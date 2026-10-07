import CleanerCore
import SwiftUI

extension AppModel {
  func prepareCleanContext() {
    guard let transcript, !busy else { return }
    busy = true
    let root = support.appendingPathComponent("HistoryBackups")
    task = Task {
      defer { busy = false }
      do {
        let backup = try await Task.detached { try transcript.backup(in: root) }.value
        output = "# Новая сессия — \(transcript.agent)\n\nПолная исходная история сохранена отдельно: \(backup.path)\nSHA-256: \(transcript.digest)\n\n## Новая задача\n[Опишите актуальную цель]\n\n## Ограничения\n[Укажите действующие запреты и важные требования]\n\nСтарая история не была удалена или изменена. Откройте новый чат штатной кнопкой агента и перенесите только необходимые сведения. Не считайте задачи из старой истории актуальными без проверки."
        status = t("Копия проверена. Заполните шаблон и откройте новый чат агента.", "Backup verified. Complete the template and open a new agent chat.")
        log("Verified clean-context backup: " + backup.lastPathComponent)
      } catch { self.error = error.localizedDescription }
    }
  }
}
