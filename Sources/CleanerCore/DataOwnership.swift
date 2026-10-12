import Foundation

/// Attribution is descriptive only. It never grants permission to remove data.
public struct DataOwnership: Sendable, Equatable {
  public enum Kind: String, Sendable { case agent, application, project, unknown }
  public let kind: Kind
  public let name: String
  public let evidence: String
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
    return name + (russian ? " · по расположению" : " · inferred from path")
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
