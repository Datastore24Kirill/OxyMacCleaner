import Foundation

/// Metadata accounting only. APFS shared extents/snapshots prevent a guaranteed reclaim estimate.
public struct SpaceEstimate: Sendable {
  public let logical: Int64
  public let allocated: Int64
  public let hardLinked: Int
  public let count: Int
  public init(files: [FileRecord]) {
    var paths = Set<String>(); var identities = Set<String>()
    var logical: Int64 = 0; var allocated: Int64 = 0; var linked = 0; var count = 0
    for file in files where paths.insert(file.path).inserted {
      let id = "\(file.device):\(file.inode)"
      guard identities.insert(id).inserted else { continue }
      logical += file.bytes; allocated += file.allocated; count += 1
      if file.links > 1 { linked += 1 }
    }
    self.logical = logical; self.allocated = allocated; hardLinked = linked; self.count = count
  }
  public static func disjointPaths(_ paths: [String]) -> [String] {
    let unique = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    return unique.filter { path in !unique.contains { $0 != path && Scanner.inside(path, $0) } }.sorted()
  }
}
