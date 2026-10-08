import CleanerCore
import SwiftUI

struct FileBrowserView: View {
  @EnvironmentObject var vm: AppModel
  @State private var query = FileBrowserIndex.Query()
  @State private var result = FileBrowserIndex.Result()
  @State private var loading = false
  @State private var failure: String?
  private var request: Request { Request(revision: vm.reportRevision, exclusions: vm.exclusions, archives: vm.page == "archives", query: query) }
  private struct Request: Hashable { let revision: Int; let exclusions: [String]; let archives: Bool; let query: FileBrowserIndex.Query }
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
          Picker(vm.t("Размер", "Size"), selection: $query.minimumMB) {
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
      HStack {
        Label("\(result.matches) " + vm.t("файлов", "files"), systemImage: "doc.on.doc")
        Text(ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)).bold().monospacedDigit()
        Spacer()
        Button(vm.t("Папки на карте", "Explore folders")) { vm.page = "map" }
        if loading { ProgressView().controlSize(.small); Text(vm.t("Готовим список…", "Preparing list…")).font(.caption) }
      }.font(.callout)
      if query.minimumMB > 0 || query.olderThanDays > 0 {
        Text(vm.t("Фильтры: ", "Filters: ") + "≥ \(query.minimumMB) MB · " + vm.t("без изменений от ", "unmodified for ") + "\(query.olderThanDays) " + vm.t("дней", "days")).font(.caption)
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
      if let failure { Text(failure).foregroundStyle(.orange) }
      if result.rows.isEmpty && !loading {
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
              Text(row.file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(row.file.path)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: row.file.bytes, countStyle: .file)).monospacedDigit()
            Menu { FileActions(path: row.file.path, file: row.file) } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
              .accessibilityLabel(vm.t("Действия с файлом", "File actions"))
          }.padding(.vertical, 4).contextMenu { FileActions(path: row.file.path, file: row.file) }
        }.listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 14))
      }
      HStack {
        if result.rows.count < result.matches {
          Button(vm.t("Показать ещё 200", "Show 200 more")) { query.limit += 200 }.disabled(loading)
        }
        Text(vm.t("Карантин пока занимает место на диске.", "Quarantine still occupies disk space.")).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button { vm.quarantineSelected(paths: Set(selectedRows.map { $0.file.path })) } label: {
          Label(vm.t("В карантин", "Quarantine") + " (\(selectedRows.count))", systemImage: "archivebox")
        }.buttonStyle(.borderedProminent).tint(.teal).disabled(selectedRows.isEmpty || loading || vm.busy)
      }
    }.onAppear {
      query.category = vm.categoryFilter; query.text = vm.search
    }.task(id: request) {
      let current = request
      vm.selected = []; loading = true; failure = nil
      do {
        try await Task.sleep(for: .milliseconds(100))
        let index = try await vm.browserIndex()
        var filter = current.query; filter.archivesAndDownloads = current.archives
        let token = Cancellation()
        let output = try await withTaskCancellationHandler {
          try await Task.detached { try index.filter(filter, cancellation: token) }.value
        } onCancel: { token.cancel() }
        try Task.checkCancellation()
        guard current == request else { return }
        result = output; loading = false
      } catch {
        if !Task.isCancelled { failure = error.localizedDescription; loading = false }
      }
    }
  }
}
