import CleanerCore
import SwiftUI

struct CleanupAdvisorView: View {
  @EnvironmentObject var vm: AppModel
  @State private var rule = "all"
  @State private var query = ""
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
        Button(vm.t("Обновить анализ", "Refresh analysis")) { vm.refreshRecommendations() }.oxyHelp(
          .advisor
        )
        .disabled(vm.busy || vm.recommendationsLoading)
      }
      HStack {
        Picker(vm.t("Правило", "Rule"), selection: $rule) {
          Text(vm.t("Все", "All")).tag("all")
          Text(vm.t("Установщики · от 90 дней", "Installers · 90+ days")).tag("oldInstaller")
          Text(vm.t("Крупные старые · от 500 MB и 180 дней", "Large & old · 500 MB and 180+ days"))
            .tag("largeOldFile")
        }.oxyHelp(.rule)
        TextField(vm.t("Поиск по имени или пути", "Search name or path"), text: $query).oxyHelp(
          .search
        )
        .textFieldStyle(.roundedBorder)
      }
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
        List(filtered.prefix(1000)) { candidate in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(candidate.file.name).font(.headline).lineLimit(1)
              Spacer()
              Text(size(candidate.file.bytes)).monospacedDigit()
            }
            Text(candidate.file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
              .truncationMode(.middle).help(candidate.file.path)
            Text(reason(candidate)).font(.callout)
            Text(
              vm.t("Не изменялся: ", "Last modified: ")
                + candidate.file.modified.formatted(date: .abbreviated, time: .omitted)
                + " · \(candidate.ageDays) " + vm.t("дней", "days")
            ).font(.caption).foregroundStyle(.secondary)
            HStack {
              Button(vm.t("Проверить и показать", "Validate & reveal")) {
                vm.reviewCandidate(candidate)
              }.oxyHelp(.review).disabled(vm.busy)
              Button(vm.t("Не предлагать этот файл", "Exclude this file")) {
                vm.protect(candidate.file.path)
              }.oxyHelp(.protect).disabled(vm.busy)
            }
          }.padding(.vertical, 8)
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
      Text(
        vm.t(
          "Очистка Xcode, зависимостей и сессий агентов требует отдельных проверок активности и восстановления — эти рекомендации ещё не включены.",
          "Xcode, dependencies and agent sessions require dedicated activity and recovery checks; these recommendations are not enabled yet."
        )
      ).font(.caption).foregroundStyle(.secondary)
    }.onAppear { vm.refreshRecommendations() }
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
