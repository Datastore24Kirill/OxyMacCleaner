import CleanerCore
import Foundation

extension AppModel {
  func reconcileRemovedPaths(_ paths: [String], invalidateOnly: Bool = false) async {
    guard (!paths.isEmpty || invalidateOnly), let date = snapshotDate else { refreshVolumes(); return }
    let saved = SavedScan(roots: roots, volumeID: volumeID, report: report, progress: scanProgress ?? ScanProgress(), date: date)
    let store = scanStore; let journal = scanJournalURL
    let result = await Task.detached {
      let updated = ScanReconciliation.removing(paths, from: saved)
      return (updated, DiskIndex(report: updated.report))
    }.value
    report = result.0.report; scanProgress = result.0.progress; diskIndex = result.1
    selected = selected.filter { path in !paths.contains { Scanner.inside(path, $0) } }
    duplicates = []; duplicatesReadAt = nil; recoveredInterruptedScan = false
    do {
      try await Task.detached {
        try store.save(result.0)
        if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }
      }.value
    } catch {
      self.error = t("Действие выполнено, но сохранить обновлённый снимок не удалось. Выполните новый обход. ", "Operation completed, but the adjusted snapshot could not be saved. Run a new scan. ") + error.localizedDescription
    }
    refreshVolumes(); refreshRecommendations()
  }
}
