import Foundation

public struct UpdateBackup: Identifiable, Sendable {
  public var id: String { url.path }
  public let url: URL
  public let version: String
  public let bytes: Int64
  public let date: Date
  public let protected: Bool
  public let fingerprint: String
}
public enum UpdateBackups {
  public static func list(beside app: URL) throws -> [UpdateBackup] {
    let fm = FileManager.default
    let parent = app.deletingLastPathComponent()
    let candidates = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.contentModificationDateKey])
      .filter { $0.lastPathComponent.hasPrefix(".OxyMacUpdate-") && UUID(uuidString: String($0.lastPathComponent.dropFirst(".OxyMacUpdate-".count))) != nil }
      .sorted { $0.path < $1.path }
    var result: [UpdateBackup] = []
    for url in candidates {
      guard url.resolvingSymlinksInPath() == url.standardizedFileURL,
        let date = try? url.appendingPathComponent("healthy").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        let data = try? Data(contentsOf: url.appendingPathComponent("previous.app/Contents/Info.plist")),
        let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        info["CFBundleIdentifier"] as? String == "com.oxyfire.OxyMacCleaner" else { continue }
      let names = Set(try fm.contentsOfDirectory(atPath: url.path))
      guard names.isSubset(of: ["healthy", "previous.app", "failed.app", "unpacked", "update.zip", "update.log", "install.sh", ".DS_Store"]) else { continue }
      guard let manifest = try? DirectoryManifest.capture(url) else { continue }
      result.append(UpdateBackup(url: url, version: info["CFBundleShortVersionString"] as? String ?? "?", bytes: manifest.bytes, date: date, protected: false, fingerprint: try manifest.digest))
    }
    result.sort { $0.date > $1.date }
    return result.enumerated().map { index, value in
      UpdateBackup(url: value.url, version: value.version, bytes: value.bytes, date: value.date, protected: index == 0, fingerprint: value.fingerprint)
    }
  }
  public static func trash(_ entry: UpdateBackup, beside app: URL) throws {
    guard let fresh = try list(beside: app).first(where: { $0.id == entry.id }), !fresh.protected,
      fresh.fingerprint == entry.fingerprint else { throw CleanerError.message("Backup changed or is the latest rollback copy; retained") }
    var destination: NSURL?
    try FileManager.default.trashItem(at: entry.url, resultingItemURL: &destination)
  }
}
