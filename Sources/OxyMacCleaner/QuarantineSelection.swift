import CleanerCore
import SwiftUI

struct QuarantineSelection: View {
  @EnvironmentObject var vm: AppModel
  @Binding var selected: Set<UUID>
  let entries: [QuarantineEntry]
  var body: some View {
    let chosen = entries.filter { selected.contains($0.id) && $0.state == "quarantined" }
    VStack(alignment: .leading) {
      SelectionControls(count: chosen.count, bytes: chosen.reduce(0) { $0 + $1.bytes },
        canSelect: entries.contains { $0.state == "quarantined" },
        select: { selected = Set(entries.filter { $0.state == "quarantined" }.map(\.id)) },
        clear: { selected = [] })
      HStack {
        Button(vm.t("Восстановить выбранные…", "Restore selected…")) {
          vm.processQuarantine(chosen, erase: false)
        }
        Button(vm.t("Удалить выбранные навсегда…", "Permanently delete selected…"), role: .destructive) {
          vm.processQuarantine(chosen, erase: true)
        }
      }.disabled(vm.busy || chosen.isEmpty)
    }
  }
}

extension AppModel {
  func processQuarantine(_ chosen: [QuarantineEntry], erase: Bool) {
    let items = chosen.filter { $0.state == "quarantined" }
    guard !busy, !items.isEmpty else { return }
    guard confirm(
      erase ? t("Удалить выбранные навсегда?", "Permanently delete selected?") : t("Восстановить выбранные?", "Restore selected?"),
      "\(items.count) · " + ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.bytes }, countStyle: .file)
      + "\n" + items.prefix(8).map(\.original).joined(separator: "\n")
      + (items.count > 8 ? t("\n… и ещё ", "\n… and ") + String(items.count - 8) : "")
      + "\n\n" + (erase ? t("Восстановление из приложения станет невозможно.", "The app will no longer be able to restore these items.") : t("Вернём в исходные папки. Конфликты имён и недоступные диски пропускаются; существующие файлы не перезаписываются.", "Restores original locations. Name conflicts and unavailable disks are skipped; existing files are never overwritten.")),
      destructive: erase) else { return }
    busy = true; cancellation = Cancellation()
    let token = cancellation, store = quarantine
    task = Task {
      var attempted = 0, completed = 0
      var failures: [String] = []
      var restoredPaths: [String] = []
      var restoredDirectory = false
      for item in items {
        if token.cancelled { break }
        attempted += 1
        status = t("Обработка: ", "Processing: ") + "\(attempted)/\(items.count)"
        do {
          try await Task.detached {
            try token.check()
            if erase { try store.erase(item) }
            else { try store.restore(item, cancellation: token) }
          }.value
          completed += 1
          if !erase {
            restoredPaths.append(item.original)
            restoredDirectory = restoredDirectory || item.kind == "directory"
          }
          log((erase ? "Deleted: " : "Restored: ") + item.original)
        } catch { failures.append(item.original + ": " + error.localizedDescription) }
      }
      if !erase && completed > 0 { await reconcileRemovedPaths([], invalidateOnly: true, restoredPaths: restoredPaths) }
      entries = store.entries(); refreshVolumes(); scheduleReminder()
      status = CleanupSummary(selected: items.count, completed: completed, attempted: attempted).text(russian: language != "en")
      if restoredDirectory {
        status += t(" · Папки восстановлены; выполните сканирование для обновления их содержимого.", " · Folders restored; scan again to update their contents.")
      }
      log(status)
      if !failures.isEmpty { error = failures.joined(separator: "\n") }
      busy = false
    }
  }
}
