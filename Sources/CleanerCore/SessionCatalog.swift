import Foundation

public struct SessionFile: Identifiable, Sendable {
  public var id: String { url.path }
  public let url: URL
  public let bytes: Int64
  public let modified: Date
  public var importable: Bool { bytes > 0 && bytes <= 1_000_000_000 }
}
public struct SessionCatalogResult: Sendable {
  public var files: [SessionFile] = []
  public var issues = 0
  public var limited = false
}
public enum SessionCatalog {
  /// Metadata only. Native format/session identity is validated when a user opens a file.
  public static func discover(roots: [URL], cancellation: Cancellation = Cancellation(),
    maximumEntries: Int = 20_000, agent: String? = nil) throws -> SessionCatalogResult {
    var result = SessionCatalogResult()
    var pending = roots
    var seen = Set<String>()
    var visited = 0
    let fm = FileManager.default
    while let url = pending.popLast() {
      try cancellation.check()
      guard visited < maximumEntries else { result.limited = true; break }
      visited += 1
      let path = url.standardizedFileURL.path
      guard seen.insert(path).inserted else { continue }
      do {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey,
          .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey])
        guard values.isSymbolicLink != true, values.isUbiquitousItem != true,
          url.resolvingSymlinksInPath().path == path else { result.issues += 1; continue }
        if values.isDirectory == true {
          // Directory enumeration streams entries, avoiding unbounded arrays in large stores.
          guard let iterator = fm.enumerator(at: url, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants], errorHandler: { _, _ in
              result.issues += 1; return true
            }) else { result.issues += 1; continue }
          for case let child as URL in iterator {
            try cancellation.check()
            if pending.count + visited >= maximumEntries { result.limited = true; break }
            pending.append(child)
          }
        } else if values.isRegularFile == true, ((agent == "aider" && url.lastPathComponent == ".aider.chat.history.md") || url.pathExtension.lowercased() == "jsonl" || (agent.map { JSONHistory.agents.contains($0) } == true && url.pathExtension.lowercased() == "json")) {
          if ["cline", "roo"].contains(agent ?? ""), url.lastPathComponent != "api_conversation_history.json" { continue }
          if agent == "continue", url.lastPathComponent == "sessions.json" { continue }
          guard let size = values.fileSize, let modified = values.contentModificationDate else {
            result.issues += 1; continue
          }
          result.files.append(SessionFile(url: url, bytes: Int64(size), modified: modified))
        }
      } catch is CancellationError { throw CancellationError() }
      catch { try cancellation.check(); result.issues += 1 }
    }
    result.files.sort { $0.modified == $1.modified ? $0.id < $1.id : $0.modified > $1.modified }
    return result
  }
}
