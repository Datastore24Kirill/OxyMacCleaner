import Foundation
import Darwin

public struct SavedScan: Codable, Sendable {
  public let version: Int
  public let date: Date
  public let roots: [URL]
  public let volumeID: String
  public let report: ScanReport
  public let progress: ScanProgress
  public init(
    roots: [URL], volumeID: String, report: ScanReport, progress: ScanProgress, date: Date = Date()
  ) {
    version = 1
    self.date = date
    self.roots = roots
    self.volumeID = volumeID
    self.report = report
    self.progress = progress
  }
}
public struct ScanStore: Sendable {
  public let url: URL
  public init(url: URL) { self.url = url }
  private struct Metadata: Codable {
    let version: Int
    let date: Date
    let roots: [URL]
    let volumeID: String
    let complete: Bool
    let progress: ScanProgress
    let fileCount: Int
  }
  private struct Folder: Codable { let path: String; let bytes: Int64 }
  private enum Batch: Codable {
    case metadata(Metadata), files([FileRecord]), folders([Folder]), issues([String]), end
  }
  public func save(_ snapshot: SavedScan) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".scan-" + UUID().uuidString)
    guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CleanerError.message("Cannot create scan snapshot") }
    defer { try? fm.removeItem(at: temporary) }
    let handle = try FileHandle(forWritingTo: temporary); defer { try? handle.close() }
    func write(_ batch: Batch) throws {
      try autoreleasepool { var data = try JSONEncoder().encode(batch); data.append(10); try handle.write(contentsOf: data) }
    }
    try write(.metadata(Metadata(version: 2, date: snapshot.date, roots: snapshot.roots, volumeID: snapshot.volumeID, complete: snapshot.report.complete, progress: snapshot.progress, fileCount: snapshot.report.files.count)))
    for start in stride(from: 0, to: snapshot.report.files.count, by: 256) {
      try write(.files(Array(snapshot.report.files[start..<min(start+256, snapshot.report.files.count)])))
    }
    var folders: [Folder] = []
    for (path, bytes) in snapshot.report.folders {
      folders.append(Folder(path: path, bytes: bytes))
      if folders.count == 256 { try write(.folders(folders)); folders.removeAll(keepingCapacity: true) }
    }
    if !folders.isEmpty { try write(.folders(folders)) }
    for start in stride(from: 0, to: snapshot.report.issues.count, by: 256) {
      try write(.issues(Array(snapshot.report.issues[start..<min(start+256, snapshot.report.issues.count)])))
    }
    try write(.end); try handle.synchronize()
    guard rename(temporary.path, url.path) == 0 else { throw CleanerError.message("Cannot finish scan snapshot; previous result retained") }
  }
  public func load() throws -> SavedScan? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    let prefix = try handle.read(upToCount: 8) ?? Data()
    if prefix.starts(with: Data("bplist".utf8)) {
      let snapshot = try PropertyListDecoder().decode(SavedScan.self, from: Data(contentsOf: url))
      guard snapshot.version == 1 else { throw CleanerError.message("Unsupported scan snapshot version") }
      try validate(snapshot.report)
      return snapshot
    }
    try handle.seek(toOffset: 0)
    var buffer = Data(); var metadata: Metadata?; var report = ScanReport(); var ended = false
    while true {
      let data = try handle.read(upToCount: 1_048_576) ?? Data()
      if data.isEmpty { break }; buffer.append(data)
      while let newline = buffer.firstIndex(of: 10) {
        let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
        guard !ended else { throw CleanerError.message("Unexpected data after scan snapshot") }
        try autoreleasepool {
          let batch = try JSONDecoder().decode(Batch.self, from: line)
          switch batch {
          case .metadata(let value):
            guard metadata == nil, value.version == 2, value.fileCount >= 0 else { throw CleanerError.message("Invalid scan snapshot header") }
            metadata = value
          case .files(let files): report.files.append(contentsOf: files)
          case .folders(let folders): for folder in folders { report.folders[folder.path] = folder.bytes }
          case .issues(let issues): report.issues.append(contentsOf: issues)
          case .end: ended = true
          }
        }
      }
      guard buffer.count < 8_000_000 else { throw CleanerError.message("Scan snapshot record too large") }
    }
    guard ended, buffer.isEmpty, let metadata, report.files.count == metadata.fileCount else { throw CleanerError.message("Incomplete scan snapshot") }
    try validate(report); report.complete = metadata.complete
    return SavedScan(roots: metadata.roots, volumeID: metadata.volumeID, report: report, progress: metadata.progress, date: metadata.date)
  }
  private func validate(_ report: ScanReport) throws {
    guard report.files.allSatisfy({ $0.bytes >= 0 && $0.path.hasPrefix("/") }) else { throw CleanerError.message("Invalid scan snapshot") }
  }

}
public struct DiskNode: Identifiable, Sendable {
  public var id: String { path }
  public let path: String
  public let bytes: Int64
  public let directory: Bool
  public init(path: String, bytes: Int64, directory: Bool) {
    self.path = path
    self.bytes = bytes
    self.directory = directory
  }
  public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
public struct DiskIndex: Sendable {
  public var children: [String: [DiskNode]] = [:]
  public init(report: ScanReport) {
    for (path, bytes) in report.folders {
      guard path != "/" else { continue }
      let parent = (path as NSString).deletingLastPathComponent
      children[parent, default: []].append(DiskNode(path: path, bytes: bytes, directory: true))
    }
    for file in report.files {
      let parent = (file.path as NSString).deletingLastPathComponent
      children[parent, default: []].append(
        DiskNode(path: file.path, bytes: file.bytes, directory: false))
    }
    for path in children.keys {
      children[path]?.sort { $0.bytes == $1.bytes ? $0.path < $1.path : $0.bytes > $1.bytes }
    }
  }
}
public enum DiskLayout {
  public struct Tile: Sendable {
    public let index: Int
    public let x: Double, y: Double, width: Double, height: Double
  }
  /// Binary subdivision. Every positive item gets its exact proportional area.
  public static func tiles(weights: [Int64], width: Double, height: Double) -> [Tile] {
    let items = weights.enumerated().filter { $0.element > 0 }
    var output: [Tile] = []
    func split(
      _ items: [(offset: Int, element: Int64)], _ x: Double, _ y: Double, _ w: Double, _ h: Double
    ) {
      guard !items.isEmpty else { return }
      if items.count == 1 {
        output.append(Tile(index: items[0].offset, x: x, y: y, width: w, height: h))
        return
      }
      let total = items.reduce(0.0) { $0 + Double($1.element) }
      var sum = 0.0
      var count = 0
      while count < items.count - 1 && sum < total / 2 {
        sum += Double(items[count].element)
        count += 1
      }
      let fraction = sum / total
      if w >= h {
        split(Array(items.prefix(count)), x, y, w * fraction, h)
        split(Array(items.dropFirst(count)), x + w * fraction, y, w * (1 - fraction), h)
      } else {
        split(Array(items.prefix(count)), x, y, w, h * fraction)
        split(Array(items.dropFirst(count)), x, y + h * fraction, w, h * (1 - fraction))
      }
    }
    guard width > 0 && height > 0 else { return [] }
    split(items, 0, 0, width, height)
    return output
  }
}
