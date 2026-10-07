import Foundation

public struct ProjectDataItem: Identifiable, Sendable {
  public var id: String { path.path }
  public let project: URL
  public let path: URL
  public let rule: String
  public let recovery: String
  public let bytes: Int64
  public let issues: Int
  public let cleanable: Bool
}
public struct ProjectDataPlan: Sendable {
  public let item: ProjectDataItem
  let manifest: DirectoryManifest
  let markers: [String: String]
}
public enum ProjectData {
  private struct Rule {
    let id: String
    let path: String
    let marker: String
    let recovery: String
    let cleanable: Bool
  }
  private static let rules: [Rule] = [
    .init(
      id: "SwiftPM", path: ".build", marker: "Package.swift",
      recovery:
        "swift build · Может понадобиться интернет / Internet may be needed. Checkouts могут содержать локальные изменения / may contain local edits.",
      cleanable: false),
    .init(
      id: "CocoaPods", path: "Pods", marker: "Podfile",
      recovery:
        "pod install · Нужны зависимости и доступ к источникам / Dependencies and registry access required.",
      cleanable: false),
    .init(
      id: "Node dependencies", path: "node_modules", marker: "package.json",
      recovery:
        "Установка по lock-файлу / Reinstall from the lockfile. Интернет и install-скрипты / Network and install scripts may be required.",
      cleanable: false),
    .init(
      id: "Python environment", path: ".venv", marker: "pyproject.toml",
      recovery:
        "Пересоздать окружение по зависимостям / Recreate from declared dependencies. Может содержать незаписанные пакеты / May contain undeclared packages.",
      cleanable: false),
    .init(
      id: "Next.js webpack cache", path: ".next/cache/webpack", marker: "package.json",
      recovery:
        "Следующая сборка Next.js пересоздаст кэш, но будет медленнее / Next.js rebuild recreates the cache and may take longer.",
      cleanable: true),
    .init(
      id: "Rust incremental (debug)", path: "target/debug/incremental", marker: "Cargo.toml",
      recovery:
        "cargo build · Кэш пересоздаётся; сборка будет дольше / Cache is regenerated; build takes longer.",
      cleanable: true),
    .init(
      id: "Rust incremental (release)", path: "target/release/incremental", marker: "Cargo.toml",
      recovery: "cargo build --release · Кэш пересоздаётся / Cache is regenerated.", cleanable: true
    ),
  ]
  private static func marker(_ url: URL) throws -> Data {
    let file = try FileRecord.read(url)
    guard file.bytes < 2_000_000 else { throw CleanerError.message("Project metadata too large") }
    let data = try Data(contentsOf: url)
    try file.validate()
    return data
  }
  private static func recognized(_ rule: Rule, root: URL) throws -> [URL] {
    let main = root.appendingPathComponent(rule.marker)
    let data = try marker(main)
    var markers = [main]
    if rule.id.hasPrefix("Next.js") {
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      let dependencies = (json?["dependencies"] as? [String: Any] ?? [:])
        .merging(json?["devDependencies"] as? [String: Any] ?? [:]) { a, _ in a }
      guard dependencies["next"] is String else {
        throw CleanerError.message("Next.js dependency not found")
      }
    }
    if rule.id.hasPrefix("Rust") {
      let info = root.appendingPathComponent("target/.rustc_info.json")
      guard try JSONSerialization.jsonObject(with: marker(info)) is [String: Any] else {
        throw CleanerError.message("Cargo build metadata is unavailable")
      }
      markers.append(info)
    }
    return markers
  }
  public static func inventory(_ root: URL, cancellation: Cancellation = Cancellation()) throws
    -> [ProjectDataItem]
  {
    guard root.path == root.standardizedFileURL.path, root.resolvingSymlinksInPath().path == root.path,
      GitWorktrees.locationAllowed(root)
    else { throw CleanerError.message("Protected or noncanonical project path") }
    var result: [ProjectDataItem] = []
    for rule in rules {
      try cancellation.check()
      let path = root.appendingPathComponent(rule.path)
      guard FileManager.default.fileExists(atPath: path.path),
        FileManager.default.fileExists(atPath: root.appendingPathComponent(rule.marker).path)
      else { continue }
      var valid = true
      do { _ = try recognized(rule, root: root) } catch { valid = false }
      let scan = Scanner.scan(roots: [path], excluded: [], cancellation: cancellation)
      try cancellation.check()
      result.append(
        ProjectDataItem(
          project: root, path: path, rule: rule.id, recovery: rule.recovery,
          bytes: scan.total, issues: scan.issues.count + (scan.complete ? 0 : 1) + (valid ? 0 : 1),
          cleanable: rule.cleanable && valid))
    }
    return result
  }
  public static func prepare(
    _ item: ProjectDataItem, exclusions: [String], cancellation: Cancellation = Cancellation(),
    now: Date = Date(), run: GitWorktrees.Runner = GitWorktrees.run,
    idle: () throws -> Void = DeveloperActivity.assertIdle
  ) throws -> ProjectDataPlan {
    try cancellation.check()
    try idle()
    guard let rule = rules.first(where: { $0.id == item.rule }), rule.cleanable,
      item.cleanable, item.issues == 0, GitWorktrees.locationAllowed(item.project),
      item.project.resolvingSymlinksInPath().path == item.project.path,
      item.path == item.project.appendingPathComponent(rule.path),
      !exclusions.contains(where: { Scanner.inside(item.id, $0) || Scanner.inside($0, item.id) })
    else {
      throw CleanerError.message("Protected, unknown or incomplete project data")
    }
    let top = try GitWorktrees.git(item.project, ["rev-parse", "--show-toplevel"], run: run)
    guard String(decoding: top, as: UTF8.self) == item.project.path + "\n" else {
      throw CleanerError.message("Choose the Git project root; unknown projects are analysis-only")
    }
    guard try GitWorktrees.git(item.project, ["ls-files", "-z", "--", rule.path], run: run).isEmpty
    else {
      throw CleanerError.message("Cache contains tracked project files")
    }
    guard
      !(try GitWorktrees.git(item.project, ["check-ignore", "--", rule.path], run: run)).isEmpty
    else {
      throw CleanerError.message("Cache is not ignored by Git")
    }
    var markers: [String: String] = [:]
    for url in try recognized(rule, root: item.project) {
      let record = try FileRecord.read(url)
      markers[url.path] = try Scanner.hash(url, cancellation: cancellation)
      try record.validate()
    }
    try GitWorktrees.assertInactive(item.project, run: run)
    let manifest = try DirectoryManifest.capture(item.path, cancellation: cancellation) { path in
      let url = URL(fileURLWithPath: path)
      guard !QuarantineStore.protected(path), !DerivedData.protectedContent(path),
        !["swift", "rs", "py", "js", "ts", "sqlite", "sqlite3", "db", "cer"].contains(
          url.pathExtension.lowercased()),
        !url.pathComponents.contains(where: {
          $0.lowercased().hasSuffix(".dsym") || $0.lowercased().hasSuffix(".xcarchive")
        }),
        !exclusions.contains(where: { Scanner.inside(path, $0) || Scanner.inside($0, path) })
      else {
        throw CleanerError.message("Cache contains protected or excluded data")
      }
    }
    guard manifest.items.allSatisfy({ $0.modified < now.addingTimeInterval(-600) }) else {
      throw CleanerError.message("Cache changed within 10 minutes; stop builds and wait")
    }
    try cancellation.check()
    try idle()
    return ProjectDataPlan(item: item, manifest: manifest, markers: markers)
  }
  public static func remove(
    _ plan: ProjectDataPlan, exclusions: [String], cancellation: Cancellation = Cancellation(),
    now: Date = Date(), run: GitWorktrees.Runner = GitWorktrees.run,
    idle: () throws -> Void = DeveloperActivity.assertIdle
  ) throws {
    let fresh = try prepare(
      plan.item, exclusions: exclusions, cancellation: cancellation, now: now, run: run, idle: idle)
    guard fresh.manifest == plan.manifest, fresh.markers == plan.markers else {
      throw CleanerError.message("Project or cache changed after confirmation")
    }
    try GitWorktrees.assertInactive(plan.item.project, run: run)
    try cancellation.check()
    try idle()
    do { try FileManager.default.removeItem(at: plan.item.path) } catch {
      throw CleanerError.message(
        "Cache deletion may be partial; inspect the project. " + error.localizedDescription)
    }
  }
}
