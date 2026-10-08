import Foundation

/// Append-only batches: a torn final batch is ignored, earlier malformed batches are rejected.
/// Version 2 durably records completed subtrees only after their file batches.
public final class ScanJournal {
  private struct Header: Codable { let version: Int; let roots: [URL]; let volumeID: String; let date: Date; let checkpoint: ScanCheckpoint? }
  private struct Issues: Codable { let issues: [String] }
  private struct Completed: Codable { let directories: [String] }
  public let url: URL
  private let handle: FileHandle
  private var pending: [FileRecord] = []
  private var directories: [String] = []
  private var failed = false
  private var issues: [String] = []
  public init(url: URL, roots: [URL], volumeID: String, excluded: [String]? = nil) throws {
    self.url = url
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var header = try JSONEncoder().encode(Header(version: excluded == nil ? 1 : 2, roots: roots, volumeID: volumeID, date: Date(), checkpoint: excluded.map { Scanner.resumeMetadata(roots: roots, excluded: $0) }))
    header.append(10)
    try header.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    handle = try FileHandle(forWritingTo: url); try handle.seekToEnd()
  }
  deinit { try? handle.close() }
  public func append(_ file: FileRecord) throws {
    pending.append(file)
    if pending.count >= 256 { try flush() }
  }
  public func completeDirectory(_ path: String) throws {
    directories.append(path)
    if directories.count >= 256 { try flush() }
  }
  public func appendIssue(_ text: String) throws {
    issues.append(text)
    if issues.count >= 256 { try flush() }
  }
  public func flush() throws {
    guard !failed else { throw CleanerError.message("Recovery journal write failed; restart scan") }
    guard !pending.isEmpty || !directories.isEmpty || !issues.isEmpty else { return }
    do {
    // Never publish a directory before all preceding file records have been written.
    if !pending.isEmpty {
      var data = try JSONEncoder().encode(pending); data.append(10)
      try handle.write(contentsOf: data)
    }
    if !issues.isEmpty {
      var data = try JSONEncoder().encode(Issues(issues: issues)); data.append(10)
      try handle.write(contentsOf: data)
    }
    if !directories.isEmpty {
      var data = try JSONEncoder().encode(Completed(directories: directories)); data.append(10)
      try handle.write(contentsOf: data)
    }
    try handle.synchronize()
    pending.removeAll(keepingCapacity: true); directories.removeAll(keepingCapacity: true); issues.removeAll(keepingCapacity: true)
    } catch { failed = true; throw error }
  }
  public static func recover(_ url: URL) throws -> SavedScan? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    var buffer = Data(); var header: Header?; var report = ScanReport()
    while true {
      let data = try handle.read(upToCount: 1_048_576) ?? Data()
      if data.isEmpty { break }; buffer.append(data)
      while let newline = buffer.firstIndex(of: 10) {
        let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
        try autoreleasepool {
          if header == nil {
            let h = try JSONDecoder().decode(Header.self, from: line)
            guard [1, 2].contains(h.version), !h.roots.isEmpty else { throw CleanerError.message("Invalid scan recovery header") }
            header = h
            if h.version == 2 {
              guard let checkpoint = h.checkpoint, checkpoint.completedDirectories.isEmpty,
                checkpoint.roots == Scanner.resumeMetadata(roots: h.roots, excluded: []).roots else {
                throw CleanerError.message("Invalid scan recovery checkpoint")
              }
              report.checkpoint = checkpoint
            }
          } else if header?.version == 2, line.first == 123 {
            if let notes = try? JSONDecoder().decode(Issues.self, from: line) {
              guard notes.issues.count <= 256 else { throw CleanerError.message("Invalid scan issues") }
              report.issues.append(contentsOf: notes.issues); return
            }
            let completed = try JSONDecoder().decode(Completed.self, from: line)
            guard completed.directories.count <= 256,
              completed.directories.allSatisfy({ path in header!.roots.contains { Scanner.inside(path, $0.path) } }) else {
              throw CleanerError.message("Invalid completed scan directories")
            }
            report.checkpoint?.completedDirectories.append(contentsOf: completed.directories)
          } else {
            let files = try JSONDecoder().decode([FileRecord].self, from: line)
            guard files.count <= 256, files.allSatisfy({ f in f.bytes >= 0 && header!.roots.contains { Scanner.inside(f.path, $0.path) } }) else { throw CleanerError.message("Invalid scan recovery records") }
            report.files.append(contentsOf: files)
          }
        }
      }
      guard buffer.count <= 8_000_000 else { throw CleanerError.message("Scan recovery record too large") }
    }
    guard let header else { throw CleanerError.message("Incomplete scan recovery header") }
    report.files.sort { $0.bytes > $1.bytes }
    for f in report.files {
      var parent = (f.path as NSString).deletingLastPathComponent
      while header.roots.contains(where: { Scanner.inside(parent, $0.path) }) {
        report.folders[parent, default: 0] += f.bytes
        if parent == "/" { break }; parent = (parent as NSString).deletingLastPathComponent
      }
    }
    report.complete = false
    report.issues.append(report.checkpoint == nil
      ? "Recovered interrupted scan; results are partial. Repeat the scan for current totals."
      : "Recovered interrupted scan. Resume unfinished folders or start a new scan for current totals.")
    var progress = ScanProgress(); progress.files = report.files.count; progress.bytes = report.total; progress.phase = .cancelled; progress.issues = report.issues.count
    return SavedScan(roots: header.roots, volumeID: header.volumeID, report: report, progress: progress, date: header.date)
  }
}
