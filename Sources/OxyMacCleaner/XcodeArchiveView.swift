import CleanerCore
import SwiftUI

struct XcodeArchiveView: View {
  @EnvironmentObject var vm: AppModel
  @State private var query = ""
  @State private var onlyReview = false
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
        Button(vm.t("Прочитать архивы Xcode", "Read Xcode archives")) { vm.scanArchives() }
          .disabled(vm.busy)
        Button(vm.t("Другая папка…", "Another folder…")) { vm.chooseArchiveRoot() }.disabled(
          vm.busy)
        Spacer()
        if vm.archivesLoading { ProgressView().controlSize(.small) }
      }
      Text(vm.archiveRoot.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      Stepper(value: $vm.archiveKeep, in: 1...20) {
        Text(
          vm.t(
            "Сохранять последние \(vm.archiveKeep) для каждого приложения",
            "Keep the latest \(vm.archiveKeep) per application"))
      }
      Text(
        vm.t(
          "Закреплённые архивы сохраняются дополнительно. Группируем по Bundle ID и команде; неполные метаданные не участвуют в рекомендациях.",
          "Pinned archives are kept additionally. Grouping uses Bundle ID and team; incomplete metadata is excluded from recommendations."
        )
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        TextField(vm.t("Поиск приложения / Bundle ID", "Search app / Bundle ID"), text: $query)
          .textFieldStyle(.roundedBorder)
        Toggle(vm.t("Только сверх лимита", "Only beyond limit"), isOn: $onlyReview)
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
      ForEach(archives.prefix(200)) { archive in
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
              "Пакетов dSYM: \(archive.dsymCount). Соответствие UUID не проверено.",
              "dSYM packages: \(archive.dsymCount). UUID matching has not been verified.")
          ).font(.caption)
          if !archive.issues.isEmpty {
            Text(
              vm.t("Размер/состав неполный: ", "Size/contents incomplete: ")
                + archive.issues.prefix(2).joined(separator: "; ")
            ).font(.caption).foregroundStyle(.orange)
          }
          HStack {
            Toggle(
              vm.t("Закрепить", "Pin"),
              isOn: Binding(
                get: { vm.pinnedArchives.contains(archive.path) },
                set: { vm.pinArchive(archive.path, $0) })
            ).toggleStyle(.checkbox)
            Spacer()
            Button(vm.t("Показать в Finder", "Show in Finder")) { vm.reveal(archive.path) }
          }
        }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
      }
      Text(
        vm.t(
          "«Сверх лимита» означает только повод для проверки, а не безопасное удаление. Архивы и dSYM выпущенных версий могут понадобиться для разбора сбоев. Удаление здесь не выполняется. Показано до 200 архивов.",
          "Beyond the limit means review, not safe deletion. Released archives and dSYMs may be needed to diagnose crashes. This screen does not delete archives. Up to 200 archives shown."
        )
      ).font(.caption).foregroundStyle(.secondary)
    }
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
