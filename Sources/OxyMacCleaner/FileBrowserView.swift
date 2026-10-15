import CleanerCore
import SwiftUI

struct FileBrowserView: View {
  @EnvironmentObject var vm: AppModel
  @State private var ownership = OwnershipCatalog()
  @State private var query = FileBrowserIndex.Query()
  @State private var result = FileBrowserIndex.Result()
  @State private var loading = false
  @State private var retry = 0
  @State private var fraction = 0.0
  @State private var activeToken: Cancellation?
  @State private var failure: String?
  @State private var loadedRequest: Request?
  private var request: Request { Request(retry: retry, revision: vm.reportRevision, exclusions: vm.exclusions, archives: vm.page == "archives", query: query) }
  private struct Request: Hashable { let retry: Int; let revision: Int; let exclusions: [String]; let archives: Bool; let query: FileBrowserIndex.Query }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionIntro(icon: "folder.fill", title: vm.t("Выберите ненужное", "Choose what you no longer need"),
        subtitle: vm.t("Отметьте файлы и переместите в карантин. Их можно восстановить.", "Select files and move them to quarantine. You can restore them."))
      HStack {
        TextField(vm.t("Поиск файла или пути", "Search file or path"), text: $query.text).textFieldStyle(.roundedBorder)
        if vm.page != "archives" {
          Picker(vm.t("Тип", "Type"), selection: $query.category) {
            Text(vm.t("Все типы", "All types")).tag("all")
            ForEach(FileCategory.allCases, id: \.rawValue) { type in Text(vm.t(type.russian, type.english)).tag(type.rawValue) }
          }.frame(maxWidth: 220)
        }
        Menu {
          Picker(vm.t("Заявленный размер", "Logical size"), selection: $query.minimumMB) {
            Text(vm.t("Любой", "Any")).tag(0); Text("≥ 100 MB").tag(100); Text("≥ 1 GB").tag(1000)
          }
          Picker(vm.t("Не изменялись", "Unmodified for"), selection: $query.olderThanDays) {
            Text(vm.t("Любая дата", "Any date")).tag(0); Text(vm.t("30 дней", "30 days")).tag(30)
            Text(vm.t("90 дней", "90 days")).tag(90); Text(vm.t("Год", "One year")).tag(365)
          }
          Toggle(vm.t("Показывать защищённые — только просмотр", "Show protected — review only"), isOn: $query.showProtected)
          Button(vm.t("Сбросить фильтры", "Reset filters")) { query = .init() }
        } label: { Label(vm.t("Фильтры", "Filters"), systemImage: "line.3.horizontal.decrease") }
      }
      if query.category == FileCategory.docker.rawValue {
        Text(vm.t("Диск Docker содержит контейнеры, образы и данные, включая базы данных. Здесь доступен только просмотр. Очистите ненужные объекты в Docker Desktop; не удаляйте виртуальный диск целиком.", "Docker disks contain containers, images and data, including databases. Review only here. Remove unwanted objects in Docker Desktop; do not delete the entire virtual disk."))
          .font(.callout).foregroundStyle(.secondary)
        Link(vm.t("Как освободить место в Docker", "How to reclaim Docker space"), destination: URL(string: "https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/#what-if-the-file-is-too-big")!)
      }
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top) { resultSummary; Spacer(); browserControls }
        VStack(alignment: .leading, spacing: 10) { resultSummary; browserControls }
      }.font(.callout)
      if loading {
        Text(vm.t("Подготовка списка из сохранённого снимка. Повторное сканирование диска не выполняется.", "Preparing the list from the saved snapshot. The disk is not being scanned again."))
          .font(.caption).foregroundStyle(.secondary)
      }
      Text(vm.t("Сортировка и фильтр размера — по заявленному размеру. Выделенные блоки APFS могут быть общими: это не обещание освобождаемого места.", "Size sorting and filtering use logical size. APFS blocks may be shared: allocated space is not guaranteed reclaimable space."))
        .font(.caption).foregroundStyle(.secondary)
      if !activeFilters.isEmpty {
        Text(vm.t("Фильтры: ", "Filters: ") + activeFilters.joined(separator: " · ")).font(.caption)
      }
      if result.hiddenProtected > 0 {
        Text(vm.t("Скрыты защищённые объекты: ", "Protected items hidden: ") + "\(result.hiddenProtected). " + vm.t("Включить просмотр можно в фильтрах.", "Enable review in Filters."))
          .font(.caption).foregroundStyle(.secondary)
      }
      let selectedRows = result.rows.filter { vm.selected.contains($0.file.path) }
      SelectionControls(count: selectedRows.count, bytes: SpaceEstimate(files: selectedRows.map(\.file)).logical,
        canSelect: !loading && result.rows.contains( where: { $0.selectable }),
        select: { vm.selected = Set(result.rows.filter(\.selectable).map { $0.file.path }) },
        clear: { vm.selected = [] }, shownOnly: true)
      if let failure { HStack { Text(failure).foregroundStyle(.orange); Button(vm.t("Повторить", "Retry")) { retry += 1 } } }
      if result.rows.isEmpty && !loading && failure == nil {
        ContentUnavailableView(vm.t("Нет подходящих файлов", "No matching files"), systemImage: "doc.text.magnifyingglass",
          description: Text(vm.snapshotDate == nil ? vm.t("Сначала запустите сканирование в Обзоре.", "Run a scan from Overview first.") : vm.t("Измените фильтры. Защищённые данные скрыты по умолчанию.", "Adjust filters. Protected data is hidden by default.")))
      } else {
        List(result.rows, id: \.file.path) { row in
          HStack(spacing: 12) {
            Toggle(row.file.name, isOn: Binding(get: { vm.selected.contains(row.file.path) }, set: { if $0 { vm.selected.insert(row.file.path) } else { vm.selected.remove(row.file.path) } }))
              .labelsHidden().toggleStyle(.checkbox).disabled(!row.selectable || vm.busy || loading)
            Image(systemName: row.selectable ? "doc.fill" : "lock.doc.fill").foregroundStyle(row.selectable ? Color.teal : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
              Text(row.file.name).lineLimit(1)
              let owner = ownership.identify(row.file.path, home: vm.home, russian: vm.language != "en")
              Text(owner.label(russian: vm.language != "en")).font(.caption2).foregroundStyle(.secondary).help(owner.evidence)
              Text(row.file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(row.file.path)
            }
            Spacer()
            VStack(alignment: .trailing) {
              Text(ByteCountFormatter.string(fromByteCount: row.file.bytes, countStyle: .file)).monospacedDigit()
              if row.file.allocated != row.file.bytes || row.category == FileCategory.docker.rawValue {
                Text(vm.t("Выделено: ", "Allocated: ") + ByteCountFormatter.string(fromByteCount: row.file.allocated, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
              }
            }
            Menu { FileActions(path: row.file.path, file: row.file) } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
              .accessibilityLabel(vm.t("Действия с файлом", "File actions"))
          }.padding(.vertical, 4).contextMenu { FileActions(path: row.file.path, file: row.file) }
        }.listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 14))
      }
      ViewThatFits(in: .horizontal) {
        HStack { pagination; Spacer(); quarantineButton(selectedRows) }
        VStack(alignment: .leading, spacing: 10) { pagination; quarantineButton(selectedRows) }
      }
    }.task(id: vm.dataProject) {
      let roots = [URL(fileURLWithPath: "/Applications"), vm.home.appendingPathComponent("Applications")]
      let projects = [vm.dataProject, vm.worktreeRepository].compactMap { $0 }
      let token = Cancellation()
      if let catalog = try? await withTaskCancellationHandler(operation: {
        try await Task.detached { try OwnershipCatalog.load(appRoots: roots, projectRoots: projects, cancellation: token) }.value
      }, onCancel: { token.cancel() }), !Task.isCancelled { ownership = catalog }
    }.onAppear {
      query.category = vm.categoryFilter; query.text = vm.search
    }.task(id: request) {
      let current = request
      let token = Cancellation(); activeToken = token
      let expanding = loadedRequest.map {
        $0.revision == current.revision && $0.exclusions == current.exclusions
          && $0.archives == current.archives && current.query.isPageExpansion(of: $0.query)
      } ?? false
      if !expanding { vm.selected = []; result = .init() }
      loading = true; fraction = 0; failure = nil
      do {
        try await Task.sleep(for: .milliseconds(100))
        try token.check()
        let index = try await vm.browserIndex()
        var configured = current.query; configured.archivesAndDownloads = current.archives
        let filter = configured
        let output = try await withTaskCancellationHandler {
          try await Task.detached { try index.filter(filter, cancellation: token) { value in
            Task { @MainActor in if activeToken === token && !token.cancelled { fraction = value } }
          } }.value
        } onCancel: { token.cancel() }
        try Task.checkCancellation()
        try token.check()
        guard current == request, activeToken === token else { return }
        vm.selected.formIntersection(Set(output.rows.filter(\.selectable).map { $0.file.path }))
        result = output; loadedRequest = current; loading = false
      } catch {
        if !Task.isCancelled, current == request, activeToken === token { failure = error is CancellationError ? vm.t("Подготовка остановлена. Нажмите «Повторить» или измените фильтр.", "Preparation stopped. Retry or change a filter.") : error.localizedDescription; loading = false }
      }
    }
  }

  private var activeFilters: [String] {
    var filters: [String] = []
    if query.minimumMB > 0 { filters.append("≥ \(query.minimumMB) MB") }
    if query.olderThanDays > 0 {
      filters.append(vm.t("Без изменений от ", "Unmodified for ") + "\(query.olderThanDays) " + vm.t("дней", "days"))
    }
    return filters
  }

  @ViewBuilder private var resultSummary: some View {
    if loading && result.rows.isEmpty {
      Text(vm.t("Готовим список из сохранённого снимка…", "Preparing the list from the saved snapshot…"))
        .fontWeight(.semibold)
    } else {
      VStack(alignment: .leading, spacing: 4) {
        Label("\(result.matches) " + vm.t("файлов", "files"), systemImage: "doc.on.doc")
        Text(vm.t("Заявлено: ", "Logical: ") + ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)).bold().monospacedDigit()
        Text(vm.t("Выделено: ", "Allocated: ") + ByteCountFormatter.string(fromByteCount: result.allocatedBytes, countStyle: .file)).monospacedDigit()
      }
    }
  }

  private var browserControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(vm.t("Папки на карте", "Explore folders")) { vm.page = "map" }
      if loading {
        Text(vm.t(result.rows.isEmpty ? "Подготовка списка" : "Загружаем следующие файлы", result.rows.isEmpty ? "Preparing list" : "Loading more files") + " · \(Int(fraction * 100))%")
          .font(.caption).monospacedDigit()
        HStack {
          ProgressView(value: fraction).frame(width: 120)
          Button(vm.t("Остановить", "Stop")) { activeToken?.cancel() }
        }
      }
    }
  }

  private var pagination: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !result.rows.isEmpty {
        Text(vm.t("Показано ", "Showing ") + "\(result.rows.count)" + vm.t(" из ", " of ") + "\(result.matches)")
          .font(.caption).monospacedDigit()
      }
      if result.rows.count < result.matches {
        Button(vm.t(loading ? "Загружаем…" : "Показать ещё 200", loading ? "Loading…" : "Show 200 more")) { query.limit += 200 }
          .disabled(loading)
      }
      Text(vm.t("Карантин пока занимает место на диске.", "Quarantine still occupies disk space."))
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func quarantineButton(_ selectedRows: [FileBrowserIndex.Row]) -> some View {
    Button { vm.quarantineSelected(paths: Set(selectedRows.map { $0.file.path })) } label: {
      Label(vm.t("В карантин", "Quarantine") + " (\(selectedRows.count))", systemImage: "archivebox")
    }.buttonStyle(.borderedProminent).tint(.teal).disabled(selectedRows.isEmpty || loading || vm.busy)
  }

}
