import Foundation

/// Attribution is descriptive only. It never grants permission to remove data.
public struct DataOwnership: Sendable, Equatable {
  public enum Kind: String, Sendable { case agent, application, project, unknown }
  public let kind: Kind
  public let name: String
  public let evidence: String
  public var metadataMatched = false
  public static func identify(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
    guard path.hasPrefix("/"), (path as NSString).standardizingPath == path else {
      return .init(kind: .unknown, name: "", evidence: "")
    }
    for agent in Agents.catalog {
      for relative in agent.relativePaths where Scanner.inside(path, home.appendingPathComponent(relative).path) {
        return .init(kind: .agent, name: agent.name, evidence: relative)
      }
    }
    if FileCategory.isDockerData(path) { return .init(kind: .application, name: "Docker", evidence: "Docker data path") }
    let components = (path as NSString).pathComponents
    if let app = components.first(where: { $0.hasSuffix(".app") }) {
      return .init(kind: .application, name: app, evidence: "Application bundle path")
    }
    for prefix in ["Library/Containers", "Library/Group Containers", "Library/Application Support"] {
      let root = home.appendingPathComponent(prefix).path + "/"
      if path.hasPrefix(root), let name = path.dropFirst(root.count).split(separator: "/").first {
        return .init(kind: .application, name: String(name), evidence: prefix)
      }
    }
    // Project root is inferred from build/dependency directory names, not asserted as a verified manifest.
    let markers: Set<String> = ["node_modules", ".build", "Pods", ".pytest_cache", ".mypy_cache", ".ruff_cache"]
    if let index = components.firstIndex(where: { markers.contains($0) }), index > 1 {
      return .init(kind: .project, name: components[index - 1], evidence: components[index])
    }
    return .init(kind: .unknown, name: "", evidence: "")
  }
  public func label(russian: Bool) -> String {
    if kind == .unknown { return russian ? "Владелец не определён" : "Owner unknown" }
    return name + (metadataMatched ? (russian ? " · по метаданным" : " · metadata match") : (russian ? " · по расположению" : " · inferred from path"))
  }
}

public enum AgentDataKind: String, CaseIterable, Sendable {
  case history, cache, working, unknown
  public func title(russian: Bool) -> String {
    switch self {
    case .history: return russian ? "Истории и экспорты" : "Histories and exports"
    case .cache: return russian ? "Служебные кэши" : "Service caches"
    case .working: return russian ? "Рабочие данные и базы" : "Working data and databases"
    case .unknown: return russian ? "Неопределённые данные" : "Unclassified data"
    }
  }
  public static func classify(_ path: String, root: String) -> Self {
    guard Scanner.inside(path, root) else { return .unknown }
    let relative = String(path.dropFirst(root.count)).lowercased()
    let parts = relative.split(separator: "/")
    let ext = (path as NSString).pathExtension.lowercased()
    if ["db", "sqlite", "sqlite3", "vscdb"].contains(ext) || parts.contains("checkpoints") || parts.contains("worktrees") { return .working }
    if parts.contains("cache") || parts.contains("caches") || parts.contains("cacheddata") { return .cache }
    if ["jsonl", "json", "md", "txt"].contains(ext), parts.contains(where: { ["sessions", "archived_sessions", "agent-transcripts", "chats", "tasks"].contains($0) }) || ext == "jsonl" { return .history }
    return .unknown
  }
}

/// Read-only metadata catalog. A bundle-ID match describes ownership, never removability.
public struct OwnershipCatalog: Sendable {
  public struct Application: Sendable {
    public let id: String
    public let name: String
    public let path: String
  }
  public struct Project: Sendable {
    public let path: String
    public let marker: String
  }
  public let applications: [Application]
  public let projects: [Project]
  public init(applications: [Application] = [], projects: [Project] = []) {
    self.applications = applications; self.projects = projects
  }
  public static func load(appRoots: [URL], projectRoots: [URL], cancellation: Cancellation = Cancellation()) throws -> Self {
    try cancellation.check()
    var apps: [Application] = [], seen = Set<String>()
    let fm = FileManager.default
    // Root and one grouping folder only; never traverse the user's entire disk or app internals.
    for root in appRoots {
      let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
      var candidates = children.filter { $0.pathExtension == "app" }
      for child in children where child.pathExtension != "app" {
        try cancellation.check()
        guard let info = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), info.isDirectory == true, info.isSymbolicLink != true else { continue }
        candidates += ((try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
      }
      for app in candidates {
        try cancellation.check()
        guard app.resolvingSymlinksInPath().path == app.path, seen.insert(app.path).inserted else { continue }
        let info = app.appendingPathComponent("Contents/Info.plist")
        guard let record = try? FileRecord.read(info), record.bytes < 1_000_000,
          let bytes = try? Data(contentsOf: info),
          let plist = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
          let id = plist["CFBundleIdentifier"] as? String, !id.isEmpty,
          (try? record.validate()) != nil else { continue }
        let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? app.deletingPathExtension().lastPathComponent
        apps.append(.init(id: id, name: name, path: app.path))
      }
    }
    var projects: [Project] = []
    for root in Set(projectRoots) {
      try cancellation.check()
      guard root.standardizedFileURL.path == root.path, root.resolvingSymlinksInPath().path == root.path else { continue }
      for marker in ["Package.swift", "package.json", "Cargo.toml", "pyproject.toml", "Podfile", "pom.xml", "settings.gradle", "settings.gradle.kts"] {
        guard let record = try? FileRecord.read(root.appendingPathComponent(marker)), record.bytes < 2_000_000 else { continue }
        projects.append(.init(path: root.path, marker: marker)); break
      }
    }
    return .init(applications: apps, projects: projects)
  }
  public func identify(_ path: String, home: URL, russian: Bool) -> DataOwnership {
    let fallback = DataOwnership.identify(path, home: home)
    guard path.hasPrefix("/"), (path as NSString).standardizingPath == path else { return fallback }
    if fallback.kind == .agent { return fallback }
    if let bundle = applications.first(where: { Scanner.inside(path, $0.path) }) {
      return .init(kind: .application, name: bundle.name, evidence: "Info.plist · \(bundle.id) · \(bundle.path)", metadataMatched: true)
    }
    let prefix = home.appendingPathComponent("Library/Containers").path + "/"
    if path.hasPrefix(prefix), let id = path.dropFirst(prefix.count).split(separator: "/").first {
      let matches = applications.filter { $0.id == String(id) }
      if matches.count == 1, let app = matches.first {
        return .init(kind: .application, name: app.name,
          evidence: (russian ? "Идентификатор контейнера совпал с Info.plist: " : "Container ID matches Info.plist: ") + app.id + " · " + app.path, metadataMatched: true)
      }
    }
    if let project = projects.filter({ Scanner.inside(path, $0.path) }).max(by: { $0.path.count < $1.path.count }) {
      return .init(kind: .project, name: (project.path as NSString).lastPathComponent,
        evidence: (russian ? "Выбранный проект, найден маркер: " : "Selected project, marker found: ") + project.path + "/" + project.marker, metadataMatched: true)
    }
    return fallback
  }
}
