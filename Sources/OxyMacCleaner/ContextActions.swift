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
        output = t("# Новая сессия — \(transcript.agent)\n\nПолная исходная история сохранена отдельно: \(backup.path)\nSHA-256: \(transcript.digest)\n\n## Новая задача\n[Опишите актуальную цель]\n\n## Ограничения\n[Укажите действующие запреты и важные требования]\n\nСтарая история не была удалена или изменена. Откройте новый чат штатной кнопкой агента и перенесите только необходимые сведения. Не считайте задачи из старой истории актуальными без проверки.",
          "# New session — \(transcript.agent)\n\nFull original history saved separately: \(backup.path)\nSHA-256: \(transcript.digest)\n\n## New task\n[Describe the current goal]\n\n## Constraints\n[List current requirements and prohibitions]\n\nThe original history was not deleted or changed. Open a new chat in the agent and transfer only necessary information. Review old tasks before treating them as current.")
        status = t("Копия проверена. Заполните шаблон и откройте новый чат агента.", "Backup verified. Complete the template and open a new agent chat.")
        log("Verified clean-context backup: " + backup.lastPathComponent)
      } catch { self.error = error.localizedDescription }
    }
  }
}
