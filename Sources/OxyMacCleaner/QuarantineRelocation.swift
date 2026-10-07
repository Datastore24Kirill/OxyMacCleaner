import CleanerCore
import SwiftUI

extension AppModel {
  func quarantineState(_ state: String) -> String {
    switch state {
    case "quarantined": return t("В карантине", "In quarantine")
    case "prepared": return t("Перенос не завершён", "Transfer incomplete")
    case "restoring": return t("Восстановление не завершено", "Restore incomplete")
    case "attention": return t("Требует проверки", "Needs inspection")
    default: return state
    }
  }
  func relocateQuarantine(_ entry: QuarantineEntry) {
    guard !busy else { return }
    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
    panel.message = t("Выберите папку на другом локальном диске. После проверки копии прежний файл карантина будет удалён.", "Choose a folder on another local disk. After verification, the previous quarantine payload will be removed.")
    guard panel.runModal() == .OK, let destination = panel.url,
      confirm(t("Перенести карантин?", "Relocate quarantine?"), entry.original + "\n→ " + destination.path + "\n" + t("Восстановление потребует подключения этого диска. Перенос не удаляет единственную копию.", "Restoring will require this disk. The only copy is never removed.")) else { return }
    busy = true; cancellation = Cancellation(); let token = cancellation; let store = quarantine
    status = t("Копируем и проверяем карантин…", "Copying and verifying quarantine…")
    task = Task {
      do {
        try await Task.detached { try store.relocate(entry, to: destination, cancellation: token) }.value
        status = t("Карантин перенесён, копия проверена", "Quarantine relocated and verified")
      } catch { self.error = error.localizedDescription }
      entries = store.entries(); busy = false
    }
  }
}
