import Foundation

public struct ScanVolume: Identifiable, Sendable {
  public var id: String { url.path }
  public let url: URL
  public let name: String
  public let total: Int64
  public let available: Int64
  public let internalDisk: Bool
  public var used: Int64 { max(0, total - available) }
}
public enum Volumes {
  public static func visiblePath(_ path: String) -> Bool {
    path == "/" || (path.hasPrefix("/Volumes/") && path != "/Volumes/")
  }
  public static func discover() -> [ScanVolume] {
    let keys: Set<URLResourceKey> = [
      .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsInternalKey,
      .volumeIsLocalKey,
    ]
    var urls =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
    urls.insert(URL(fileURLWithPath: "/"), at: 0)
    var seen = Set<String>()
    return urls.compactMap { u -> ScanVolume? in
      let url = u.standardizedFileURL
      guard visiblePath(url.path), seen.insert(url.path).inserted,
        let v = try? url.resourceValues(forKeys: keys), v.volumeIsLocal != false
      else { return nil }
      return ScanVolume(
        url: url, name: v.volumeName ?? url.lastPathComponent,
        total: Int64(v.volumeTotalCapacity ?? 0), available: Int64(v.volumeAvailableCapacity ?? 0),
        internalDisk: v.volumeIsInternal ?? (url.path == "/"))
    }.sorted {
      if $0.id == "/" { return $1.id != "/" }
      if $1.id == "/" { return false }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
  // Scan the unified startup namespace only once. Other mounted volumes are separate selections.
  public static func exclusions(for root: URL, mounted: [URL]) -> [String] {
    var paths = mounted.map(\.standardizedFileURL.path).filter {
      $0 != root.path && Scanner.inside($0, root.path)
    }
    if root.path == "/" { paths += ["/System/Volumes", "/Volumes", "/dev"] }
    return Array(Set(paths))
  }
}
