import Foundation

public struct DerivedCache: Identifiable, Sendable {
  public var id: String { path }
  public let path: String
  public let project: String
  public let workspace: String
  public let category: String
  public let bytes: Int64
  public let modified: Date
  public let issues: Int
}
public struct DerivedDataPlan: Sendable {
  public let source: URL
  public let manifest: DirectoryManifest
}
public enum DerivedData {
  public static var root: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Developer/Xcode/DerivedData")
  }
  public static let categories = ["Build/Intermediates.noindex", "Index.noindex", "Logs"]
  public static func allowed(_ source: URL, base: URL = root) -> Bool {
    guard source.standardizedFileURL == source.resolvingSymlinksInPath(),
      Scanner.inside(source.path, base.path)
    else { return false }
    let relative = String(source.path.dropFirst(base.path.count + 1)).split(separator: "/").map(
      String.init)
    guard relative.count >= 2, !relative[0].hasPrefix("."), relative[0] != "SourcePackages" else {
      return false
    }
    return categories.contains(relative.dropFirst().joined(separator: "/"))
  }
  public static func protectedContent(_ path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    let blocked: Set<String> = [".git", ".ssh", ".gnupg", "SourcePackages", "Keychains"]
    return !blocked.isDisjoint(with: url.pathComponents) || url.lastPathComponent == ".env"
      || url.lastPathComponent.hasPrefix(".env.")
      || ["p8", "p12", "pem", "key", "mobileprovision"].contains(url.pathExtension.lowercased())
  }
  public static func inventory(
    base: URL = root, cancellation: Cancellation = Cancellation(), projectName: String? = nil
  ) throws
    -> [DerivedCache]
  {
    let fm = FileManager.default
    var result: [DerivedCache] = []
    for project in try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
      try cancellation.check()
      if let projectName, project.lastPathComponent != projectName { continue }
      guard project.resolvingSymlinksInPath() == project.standardizedFileURL else { continue }
      let info = project.appendingPathComponent("info.plist")
      guard let record = try? FileRecord.read(info), record.bytes < 4_000_000 else { continue }
      let metadata =
        try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil)
        as? [String: Any]
      try record.validate()
      guard let workspace = metadata?["WorkspacePath"] as? String, workspace.hasPrefix("/") else {
        continue
      }
      for category in categories {
        let path = project.appendingPathComponent(category)
        guard allowed(path, base: base), fm.fileExists(atPath: path.path) else { continue }
        let scan = Scanner.scan(roots: [path], excluded: [], cancellation: cancellation)
        let modified = scan.files.map(\.modified).max() ?? .distantPast
        result.append(
          DerivedCache(
            path: path.path,
            project: URL(fileURLWithPath: workspace).deletingPathExtension().lastPathComponent,
            workspace: workspace, category: category, bytes: scan.total, modified: modified,
            issues: scan.issues.count + (scan.complete ? 0 : 1)))
      }
    }
    return result.sorted { $0.bytes > $1.bytes }
  }
  public static func prepare(
    _ cache: DerivedCache, cancellation: Cancellation = Cancellation(),
    idle: () throws -> Void = DeveloperActivity.assertIdle
  ) throws -> DerivedDataPlan {
    try idle()
    guard allowed(URL(fileURLWithPath: cache.path)), cache.issues == 0 else {
      throw CleanerError.message("Unrecognized or incomplete DerivedData cache")
    }
    let manifest = try DirectoryManifest.capture(
      URL(fileURLWithPath: cache.path), cancellation: cancellation
    ) { path in
      guard !protectedContent(path) else {
        throw CleanerError.message("Cache contains protected data")
      }
    }
    guard manifest.items.allSatisfy({ $0.modified < Date().addingTimeInterval(-600) }) else {
      throw CleanerError.message(
        "Cache was modified within 10 minutes; wait for builds/indexing to stop")
    }
    try idle()
    return DerivedDataPlan(source: URL(fileURLWithPath: cache.path), manifest: manifest)
  }
  public static func delete(
    _ plan: DerivedDataPlan, protectedPaths: [String] = [],
    cancellation: Cancellation = Cancellation(),
    idle: () throws -> Void = DeveloperActivity.assertIdle
  ) throws {
    try cancellation.check()
    try idle()
    guard allowed(plan.source) else { throw CleanerError.message("Unknown DerivedData path") }
    let current = try DirectoryManifest.capture(plan.source, cancellation: cancellation) { path in
      guard !protectedContent(path),
        !protectedPaths.contains(where: {
          Scanner.inside(path, $0) || Scanner.inside($0, path)
        })
      else { throw CleanerError.message("Cache contains protected or excluded data") }
    }
    guard current == plan.manifest,
      current.items.allSatisfy({ $0.modified < Date().addingTimeInterval(-600) })
    else { throw CleanerError.message("Cache changed; deletion blocked") }
    try idle()
    try cancellation.check()
    do { try FileManager.default.removeItem(at: plan.source) } catch {
      throw CleanerError.message(
        "Cache deletion failed and may be partial: " + error.localizedDescription)
    }
  }

}
