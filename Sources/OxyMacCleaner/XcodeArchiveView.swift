import CleanerCore
import SwiftUI

struct XcodeArchiveView: View {
  @EnvironmentObject var vm: AppModel
  @State private var query = ""
  @State private var onlyReview = false
  @State private var archivePage = 0
  private var decisions: [String: ArchiveRetention.Decision] {
    ArchiveRetention.decisions(
      vm.archiveInventory.archives, keep: vm.archiveKeep, pinned: vm.pinnedArchives)
  }
  private var archives: [XcodeArchive] {
    vm.archiveInventory.archives.filter {
      (!onlyReview || decisions[$0.path] == .review)
        && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
          || ($0.bundleID ?? "").localizedCaseInsensitiveContains(query))
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(vm.t("Архивы приложений", "Application archives"), systemImage: "archivebox").font(
        .title2.bold())
      HStack {
        Button(vm.t("Прочитать архивы Xcode", "Read Xcode archives")) { vm.scanArchives() }.oxyHelp(
          .archiveRead
        )
        .disabled(vm.busy)
        Button(vm.t("Другая папка…", "Another folder…")) { vm.chooseArchiveRoot() }.oxyHelp(
          .archiveRoot
        ).disabled(
          vm.busy)
        Spacer()
        if vm.archivesLoading { ProgressView().controlSize(.small) }
      }
      let beyond = vm.archiveInventory.archives.filter { decisions[$0.path] == .review }
      HStack {
        Text(
          vm.t("Сверх лимита: ", "Beyond limit: ") + "\(beyond.count) · "
            + ByteCountFormatter.string(
              fromByteCount: beyond.reduce(0) { $0 + $1.bytes }, countStyle: .file))
        Spacer()
        Button(vm.t("Удалить сверх лимита…", "Delete beyond limit…"), role: .destructive) {
          vm.deleteExcessArchives()
        }.oxyHelp(.archiveDelete).disabled(vm.busy || beyond.isEmpty)
        Button(vm.t("В карантин…", "Quarantine…")) {
          vm.quarantineExcessArchives()
        }.oxyHelp(.archiveBatch).disabled(vm.busy || beyond.isEmpty)
      }
      Text(
        vm.t(
          "Оба действия сначала создают или проверяют полные резервные копии. «Удалить сверх лимита» удаляет оригиналы без карантина после отдельного подтверждения. Карантин — вариант с восстановлением из приложения. Копии на этом диске тоже занимают место.",
          "Both actions first create or verify full backups. Delete beyond limit removes originals without quarantine after separate confirmation. Quarantine offers in-app restoration. Backups on this disk also take space."
        )
      ).font(.caption).foregroundStyle(.secondary)
      DisclosureGroup(
        vm.t("Зачем проверять символы и делать копию?", "Why check symbols and make a backup?")
      ) {
        VStack(alignment: .leading, spacing: 10) {
          Text(vm.t(HelpTopic.symbols.text.ru, HelpTopic.symbols.text.en))
          Text(vm.t(HelpTopic.backup.text.ru, HelpTopic.backup.text.en))
          Text(
            vm.t(
              "Выберите: проверенная копия → прямое удаление или копия → карантин → удаление позже. После прямого удаления восстановление возможно только вручную из копии. Сохраните её для разбора будущих сбоев.",
              "Choose: verified backup → direct deletion, or backup → quarantine → delete later. Direct deletion requires manual recovery from backup. Keep it for future crash diagnosis."
            ))
        }.font(.callout).foregroundStyle(.secondary).padding(.top, 6)
      }.oxyHelp(.disclosure)
      DeveloperReportView()
      Text(vm.archiveRoot.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      Stepper(value: $vm.archiveKeep, in: 1...20) {
        Text(
          vm.t(
            "Сохранять последние \(vm.archiveKeep) для каждого приложения",
            "Keep the latest \(vm.archiveKeep) per application"))
      }.oxyHelp(.retention).disabled(vm.busy)
      Text(
        vm.t(
          "«Не удалять» защищает архив от очистки независимо от лимита. Такие архивы сохраняются дополнительно. Группируем по Bundle ID и команде; неполные метаданные не участвуют в рекомендациях.",
          "Keep protected excludes the archive from cleanup regardless of the limit. These archives are kept additionally. Grouping uses Bundle ID and team; incomplete metadata is excluded from recommendations."
        )
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        TextField(vm.t("Поиск приложения / Bundle ID", "Search app / Bundle ID"), text: $query)
          .oxyHelp(.search)
          .textFieldStyle(.roundedBorder)
        Toggle(vm.t("Только сверх лимита", "Only beyond limit"), isOn: $onlyReview).oxyHelp(
          .beyondFilter)
      }
      if let date = vm.archiveScanDate {
        Text(
          vm.t("Проверено: ", "Checked: ") + date.formatted()
            + " · \(vm.archiveInventory.archives.count) " + vm.t("архивов", "archives")
            + (vm.archiveInventory.complete
              ? "" : vm.t(" · неполный обход", " · partial inventory"))
        ).font(.caption)
      }
      if !vm.archiveInventory.issues.isEmpty {
        Text(vm.archiveInventory.issues.prefix(3).joined(separator: "\n")).font(.caption)
          .foregroundStyle(.orange).textSelection(.enabled)
      }
      if archives.isEmpty {
        Text(
          vm.t(
            "Архивы не загружены или не подходят под фильтр.",
            "No archives loaded or matching the filter.")
        ).foregroundStyle(.secondary).padding(.vertical)
      }
      if !archives.isEmpty {
        HStack {
          Button(vm.t("Назад", "Previous")) { archivePage -= 1 }.oxyHelp(.previous).disabled(
            archivePage == 0)
          Text(
            vm.t("Страница ", "Page ") + "\(archivePage + 1)/\(max(1, (archives.count + 9) / 10))")
          Button(vm.t("Далее", "Next")) { archivePage += 1 }.oxyHelp(.next).disabled(
            (archivePage + 1) * 10 >= archives.count)
        }
      }
      ForEach(archives.dropFirst(archivePage * 10).prefix(10)) { archive in
        VStack(alignment: .leading, spacing: 7) {
          HStack {
            Text(archive.name).font(.headline)
            Text("\(archive.version ?? "?") (\(archive.build ?? "?"))").foregroundStyle(.secondary)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: archive.bytes, countStyle: .file))
              .monospacedDigit()
          }
          Text(
            (archive.bundleID ?? vm.t("Bundle ID неизвестен", "Unknown Bundle ID")) + " · "
              + (archive.created?.formatted(date: .abbreviated, time: .shortened)
                ?? vm.t("Дата неизвестна", "Unknown date"))
          ).font(.caption).foregroundStyle(.secondary)
          Text(vm.t("Команда: ", "Team: ") + (archive.team ?? "?")).font(.caption).foregroundStyle(
            .secondary)
          Text(decision(archive)).font(.callout).foregroundStyle(
            decisions[archive.path] == .review ? Color.orange : Color.teal)
          Text(
            vm.t(
              "Пакетов dSYM: \(archive.dsymCount). Проверка соответствия символов запускается отдельно.",
              "dSYM packages: \(archive.dsymCount). Symbol matching is checked separately.")
          ).font(.caption)
          if let report = vm.archiveSymbols[archive.path] {
            Text(
              vm.t("UUID совпали: ", "UUID matches: ") + "\(report.matched)/\(report.binaries)"
                + vm.t(" бинарников", " binaries")
            )
            .foregroundStyle(report.complete ? Color.teal : Color.orange)
            if !report.missing.isEmpty {
              Text(
                vm.t("Нет полного совпадения: ", "No complete match: ")
                  + report.missing.prefix(5).joined(separator: "; ")
              ).font(.caption).textSelection(.enabled)
            }
            if !report.issues.isEmpty {
              Text(report.issues.prefix(3).joined(separator: "\n")).font(.caption).foregroundStyle(
                .orange)
            }
            Text(
              vm.t(
                "Проверены UUID и архитектуры. Полнота отладочной информации не проверялась. Перед переносом UUID проверяются заново.",
                "UUIDs and architectures checked. Debug information completeness has not been verified. UUIDs are rechecked before transfer."
              )
            ).font(.caption).foregroundStyle(.secondary)
          }
          HStack {
            Button(vm.t("Проверить символы отладки", "Check debug symbols")) {
              vm.checkArchiveSymbols(archive)
            }.oxyHelp(.symbols)
            Button(vm.t("Резервная копия…", "Back up archive…")) { vm.backupArchive(archive) }
              .oxyHelp(.backup)
            if decisions[archive.path] == .review {
              Button(vm.t("В карантин…", "Quarantine…")) { vm.quarantineArchive(archive) }.oxyHelp(
                .archiveQuarantine)
            }
          }.disabled(vm.busy)
          if !archive.issues.isEmpty {
            Text(
              vm.t("Размер/состав неполный: ", "Size/contents incomplete: ")
                + archive.issues.prefix(2).joined(separator: "; ")
            ).font(.caption).foregroundStyle(.orange)
          }
          HStack {
            Toggle(
              vm.t("Не удалять", "Keep protected"),
              isOn: Binding(
                get: { vm.pinnedArchives.contains(archive.path) },
                set: { vm.pinArchive(archive.path, $0) })
            ).oxyHelp(.pin).toggleStyle(.checkbox).disabled(vm.busy)
            Spacer()
            Button(vm.t("Показать в Finder", "Show in Finder")) { vm.reveal(archive.path) }.oxyHelp(
              .finder)
          }
        }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
      }
      Text(
        vm.t(
          "«Сверх лимита» означает только повод для проверки, а не безопасное удаление. Архивы и dSYM выпущенных версий могут понадобиться для разбора сбоев. Карантин доступен только сверх лимита, с полной проверенной копией и без изменений за 24 часа. На странице показано 10 архивов.",
          "Beyond the limit means review, not safe deletion. Released archives and dSYMs may be needed to diagnose crashes. Quarantine requires an archive beyond the retention limit, a verified full backup and no changes for 24 hours. 10 archives per page."
        )
      ).font(.caption).foregroundStyle(.secondary)
    }
    .onChange(of: query) { _, _ in archivePage = 0 }
    .onChange(of: onlyReview) { _, _ in archivePage = 0 }
    .onChange(of: vm.archiveInventory.archives.count) { _, _ in archivePage = 0 }
  }
  private func decision(_ archive: XcodeArchive) -> String {
    switch decisions[archive.path] {
    case .pinned: return vm.t("Сохраняем: закреплён вами", "Keep: pinned by you")
    case .latest:
      return vm.t(
        "Сохраняем: входит в последние \(vm.archiveKeep)",
        "Keep: among the latest \(vm.archiveKeep)")
    case .review:
      return vm.t(
        "Сверх лимита: проверьте нужность и резервную копию символов",
        "Beyond limit: review need and symbol backup")
    default:
      return vm.t(
        "Ручная проверка: недостаточно достоверных данных",
        "Manual review: insufficient reliable metadata")
    }
  }
}
