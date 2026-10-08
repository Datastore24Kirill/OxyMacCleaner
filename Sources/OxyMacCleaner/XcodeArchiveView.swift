import CleanerCore
import SwiftUI

struct XcodeArchiveView: View {
  @EnvironmentObject var vm: AppModel
  @State private var query = ""
  @State private var selected: Set<String> = []
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
        Button(vm.t("Обновить список", "Refresh list")) { vm.scanArchives() }.oxyHelp(
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
        Menu(vm.t("Ещё", "More")) {
          Button(vm.t("В карантин…", "Quarantine…")) {
            vm.quarantineExcessArchives()
          }.oxyHelp(.archiveBatch).disabled(vm.busy || beyond.isEmpty)
        }.help(
          vm.t(
            "Перенести сверх лимита в карантин вместо удаления.",
            "Quarantine archives beyond the limit instead of deleting.")
        )
        .fixedSize()
      }
      Toggle(
        vm.t("Сделать резервную копию перед удалением", "Back up before deleting"),
        isOn: $vm.archiveBackupBeforeDelete
      )
      .oxyHelp(.backupOption).disabled(vm.busy)
      Text(
        vm.t(
          "Удаление — без Корзины, после одного подтверждения. Копия необязательна. В меню «Ещё» можно выбрать карантин с восстановлением. Архивы выпущенных версий защитите отметкой «Не удалять».",
          "Delete without Trash after one confirmation. Backup is optional. More offers quarantine with restoration. Protect released archives using Keep protected."
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
              "Проверка символов — отдельная диагностика, для очистки она не обязательна. Копирование и карантин тоже необязательны. Без сохранённой копии удалённый архив восстановить из приложения нельзя.",
              "Symbol checking is optional diagnostics, not a cleanup prerequisite. Backup and quarantine are optional too. Without a saved copy, a deleted archive cannot be restored by this app."
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
          "Лимит действует на массовую очистку. Отдельный архив, даже последний, можно удалить или перенести в карантин через «Действия с архивом». «Не удалять» защищает архив от очистки независимо от лимита. Такие архивы сохраняются дополнительно. Группируем по Bundle ID и команде; неполные метаданные не участвуют в рекомендациях.",
          "The limit applies to bulk cleanup. Archive actions can delete or quarantine an individual archive, including the last one. Keep protected excludes the archive from cleanup regardless of the limit. These archives are kept additionally. Grouping uses Bundle ID and team; incomplete metadata is excluded from recommendations."
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
      let chosen = archives.filter { selected.contains($0.path) && ArchiveRetention.permits(decisions[$0.path], explicitlySelected: true) }
      SelectionControls(count: chosen.count, bytes: chosen.reduce(0) { $0 + $1.bytes },
        canSelect: archives.contains { ArchiveRetention.permits(decisions[$0.path], explicitlySelected: true) },
        select: { selected = Set(archives.filter { ArchiveRetention.permits(decisions[$0.path], explicitlySelected: true) }.map(\.path)) },
        clear: { selected = [] })
      HStack {
        Button(vm.t("Удалить выбранные…", "Delete selected…"), role: .destructive) {
          vm.processSelectedArchives(chosen, deleteImmediately: true)
        }
        Button(vm.t("В карантин выбранные…", "Quarantine selected…")) {
          vm.processSelectedArchives(chosen, deleteImmediately: false)
        }
      }.disabled(vm.busy || chosen.isEmpty)
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
            Toggle(vm.t("Выбрать ", "Select ") + archive.name, isOn: Binding(
              get: { selected.contains(archive.path) },
              set: { if $0 { selected.insert(archive.path) } else { selected.remove(archive.path) } }
            )).labelsHidden().toggleStyle(.checkbox)
              .disabled(vm.busy || !ArchiveRetention.permits(decisions[archive.path], explicitlySelected: true))
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
                "Проверены UUID и архитектуры. Полнота отладочной информации не проверялась. Эта диагностика не требуется для очистки.",
                "UUIDs and architectures checked. Debug information completeness has not been verified. This diagnostic is not required for cleanup."
              )
            ).font(.caption).foregroundStyle(.secondary)
          }
          Menu(vm.t("Действия с архивом", "Archive actions")) {
            Button(vm.t("Копировать путь", "Copy path")) { vm.copyPath(archive.path) }
            Button(vm.t("Проверить символы отладки", "Check debug symbols")) {
              vm.checkArchiveSymbols(archive)
            }.oxyHelp(.symbols)
            Button(vm.t("Резервная копия…", "Back up archive…")) { vm.backupArchive(archive) }
              .oxyHelp(.backup)
            if ArchiveRetention.permits(decisions[archive.path], explicitlySelected: true) {
              Button(vm.t("Удалить…", "Delete…"), role: .destructive) {
                vm.deleteArchive(archive)
              }.help(vm.t("Удалить только этот архив после проверки и подтверждения. Без Корзины. Лимит хранения не мешает ручному выбору.", "Delete only this archive after checks and confirmation, without Trash. Manual selection overrides the count limit."))
              Button(vm.t("В карантин…", "Quarantine…")) { vm.quarantineArchive(archive) }.oxyHelp(
                .archiveQuarantine)
                .help(vm.t("Перенести только этот архив, даже последний. Можно восстановить; место пока не освободится.", "Move only this archive, including the last one. Restorable, but space is not freed yet."))
            }
          }.fixedSize().disabled(vm.busy)
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
          "«Сверх лимита» означает только повод для проверки, а не безопасное удаление. Архивы и dSYM выпущенных версий могут понадобиться для разбора сбоев. Свежие изменения за последние 10 минут защищены. Копия и проверка символов необязательны. На странице показано 10 архивов.",
          "Beyond the limit means review, not safe deletion. Released archives and dSYMs may be needed to diagnose crashes. Changes within the last 10 minutes are protected. Backup and symbol checks are optional. 10 archives per page."
        )
      ).font(.caption).foregroundStyle(.secondary)
    }
    .modifier(InventoryLoading(isLoaded: vm.archiveScanDate != nil, load: vm.scanArchives))
    .onChange(of: query) { _, _ in archivePage = 0; selected = [] }
    .onChange(of: onlyReview) { _, _ in archivePage = 0; selected = [] }
    .onChange(of: vm.pinnedArchives) { _, _ in selected.subtract(vm.pinnedArchives) }
    .onChange(of: vm.archiveInventory.archives.count) { _, _ in archivePage = 0; selected = [] }
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
        "Сверх лимита: можно выбрать для очистки",
        "Beyond limit: review for cleanup")
    default:
      return vm.t(
        "Ручная проверка: недостаточно достоверных данных",
        "Manual review: insufficient reliable metadata")
    }
  }
}
