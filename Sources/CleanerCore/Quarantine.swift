import Foundation

public struct QuarantineEntry: Codable, Identifiable, Sendable {
  public let id: UUID
  public let original: String
  public let bytes: Int64
  public let date: Date
  public let hash: String
  public var state: String
}
public final class QuarantineStore: @unchecked Sendable {
  public let root: URL
  private let lock = NSLock()
  public init(root: URL) throws {
    self.root = root.standardizedFileURL
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  }
  private func folder(_ id: UUID) -> URL {
    root.appendingPathComponent(id.uuidString, isDirectory: true)
  }
  private func save(_ e: QuarantineEntry) throws {
    try JSONEncoder().encode(e).write(
      to: folder(e.id).appendingPathComponent("entry.json"), options: .atomic)
  }
  public func entries() -> [QuarantineEntry] {
    lock.lock()
    defer { lock.unlock() }
    return
      ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))
      ?? []).compactMap { u in
        guard let data = try? Data(contentsOf: u.appendingPathComponent("entry.json")) else {
          return nil
        }
        return try? JSONDecoder().decode(QuarantineEntry.self, from: data)
      }.sorted { $0.date > $1.date }
  }
  public static func protected(_ path: String) -> Bool {
    let components = URL(fileURLWithPath: path).pathComponents
    let blocked: Set<String> = [
      ".git", ".ssh", ".gnupg", ".aws", ".azure", "Keychains", "MobileDevice", "CoreSimulator",
      ".codex", ".claude", ".gemini", ".continue", ".aider", ".ollama", ".config",
      "Application Support", "workspaceStorage", "globalStorage",
    ]
    if components.contains(where: {
      $0.hasSuffix(".app") || $0.hasSuffix(".xcarchive") || $0.hasSuffix(".framework")
        || $0.hasSuffix(".bundle")
    }) {
      return true
    }
    if !blocked.isDisjoint(with: components) { return true }
    let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    if name == ".env" || name.hasPrefix(".env.")
      || [
        "key", "pem", "p12", "p8", "mobileprovision", "cer", "swift", "m", "h", "py", "js", "ts",
        "rs", "go",
      ].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    {
      return true
    }
    return ["/System", "/Library", "/usr", "/bin", "/sbin", "/private"].contains {
      Scanner.inside(path, $0)
    }
  }
  public func move(_ file: FileRecord, protectedPaths: [String] = []) throws -> QuarantineEntry {
    lock.lock()
    defer { lock.unlock() }
    let source = URL(fileURLWithPath: file.path)
    guard source.resolvingSymlinksInPath().path == source.standardizedFileURL.path else {
      throw CleanerError.message("Symbolic links are not eligible")
    }
    guard !Self.protected(file.path), !Scanner.inside(file.path, root.path),
      !protectedPaths.contains(where: { Scanner.inside(file.path, $0) }), file.links == 1
    else { throw CleanerError.message("Protected file; no changes made") }
    var parent = source.deletingLastPathComponent()
    while parent.path != "/" {
      if FileManager.default.fileExists(atPath: parent.appendingPathComponent(".git").path) {
        throw CleanerError.message("Project files are analysis-only in this preview")
      }
      parent.deleteLastPathComponent()
    }
    try file.validate()
    let digest = try Scanner.hash(source)
    try file.validate()
    var entry = QuarantineEntry(
      id: UUID(), original: file.path, bytes: file.bytes, date: Date(), hash: digest,
      state: "prepared")
    let dir = folder(entry.id)
    try FileManager.default.createDirectory(
      at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    try save(entry)
    let payload = dir.appendingPathComponent("payload")
    // Same-volume rename only. Never fall back to an unverified copy/delete.
    let rootAttrs = try FileManager.default.attributesOfItem(atPath: root.path)
    guard (rootAttrs[.systemNumber] as? NSNumber)?.uint64Value == file.device else {
      throw CleanerError.message(
        "Cross-volume quarantine is not supported in this preview; source is intact")
    }
    try file.validate()
    guard rename(source.path, payload.path) == 0 else {
      throw CleanerError.message("Could not move file: \(String(cString:strerror(errno)))")
    }
    entry.state = "quarantined"
    try save(entry)
    return entry
  }
  public func restore(_ entry: QuarantineEntry, destination: URL? = nil) throws {
    lock.lock()
    defer { lock.unlock() }
    let dest = destination ?? URL(fileURLWithPath: entry.original)
    let payload = folder(entry.id).appendingPathComponent("payload")
    guard !FileManager.default.fileExists(atPath: dest.path) else {
      throw CleanerError.message("Destination already exists; choose another name")
    }
    guard
      dest.deletingLastPathComponent().resolvingSymlinksInPath()
        == dest.deletingLastPathComponent().standardizedFileURL
    else { throw CleanerError.message("Destination parent contains symbolic links") }
    guard try Scanner.hash(payload) == entry.hash else {
      throw CleanerError.message("Integrity check failed; quarantine retained")
    }
    guard FileManager.default.fileExists(atPath: dest.deletingLastPathComponent().path) else {
      throw CleanerError.message("Original folder missing; choose another destination")
    }
    // COPYFILE_EXCL semantics through moveItem: do not overwrite conflicts.
    try FileManager.default.moveItem(at: payload, to: dest)
    var saved = entry
    saved.state = "restored"
    try save(saved)
  }
  public func erase(_ entry: QuarantineEntry) throws {
    lock.lock()
    defer { lock.unlock() }
    let payload = folder(entry.id).appendingPathComponent("payload")
    guard FileManager.default.fileExists(atPath: payload.path) else {
      throw CleanerError.message("No quarantined payload")
    }
    try FileManager.default.removeItem(at: payload)
    var saved = entry
    saved.state = "deleted"
    try save(saved)
  }
  public static func reminderDue(entries: [QuarantineEntry], last: Date?, now: Date = Date())
    -> Bool
  {
    let active = entries.filter { $0.state == "quarantined" || $0.state == "prepared" }
    guard let oldest = active.map(\.date).min() else { return false }
    return now.timeIntervalSince(last ?? oldest) >= 5 * 24 * 3600
  }
}
