import Foundation

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
  public func save(_ snapshot: SavedScan) throws {
    let fm = FileManager.default
    try fm.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(snapshot)
    // Complete replacement is atomic; a failed write leaves the prior scan available.
    try data.write(to: url, options: [.atomic])
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  public func load() throws -> SavedScan? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let snapshot = try PropertyListDecoder().decode(SavedScan.self, from: Data(contentsOf: url))
    guard snapshot.version == 1 else {
      throw CleanerError.message("Unsupported scan snapshot version")
    }
    guard snapshot.report.files.allSatisfy({ $0.bytes >= 0 && $0.path.hasPrefix("/") }) else {
      throw CleanerError.message("Invalid scan snapshot")
    }
    return snapshot
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
      let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
      children[parent, default: []].append(DiskNode(path: path, bytes: bytes, directory: true))
    }
    for file in report.files {
      let parent = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
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
