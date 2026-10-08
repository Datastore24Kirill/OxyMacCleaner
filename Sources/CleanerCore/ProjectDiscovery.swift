import Foundation

public struct DiscoveredProject: Identifiable, Sendable {
  public var id: String { url.path }
  public let url: URL
  public let markers: [String]
}
public struct ProjectDiscoveryResult: Sendable {
  public var projects: [DiscoveredProject] = []
  public var visited = 0
  public var incomplete = false
  public var issues: [String] = []
}
public enum ProjectDiscovery {
  public static func discover(_ root: URL, exclusions: [String] = [], limit: Int = 50_000, cancellation: Cancellation = Cancellation(), progress: @escaping @Sendable (Int) -> Void = { _ in }) -> ProjectDiscoveryResult {
    let root = root.standardizedFileURL.resolvingSymlinksInPath()
    var result = ProjectDiscoveryResult(); var found: [String: Set<String>] = [:]
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
    let skipped: Set<String> = ["node_modules", "Pods", ".build", ".venv", "venv", "target", ".next", "vendor", ".gradle", "Library", ".Trash"]
    func inspect(_ url: URL) {
      let name = url.lastPathComponent
      if ["Package.swift", "package.json", "Cargo.toml", "pyproject.toml", "Podfile", "composer.json", "Gemfile", "settings.gradle", "settings.gradle.kts", "pom.xml", "requirements.txt", ".git"].contains(name) || ["xcodeproj", "xcworkspace"].contains(url.pathExtension) {
        let parent = url.deletingLastPathComponent()
        if GitWorktrees.locationAllowed(parent) { found[parent.path, default: []].insert(name) }
      }
    }
    guard !exclusions.contains(where: { Scanner.inside(root.path, $0) }) else { return result }
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { url, error in
      result.incomplete = true
      if result.issues.count < 100 { result.issues.append(url.path + ": " + error.localizedDescription) }; return true
    }) else { result.incomplete = true; result.issues = ["Folder unavailable"]; return result }
    for case let url as URL in enumerator {
      if cancellation.cancelled || result.visited >= limit { result.incomplete = true; break }
      result.visited += 1
      if result.visited % 250 == 0 { progress(result.visited) }
      do {
        let values = try url.resourceValues(forKeys: Set(keys))
        if values.isSymbolicLink == true || exclusions.contains(where: { Scanner.inside(url.path, $0) }) || (values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current) {
          enumerator.skipDescendants(); continue
        }
        if skipped.contains(url.lastPathComponent) { enumerator.skipDescendants(); continue }
        inspect(url)
        if url.lastPathComponent == ".git" || ["app", "xcodeproj", "xcworkspace", "photoslibrary", "xcarchive"].contains(url.pathExtension) { enumerator.skipDescendants() }
      } catch { result.incomplete = true; if result.issues.count < 100 { result.issues.append(url.path) } }
    }
    result.projects = found.map { DiscoveredProject(url: URL(fileURLWithPath: $0.key), markers: $0.value.sorted()) }.sorted { $0.id < $1.id }
    progress(result.visited)
    return result
  }
}
