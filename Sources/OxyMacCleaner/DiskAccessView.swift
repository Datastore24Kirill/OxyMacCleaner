import CleanerCore
import SwiftUI

struct DiskAccessView: View {
  @EnvironmentObject var vm: AppModel
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label(vm.t("Доступ к диску", "Disk access"), systemImage: "externaldrive.badge.person.crop")
        .font(.title2.bold())
      Text(
        vm.t(
          "Для полного обхода диска включите OxyMac Cleaner в настройках macOS → Конфиденциальность и безопасность → Полный доступ к диску.",
          "For broader disk scanning, enable OxyMac Cleaner in System Settings → Privacy & Security → Full Disk Access."
        ))
      Label(
        status, systemImage: vm.diskAccess?.state == .available ? "checkmark.shield" : "info.circle"
      )
      .foregroundStyle(vm.diskAccess?.state == .available ? Color.teal : Color.orange)
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
          .buttonStyle(.borderedProminent)
        Button(vm.t("Показать приложение", "Show app in Finder")) {
          vm.reveal(Bundle.main.bundlePath)
        }
      }
      Text(
        vm.t(
          "После обновления проверяем доступ заново. Если галочка уже включена, но проверка показывает отказ: полностью закройте приложение и запустите эту копию. Если отказ остаётся — удалите только старую запись OxyMac Cleaner кнопкой «−», добавьте эту копию через «+» и снова запустите её.",
          "Access is checked again after updates. If the toggle is enabled but access is denied, quit and reopen this copy. If access is still denied, remove only the old OxyMac Cleaner entry with “−”, add this copy with “+”, and reopen it."
        )
      )
      .font(.callout)
      Text(
        vm.t(
          "В этой Preview-сборке нет Developer ID: сохранение разрешения между обновлениями пока не гарантируется. Приложение не сбрасывает ваши разрешения автоматически.",
          "This preview has no Developer ID signature: permissions may not persist across updates. The app never resets your permissions automatically."
        )
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        Button(vm.t("Проверить снова", "Check again")) { vm.checkDiskAccess() }
        if let date = vm.diskAccessCheckedAt {
          Text(date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(
            .secondary)
        }
        Spacer()
        Button(
          vm.pendingDiskScan
            ? vm.t("Сканировать доступное", "Scan accessible files") : vm.t("Готово", "Done")
        ) {
          let scan = vm.pendingDiskScan
          vm.pendingDiskScan = false
          vm.diskAccessAcknowledged = true
          dismiss()
          if scan { vm.scan() }
        }
      }
    }.padding(28).frame(width: 660)
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
