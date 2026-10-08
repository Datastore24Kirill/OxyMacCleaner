import CleanerCore
import SwiftUI

struct CleanupAdvisorView: View {
  @EnvironmentObject var vm: AppModel
  @State private var rule = "all"
  @State private var query = ""
  @State private var selected: Set<String> = []
  private var filtered: [CleanupCandidate] {
    vm.recommendations.filter {
      (rule == "all" || $0.rule.rawValue == rule)
        && (query.isEmpty || $0.file.path.localizedCaseInsensitiveContains(query))
    }
  }
  private func size(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text(vm.t("Кандидаты для вашего просмотра", "Candidates for your review")).font(
          .title3.bold())
        Text(
          vm.t(
            "Это не список мусора. Возраст и размер помогают выбрать, что проверить; решение остаётся за вами. Ничего не выбрано для удаления.",
            "This is not a junk list. Age and size help prioritize review; you decide what to keep. Nothing is selected for deletion."
          )
        )
        .foregroundStyle(.secondary)
        HStack {
          Button(vm.t("Обновить сводку", "Refresh summary")) { vm.refreshOpportunities() }
            .help(
              vm.t(
                "Пересчитывает личные файлы по снимку и читает архивы Xcode, DerivedData и симуляторы. Поиск дубликатов запускается отдельно. Ничего не удаляет.",
                "Recalculates personal-file suggestions and reads Xcode archives, DerivedData and simulators. Duplicate search runs separately. Deletes nothing."
              )
            )
            .disabled(vm.busy || vm.recommendationsLoading)
          if vm.busy {
            ProgressView().controlSize(.small)
            Text(vm.status).font(.caption).foregroundStyle(.secondary)
            Button(vm.t("Остановить", "Stop")) { vm.cancel() }.help(
              vm.t(
                "Останавливает текущую проверку. Команда чтения симуляторов может завершиться не сразу.",
                "Stops the current inspection. Simulator inventory commands may take time to finish."
              ))
          }
        }
        OpportunityCards().environmentObject(vm)
        Text(
          vm.t(
            "Категории могут пересекаться: объёмы не складываются и не обещают фактическую экономию. Переход в раздел ничего не выбирает для удаления.",
            "Categories can overlap: sizes are not added or guaranteed savings. Opening a section selects nothing for deletion."
          )
        )
        .font(.caption).foregroundStyle(.secondary)
        Divider()
        Text(vm.t("Личные файлы из снимка диска", "Personal files from the disk snapshot")).font(
          .headline)
        HStack {
          Label(
            "\(vm.recommendations.count) " + vm.t("файлов", "files"),
            systemImage: "doc.text.magnifyingglass")
          Text(size(vm.recommendations.reduce(0) { $0 + $1.file.bytes })).bold()
          Text(
            vm.t(
              "объём кандидатов, не гарантированная экономия",
              "candidate size, not guaranteed reclaimable space")
          ).font(.caption).foregroundStyle(.secondary)
          Spacer()
          if vm.recommendationsLoading { ProgressView().controlSize(.small) }
          Button(vm.t("Обновить по снимку", "Refresh from snapshot")) {
            vm.refreshRecommendations()
          }.oxyHelp(
            .advisor
          )
          .disabled(vm.busy || vm.recommendationsLoading)
        }
        HStack {
          Picker(vm.t("Правило", "Rule"), selection: $rule) {
            Text(vm.t("Все", "All")).tag("all")
            Text(vm.t("Установщики · от 90 дней", "Installers · 90+ days")).tag("oldInstaller")
            Text(
              vm.t("Крупные старые · от 500 MB и 180 дней", "Large & old · 500 MB and 180+ days")
            )
            .tag("largeOldFile")
          }.oxyHelp(.rule)
          TextField(vm.t("Поиск по имени или пути", "Search name or path"), text: $query).oxyHelp(
            .search
          )
          .textFieldStyle(.roundedBorder)
        }
        let shown = Array(filtered.prefix(1000))
        let chosen = shown.map(\.file).filter { selected.contains($0.path) }
        SelectionControls(count: chosen.count, bytes: SpaceEstimate(files: chosen).logical,
          canSelect: shown.contains { vm.fileSelectable($0.file) },
          select: { selected = Set(shown.filter { vm.fileSelectable($0.file) }.map { $0.file.path }) },
          clear: { selected = [] }, shownOnly: true)
        Button(vm.t("В карантин выбранные…", "Quarantine selected…")) {
          vm.quarantineSelected(paths: Set(chosen.map(\.path)))
        }.disabled(vm.busy || chosen.isEmpty)
        if vm.snapshotDate == nil {
          ContentUnavailableView(
            vm.t("Сначала выполните сканирование", "Scan first"), systemImage: "externaldrive")
        } else if filtered.isEmpty && !vm.recommendationsLoading {
          ContentUnavailableView(
            vm.t("Нет кандидатов по этим правилам", "No candidates match these rules"),
            systemImage: "checkmark.seal",
            description: Text(
              vm.t(
                "Проверены только файлы текущего снимка в личных папках. Неполный обход не означает, что на диске нет других возможностей очистки.",
                "Only files in personal folders from the current snapshot were considered. A partial scan does not rule out other cleanup opportunities."
              )))
        } else {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(filtered.prefix(1000))) { candidate in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Toggle(candidate.file.name, isOn: Binding(
                    get: { selected.contains(candidate.file.path) },
                    set: { if $0 { selected.insert(candidate.file.path) } else { selected.remove(candidate.file.path) } }
                  )).toggleStyle(.checkbox).disabled(vm.busy || !vm.fileSelectable(candidate.file)).font(.headline).lineLimit(1)
                  Spacer()
                  Text(size(candidate.file.bytes)).monospacedDigit()
                }
                Text(candidate.file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                  .truncationMode(.middle).help(candidate.file.path)
                Text(reason(candidate)).font(.callout)
                CleanupExplanationView(section: "personal")
                Text(
                  vm.t("Не изменялся: ", "Last modified: ")
                    + candidate.file.modified.formatted(date: .abbreviated, time: .omitted)
                    + " · \(candidate.ageDays) " + vm.t("дней", "days")
                ).font(.caption).foregroundStyle(.secondary)
                HStack {
                  Button(vm.t("Проверить и показать", "Validate & reveal")) {
                    vm.reviewCandidate(candidate)
                  }.oxyHelp(.review).disabled(vm.busy)
                  Menu(vm.t("Действия", "Actions")) { FileActions(path: candidate.file.path, file: candidate.file) }
                  Button(vm.t("Не предлагать этот файл", "Exclude this file")) {
                    vm.protect(candidate.file.path)
                  }.oxyHelp(.protect).disabled(vm.busy)
                }
              }.padding(.vertical, 8)
              Divider()
            }
          }
        }
        HStack {
          Text(
            vm.t(
              "Показано до 1000 кандидатов. Последнее использование не определяется по дате изменения.",
              "Up to 1,000 candidates shown. Modification time does not indicate last use.")
          ).font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button(vm.t("Проверить точные дубликаты", "Check exact duplicates")) {
            vm.page = "duplicates"
          }.oxyHelp(.duplicatesPage)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.onAppear { vm.refreshRecommendations() }
      .onChange(of: query) { _, _ in selected = [] }
      .onChange(of: rule) { _, _ in selected = [] }
      .onChange(of: vm.recommendations.count) { _, _ in selected = [] }
  }
  private func reason(_ candidate: CleanupCandidate) -> String {
    switch candidate.rule {
    case .oldInstaller:
      return vm.t(
        "Установочный файл в «Загрузках», не изменявшийся минимум 90 дней. Проверьте, нужен ли он для повторной установки.",
        "Installer in Downloads, unmodified for at least 90 days. Check whether you need it for reinstallation."
      )
    case .largeOldFile:
      return vm.t(
        "Личный файл от 500 MB, не изменявшийся минимум 180 дней. Может быть важным архивом — сначала просмотрите его.",
        "Personal file of at least 500 MB, unmodified for at least 180 days. It may be an important archive; review it first."
      )
    }
  }
}
