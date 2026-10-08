import CleanerCore
import Foundation

extension AppModel {
  func browserIndex() async throws -> FileBrowserIndex {
    if let cachedBrowser, cachedBrowserRevision == reportRevision, cachedBrowserExclusions == exclusions { return cachedBrowser }
    let files = report.files, excluded = exclusions, revision = reportRevision
    let quarantinePath = quarantine.root.path, downloads = home.appendingPathComponent("Downloads").path
    let token = Cancellation()
    let index = try await withTaskCancellationHandler {
      try await Task.detached {
        try FileBrowserIndex(files: files, excluded: excluded, quarantine: quarantinePath, downloads: downloads, cancellation: token)
      }.value
    } onCancel: { token.cancel() }
    try Task.checkCancellation()
    if revision == reportRevision && excluded == exclusions {
      cachedBrowser = index; cachedBrowserRevision = revision; cachedBrowserExclusions = excluded
    }
    return index
  }
}
