import Foundation

/// Append-only batches: a torn final batch is ignored, earlier malformed batches are rejected.
/// Recovery restores partial results; a fresh traversal is required for current totals.
public final class ScanJournal {
  private struct Header: Codable { let version: Int; let roots: [URL]; let volumeID: String; let date: Date }
  public let url: URL
  private let handle: FileHandle
  private var pending: [FileRecord] = []
  public init(url: URL, roots: [URL], volumeID: String) throws {
    self.url = url
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var header = try JSONEncoder().encode(Header(version: 1, roots: roots, volumeID: volumeID, date: Date()))
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
  public func flush() throws {
    guard !pending.isEmpty else { return }
    var data = try JSONEncoder().encode(pending); data.append(10)
    try handle.write(contentsOf: data); try handle.synchronize(); pending.removeAll(keepingCapacity: true)
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
            guard h.version == 1, !h.roots.isEmpty else { throw CleanerError.message("Invalid scan recovery header") }
            header = h
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
    report.issues = ["Recovered interrupted scan; results are partial. Repeat the scan for current totals."]
    var progress = ScanProgress(); progress.files = report.files.count; progress.bytes = report.total; progress.phase = .cancelled; progress.issues = 1
    return SavedScan(roots: header.roots, volumeID: header.volumeID, report: report, progress: progress, date: header.date)
  }
}
