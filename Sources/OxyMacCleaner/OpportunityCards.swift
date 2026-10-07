import CleanerCore
import SwiftUI

struct OpportunityCards: View {
  @EnvironmentObject var vm: AppModel
  private func size(_ value: Int64?) -> String {
    value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
      ?? vm.t("Объём не определён", "Size unknown")
  }
  private func stamp(_ date: Date?) -> String {
    date.map {
      vm.t("Проверено: ", "Checked: ") + $0.formatted(date: .abbreviated, time: .shortened)
    }
      ?? vm.t("Ещё не проверено", "Not checked yet")
  }
  private func summary(_ value: OpportunitySummary, known: Bool) -> String {
    guard known else { return vm.t("Нужна проверка", "Inspection needed") }
    return value.count == 0
      ? vm.t("Кандидатов не найдено", "No candidates found")
      : "\(value.count) · " + size(value.bytes)
  }
  var body: some View {
    LazyVGrid(
      columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12
    ) {
      opportunity(
        "Тестовые симуляторы", "Test simulators", icon: "iphone.gen3", section: "testSimulators",
        result: vm.testDeviceReadAt == nil || vm.testDeviceIssue != nil
          ? vm.t("Нужна проверка", "Inspection needed")
          : "\(vm.testDevices.count) " + vm.t("устройств", "devices"),
        date: vm.testDeviceReadAt,
        explanation: vm.t("Отдельные устройства XCTestDevices для автотестов. Просмотрите их состояние и размеры перед выбором.", "Separate XCTestDevices used by tests. Review states and sizes before selecting."),
        limitation: vm.testDeviceIssue ?? (size(vm.testDeviceSizes.isEmpty ? nil : vm.testDeviceSizes.values.reduce(0,+)) + vm.t(" · измеренная часть; экономия APFS может отличаться. Проверяется в разделе.", " · measured portion; APFS savings may differ. Inspect in the section.")))
      opportunity(
        "Данные проектов", "Project data", icon: "shippingbox", section: "projectData",
        result: vm.projectDataDate == nil || vm.projectDataIssue != nil
          ? vm.t("Нужна проверка", "Inspection needed")
          : "\(vm.projectData.count) " + vm.t("категорий для просмотра", "categories to review"),
        date: vm.projectDataDate,
        explanation: vm.t(
          "Сборочные кэши и зависимости выбранного проекта. У каждой категории свой способ восстановления.",
          "Build caches and dependencies in the chosen project. Each category explains recovery."),
        limitation: vm.projectDataIssue
          ?? vm.t(
            "Зависимости — только просмотр. Для поддерживаемых кэшей выполняются отдельные проверки перед очисткой.",
            "Dependencies are review-only. Supported caches require separate checks before cleanup."
          ))
      opportunity(
        "Рабочие деревья Git", "Git worktrees", icon: "arrow.triangle.branch", section: "worktrees",
        result: vm.worktreeReadAt == nil || vm.worktreeIssue != nil
          ? vm.t("Нужна проверка", "Inspection needed")
          : "\(vm.worktreeReviews.filter(\.eligible).count) " + vm.t("кандидатов", "candidates"),
        date: vm.worktreeReadAt,
        explanation: vm.t(
          "Дополнительные checkout без локальных данных и изменений за 30 дней. Основной checkout защищён.",
          "Linked checkouts without local changes or changes within 30 days. The main checkout is protected."
        ),
        limitation: vm.worktreeIssue
          ?? vm.t(
            "Выберите репозиторий и запустите проверку в разделе. Завершите связанные задачи агентов перед удалением.",
            "Choose a repository and inspect it in the section. Finish associated agent tasks before removal."
          ))
      opportunity(
        "Дубликаты", "Duplicates", icon: "square.on.square", section: "duplicates",
        result: summary(
          CleanupOpportunities.duplicates(vm.duplicates, exclusions: vm.exclusions),
          known: vm.duplicatesReadAt != nil),
        date: vm.duplicatesReadAt,
        explanation: vm.t(
          "Группы точных копий. Объём указан с сохранением одной копии в каждой группе. Защищённые файлы исключены.",
          "Exact-copy groups. Size preserves one copy per group. Protected files are excluded."),
        limitation: vm.t(
          "Поиск по содержимому запускается в разделе «Дубликаты». Снимок диска может быть неполным или устаревшим.",
          "Run content comparison in Duplicates. The disk snapshot may be partial or outdated."))
      opportunity(
        "Архивы Xcode", "Xcode archives", icon: "archivebox", section: "archives",
        result: summary(
          CleanupOpportunities.archives(
            vm.archiveInventory, keep: vm.archiveKeep, pinned: vm.pinnedArchives,
            exclusions: vm.exclusions),
          known: vm.archiveScanDate != nil && vm.archiveInventory.complete),
        date: vm.archiveScanDate,
        explanation: vm.t(
          "Архивы сверх вашего лимита. Сохраняем последние \(vm.archiveKeep) и отмеченные «Не удалять»; исключения учтены.",
          "Archives beyond your limit. Keep the latest \(vm.archiveKeep) plus protected archives; exclusions apply."
        ),
        limitation: vm.archiveScanDate != nil && !vm.archiveInventory.complete
          ? vm.t(
            "Проверка неполная: рекомендации скрыты. Ошибки — в разделе архивов.",
            "Inspection incomplete: suggestions hidden. See archive inspection issues.")
          : vm.t(
            "Архивы выпущенных сборок могут быть нужны для разбора сбоев. Возраст и активность проверяются перед очисткой.",
            "Released archives may be needed for crash diagnosis. Age and activity are checked before cleanup."
          ))
      opportunity(
        "Кэши проектов", "Project caches", icon: "hammer", section: "derived",
        result: summary(
          CleanupOpportunities.derived(vm.derivedCaches, exclusions: vm.exclusions),
          known: vm.derivedReadAt != nil && vm.derivedReadIssue == nil),
        date: vm.derivedReadAt,
        explanation: vm.t(
          "Категории DerivedData: промежуточные сборки, индексы и логи. Без ошибок обхода и изменений за последние 10 минут.",
          "DerivedData categories: intermediates, indexes and logs. No traversal issues or changes within 10 minutes."
        ),
        limitation: vm.derivedReadIssue.map {
          vm.t("Не удалось обновить: ", "Refresh failed: ") + $0
        }
          ?? vm.t(
            "Xcode создаст кэши заново; следующая сборка может быть дольше. Активность проверяется перед удалением.",
            "Xcode recreates these caches; the next build may take longer. Activity is checked before deletion."
          ))
      opportunity(
        "Симуляторы", "Simulators", icon: "iphone", section: "simulators",
        result: summary(
          CleanupOpportunities.simulators(vm.simulatorInventory),
          known: vm.simulatorReadAt != nil && vm.simulatorReadIssue == nil),
        date: vm.simulatorReadAt,
        explanation: vm.t(
          "Выключенные недоступные устройства и runtimes без использования от 90 дней. Занятые runtimes исключены.",
          "Shutdown unavailable devices and runtimes unused for 90+ days. Busy runtimes are excluded."
        ),
        limitation: vm.simulatorReadIssue.map {
          vm.t("Не удалось обновить: ", "Refresh failed: ") + $0
        }
          ?? (vm.simulatorInventory.runtimeIssue != nil
            ? vm.t(
              "Данные runtimes недоступны — показана только часть результатов. Удаление устройств теряет тестовые данные.",
              "Runtime data unavailable — results are partial. Deleting devices loses test data.")
            : vm.t(
              "Удаление устройств теряет тестовые данные. Runtime можно скачать заново, если версия доступна.",
              "Deleting devices loses test data. Runtimes can be downloaded again if available.")))
    }
  }
  private func opportunity(
    _ ru: String, _ en: String, icon: String, section: String,
    result: String, date: Date?, explanation: String, limitation: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(vm.t(ru, en), systemImage: icon).font(.headline)
      Text(result).font(.title3.bold())
      Text(explanation).font(.callout)
      Text(limitation).font(.caption).foregroundStyle(.secondary)
      Spacer(minLength: 0)
      HStack {
        Text(stamp(date)).font(.caption2).foregroundStyle(.secondary)
        Spacer()
        Button(vm.t("Посмотреть", "Review")) { vm.openOpportunity(section) }
          .help(
            vm.t(
              "Открывает соответствующий раздел. Ничего не выбирает и не удаляет.",
              "Opens the matching section. Does not select or delete anything.")
          )
          .disabled(vm.busy)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
  }
}
