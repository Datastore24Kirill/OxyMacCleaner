import CleanerCore
import SwiftUI

struct DiskAccessView: View {
  @EnvironmentObject var vm: AppModel
  @EnvironmentObject var updater: AppUpdater
  @Environment(\.dismiss) var dismiss
  @State private var copiedPath = false
  private var available: Bool { vm.diskAccess?.state == .available }
  private var limited: Bool { vm.diskAccess?.state == .limited }
  private var restartBlocked: Bool {
    vm.busy || vm.contextRunning || updater.installing || vm.restartingForAccess
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label(vm.t("Доступ к диску", "Disk access"), systemImage: "externaldrive.badge.person.crop")
        .font(.title2.bold())
      Label(status, systemImage: available ? "checkmark.shield" : "info.circle")
        .foregroundStyle(available ? Color.teal : Color.orange)
        .fixedSize(horizontal: false, vertical: true)
      if available {
        Text(vm.t("Можно приступать к сканированию.", "You can start scanning."))
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          accessInstructions
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
        .frame(maxHeight: 360)
        Divider()
      }
      footer
    }
    .padding(28)
    .frame(width: available ? 440 : 640)
    .onAppear { vm.checkDiskAccess() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in vm.checkDiskAccess()
    }
    .onDisappear {
      UserDefaults.standard.set(vm.permissionBuild, forKey: "permissionReviewedBuild")
    }
  }

  private var accessInstructions: some View {
    VStack(alignment: .leading, spacing: 16) {
      if limited {
        Text(vm.t(
          "В настройках macOS откройте «Конфиденциальность и безопасность → Полный доступ к диску» и разрешите доступ OxyMac Cleaner. Если доступ уже включён, раскройте инструкцию ниже.",
          "In System Settings, open Privacy & Security → Full Disk Access and enable OxyMac Cleaner. If access is already enabled, expand the instructions below."))
        Button(vm.t("Открыть настройки macOS", "Open macOS settings")) { vm.openDiskSettings() }
          .buttonStyle(.borderedProminent).oxyHelp(.openSettings)
      } else {
        Text(vm.t(
          "Контрольные папки отсутствуют или проверке помешала другая ошибка. Это не обязательно означает, что разрешение выключено. Повторите проверку или посмотрите подробности ниже.",
          "Probe directories are missing or another error prevented verification. This does not necessarily mean permission is disabled. Retry the check or review the details below."))
        Button(vm.t("Проверить снова", "Check again")) { vm.checkDiskAccess() }
          .buttonStyle(.borderedProminent).oxyHelp(.recheck)
      }
      Text(vm.t(
        "Можно сканировать доступные файлы. Недоступные папки будут отмечены в результате.",
        "You can scan accessible files. Inaccessible directories will be noted in the result."))
        .font(.callout).foregroundStyle(.secondary)
      DisclosureGroup(vm.t(
        "Доступ уже включён или приложение обновилось?",
        "Access already enabled, or app recently updated?")) {
        recovery.padding(.top, 10)
      }
      DisclosureGroup(vm.t("Технические подробности", "Technical details")) {
        diagnostics.padding(.top, 10)
      }
    }
  }

  private var recovery: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(vm.t(
        "1. После изменения доступа перезапустите эту копию приложения.",
        "1. After changing access, restart this copy of the app."))
      Button(vm.t(
        vm.restartingForAccess ? "Перезапускаем…" : "Перезапустить приложение",
        vm.restartingForAccess ? "Restarting…" : "Restart app")) { vm.restartForDiskAccess() }
        .disabled(restartBlocked)
        .help(vm.t(
          "Закрывает и запускает эту же копию приложения. Разрешения не изменяет.",
          "Quits and reopens this copy of the app. Does not change permissions."))
      if restartBlocked {
        Text(vm.t(
          vm.restartingForAccess
            ? "Запущен перезапуск приложения."
            : "Перезапуск станет доступен после завершения текущей операции.",
          vm.restartingForAccess
            ? "App restart has started."
            : "Restart will be available when the current operation finishes."))
          .font(.caption).foregroundStyle(.secondary)
      }
      Text(vm.t(
        "2. Если отказ остался, снова добавьте именно эту копию через «+» в разделе «Полный доступ к диску».",
        "2. If access is still denied, add this exact copy again using + in Full Disk Access."))
      Text(Bundle.main.bundlePath)
        .font(.caption.monospaced()).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      ViewThatFits(in: .horizontal) {
        HStack { locationButtons }
        VStack(alignment: .leading, spacing: 8) { locationButtons }
      }
      Text(vm.t(
        "В диалоге «+» нажмите ⇧⌘G и вставьте скопированный путь. Затем перезапустите приложение.",
        "In the + dialog, press ⇧⌘G and paste the copied path. Then restart the app."))
        .font(.caption).foregroundStyle(.secondary)
      if !limited {
        Button(vm.t("Открыть настройки macOS", "Open macOS settings")) { vm.openDiskSettings() }
          .oxyHelp(.openSettings)
      }
      Text(vm.t(
        "Если повторное добавление не помогло, удалите только старую запись OxyMac Cleaner кнопкой «−» и добавьте эту копию заново.",
        "If adding the app again did not help, remove only the old OxyMac Cleaner entry using − and add this copy again."))
        .font(.callout)
    }
  }

  @ViewBuilder private var locationButtons: some View {
    Button(vm.t("Показать приложение", "Show app in Finder")) { vm.reveal(Bundle.main.bundlePath) }
      .oxyHelp(.finder)
    Button(vm.t(copiedPath ? "Путь скопирован" : "Копировать путь", copiedPath ? "Path copied" : "Copy path")) {
      NSPasteboard.general.clearContents()
      copiedPath = NSPasteboard.general.setString(Bundle.main.bundlePath, forType: .string)
    }
  }

  private var diagnostics: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(vm.t(
        "Проверка открывает три защищённые папки без чтения содержимого. Это доступ текущего процесса, а не положение галочки в настройках. Успех не гарантирует доступ ко всем файлам и не отменяет ограничения macOS.",
        "The check opens three protected directories without reading their contents. It reflects access by this process, not the toggle in settings. Success does not guarantee access to every file or override macOS restrictions."))
      ForEach(vm.diskAccess?.checks ?? [], id: \.path) { check in
        VStack(alignment: .leading, spacing: 2) {
          Text(URL(fileURLWithPath: check.path).lastPathComponent).bold()
          Text(check.error == 0 ? vm.t("Доступно", "Accessible")
            : String(cString: strerror(check.error)) + " (\(check.error))")
            .textSelection(.enabled)
        }
      }
      Text(vm.t(
        "В этой сборке нет Developer ID: сохранение разрешения между обновлениями пока не гарантируется. Приложение не сбрасывает ваши разрешения автоматически.",
        "This build has no Developer ID signature: permissions may not persist across updates. The app never resets your permissions automatically."))
    }.font(.caption).foregroundStyle(.secondary)
  }

  private var footer: some View {
    ViewThatFits(in: .horizontal) {
      HStack { footerStatus; Spacer(); doneButton }
      VStack(alignment: .leading, spacing: 12) { footerStatus; doneButton }
    }
  }

  @ViewBuilder private var footerStatus: some View {
    if !available {
      VStack(alignment: .leading, spacing: 6) {
        if limited {
          Button(vm.t("Проверить снова", "Check again")) { vm.checkDiskAccess() }.oxyHelp(.recheck)
        }
        if let date = vm.diskAccessCheckedAt {
          Text(vm.t("Проверено: ", "Checked: ") + date.formatted(date: .omitted, time: .standard))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var doneButton: some View {
    Button(vm.pendingDiskScan
      ? (available ? vm.t("Начать сканирование", "Start scanning") : vm.t("Сканировать доступное", "Scan accessible files"))
      : vm.t("Готово", "Done")) {
      let scan = vm.pendingDiskScan
      vm.pendingDiskScan = false
      vm.diskAccessAcknowledged = true
      dismiss()
      if scan { vm.scan() }
    }.oxyHelp(.accessDone)
  }

  private var status: String {
    switch vm.diskAccess?.state {
    case .available:
      return vm.t("Проверенные защищённые папки доступны", "Checked protected directories are accessible")
    case .limited:
      return vm.t("Этой копии приложения недоступны защищённые папки.", "This copy of the app cannot access protected directories.")
    default:
      return vm.t("Не удалось подтвердить доступ.", "Could not verify access.")
    }
  }
}
