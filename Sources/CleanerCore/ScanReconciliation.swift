import Foundation

public enum ScanReconciliation {
  /// Re-read confirmed restored files only, within the original scan scope.
  /// Directories and inaccessible paths require a new scan; never traverse them here.
  public static func restoring(_ paths: [String], into saved: SavedScan,
    exclusions: [String] = []) -> SavedScan {
    var report = saved.report
    var replacements: [String: FileRecord] = [:]
    for path in Set(paths) {
      let url = URL(fileURLWithPath: path).standardizedFileURL
      guard saved.roots.contains(where: { Scanner.inside(url.path, $0.standardizedFileURL.path) }),
        !exclusions.contains(where: { Scanner.inside(url.path, $0) }),
        url.resolvingSymlinksInPath().path == url.path,
        let fresh = try? FileRecord.read(url) else { continue }
      replacements[url.path] = fresh
    }
    report.files.removeAll { replacements[$0.path] != nil }
    report.files.append(contentsOf: replacements.values.sorted { $0.path < $1.path })
    let updated = SavedScan(roots: saved.roots, volumeID: saved.volumeID,
      report: report, progress: saved.progress, date: saved.date)
    return removing([], from: updated)
  }

  /// Remove only confirmed paths. Remaining observations keep their original date;
  /// this is not a new scan and cannot be resumed from its former checkpoint.
  public static func removing(_ paths: [String], from saved: SavedScan) -> SavedScan {
    let removed = SpaceEstimate.disjointPaths(paths)
    var report = saved.report
    report.files.removeAll { file in removed.contains { Scanner.inside(file.path, $0) } }
    report.checkpoint = nil; report.complete = false; report.folders = [:]
    var progress = saved.progress
    progress.files = report.files.count; progress.bytes = report.total; progress.categories = [:]
    for file in report.files {
      progress.categories[file.category, default: 0] += file.bytes
      var parent = (file.path as NSString).deletingLastPathComponent
      while saved.roots.contains(where: { Scanner.inside(parent, $0.path) }) {
        report.folders[parent, default: 0] += file.bytes
        if parent == "/" { break }
        parent = (parent as NSString).deletingLastPathComponent
      }
    }
    progress.directories = report.folders.count
    progress.phase = .cancelled; progress.currentPath = ""
    let note = "Snapshot adjusted after a file operation; rescan for current disk totals."
    if !report.issues.contains(note) { report.issues.append(note) }
    progress.issues = report.issues.count
    return SavedScan(roots: saved.roots, volumeID: saved.volumeID, report: report, progress: progress, date: saved.date)
  }
}
