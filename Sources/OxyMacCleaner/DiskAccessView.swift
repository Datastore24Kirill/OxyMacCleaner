import CleanerCore
import SwiftUI

struct DiskAccessView: View {
  @EnvironmentObject var vm: AppModel
  @EnvironmentObject var updater: AppUpdater
  @Environment(\.dismiss) var dismiss
  @State private var copiedPath = false
  private var available: Bool { vm.diskAccess?.state == .available }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label(vm.t("Доступ к диску", "Disk access"), systemImage: "externaldrive.badge.person.crop")
        .font(.title2.bold())
      Label(
        status, systemImage: vm.diskAccess?.state == .available ? "checkmark.shield" : "info.circle"
      )
      .foregroundStyle(vm.diskAccess?.state == .available ? Color.teal : Color.orange)
      if available {
        Text(vm.t("Можно приступать к сканированию.", "You can start scanning."))
          .foregroundStyle(.secondary)
      } else {
        Text(
          vm.t(
            "Для полного обхода диска включите OxyMac Cleaner в настройках macOS → Конфиденциальность и безопасность → Полный доступ к диску.",
            "For broader disk scanning, enable OxyMac Cleaner in System Settings → Privacy & Security → Full Disk Access."
          ))
        Text(
          vm.t(
            "Проверка открывает только три защищённые папки без чтения их содержимого. Успешная проверка не гарантирует доступ ко всем файлам и не отменяет ограничения macOS.",
            "The check only opens three protected directories without reading their contents. A successful check does not guarantee access to every file or override macOS restrictions."
          )
        )
        .font(.caption).foregroundStyle(.secondary)
        Divider()
        Text(
          vm.t(
            "1. Откройте настройки и включите приложение. Если его нет в списке — добавьте через «+» или перетащите из Finder.\n2. Используйте именно эту установленную копию:\n",
            "1. Open settings and enable the app. If it is missing, add it with “+” or drag it from Finder.\n2. Use this exact installed copy:\n"
          ) + Bundle.main.bundlePath
        )
        .textSelection(.enabled).font(.callout)
        HStack {
          Button(vm.t("Открыть настройки macOS", "Open macOS settings")) { vm.openDiskSettings() }
            .oxyHelp(.openSettings)
            .buttonStyle(.borderedProminent)
          Button(vm.t("Показать приложение", "Show app in Finder")) {
            vm.reveal(Bundle.main.bundlePath)
          }.oxyHelp(.finder)
          Button(vm.t(copiedPath ? "Путь скопирован" : "Копировать путь", copiedPath ? "Path copied" : "Copy path")) {
            NSPasteboard.general.clearContents()
            copiedPath = NSPasteboard.general.setString(Bundle.main.bundlePath, forType: .string)
          }.help(vm.t("В диалоге «+» нажмите ⇧⌘G и вставьте путь к этой копии приложения.", "In the + dialog, press ⇧⌘G and paste the path to this copy of the app."))
        }
        Text(
          vm.t(
            "После выдачи доступа нажмите «Перезапустить приложение». Если галочка уже включена, а отказ остаётся, повторно добавьте эту копию через «+». Если это не помогло, удалите только старую запись OxyMac Cleaner кнопкой «−» и добавьте приложение заново.",
            "After granting access, click Restart app. If the toggle is already enabled but access is denied, add this copy again with +. If that does not help, remove only the old OxyMac Cleaner entry with − and add the app again."
          )
        )
        .font(.callout)
        Text(
          vm.t(
            "В этой сборке нет Developer ID: сохранение разрешения между обновлениями пока не гарантируется. Приложение не сбрасывает ваши разрешения автоматически.",
            "This build has no Developer ID signature: permissions may not persist across updates. The app never resets your permissions automatically."
          )
        )
        .font(.caption).foregroundStyle(.secondary)
        DisclosureGroup(vm.t("Результат проверки", "Check details")) {
          ForEach(vm.diskAccess?.checks ?? [], id: \.path) { check in
            HStack {
              Text(URL(fileURLWithPath: check.path).lastPathComponent)
              Spacer()
              Text(check.error == 0 ? vm.t("Доступно", "Accessible")
                : String(cString: strerror(check.error)) + " (\(check.error))")
                .foregroundStyle(.secondary)
            }.font(.caption)
          }
          Text(vm.t("Это результат открытия папок текущим процессом, а не чтение галочки из настроек macOS.", "These are directory-open results from this process, not the toggle state in macOS settings."))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      HStack {
        if !available {
          Button(vm.t("Проверить снова", "Check again")) { vm.checkDiskAccess() }.oxyHelp(.recheck)
          Button(vm.t("Перезапустить приложение", "Restart app")) { vm.restartForDiskAccess() }
            .disabled(vm.busy || vm.contextRunning || updater.installing || vm.restartingForAccess)
            .help(vm.t("После изменения доступа закрывает и запускает эту же копию. Недоступно во время операций. Разрешения не изменяет.", "Quits and reopens this copy after access changes. Unavailable during operations. Does not change permissions."))
          if let date = vm.diskAccessCheckedAt {
            Text(date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(
              .secondary)
          }
        }
        Spacer()
        Button(
          vm.pendingDiskScan
            ? (available
              ? vm.t("Начать сканирование", "Start scanning")
              : vm.t("Сканировать доступное", "Scan accessible files")) : vm.t("Готово", "Done")
        ) {
          let scan = vm.pendingDiskScan
          vm.pendingDiskScan = false
          vm.diskAccessAcknowledged = true
          dismiss()
          if scan { vm.scan() }
        }.oxyHelp(.accessDone)
      }
    }.padding(28).frame(width: available ? 440 : 660)
      .onAppear { vm.checkDiskAccess() }
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in vm.checkDiskAccess() }
      .onDisappear {
        UserDefaults.standard.set(vm.permissionBuild, forKey: "permissionReviewedBuild")
      }
  }
  private var status: String {
    switch vm.diskAccess?.state {
    case .available:
      return vm.t(
        "Проверенные защищённые папки доступны", "Checked protected directories are accessible")
    case .limited:
      return vm.t(
        "Есть отказ в доступе. Полный обход будет неполным.",
        "Access was denied. The scan will be incomplete.")
    default:
      return vm.t(
        "Доступ не подтверждён: контрольные папки отсутствуют или недоступны по другой причине.",
        "Access is unconfirmed: probe directories are missing or another error occurred.")
    }
  }
}
