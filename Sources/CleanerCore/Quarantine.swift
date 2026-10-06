import Darwin
import Foundation

public struct QuarantineEntry: Codable, Identifiable, Sendable {
  public let id: UUID
  public let original: String
  public let bytes: Int64
  public let date: Date
  public let hash: String
  public var kind: String? = nil
  public var restoreDestination: String? = nil
  public var archiveBackup: String? = nil
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
  public func moveDirectory(
    _ source: URL, expected: DirectoryManifest, protectedPaths: [String] = [],
    cancellation: Cancellation = Cancellation()
  ) throws -> QuarantineEntry {
    try moveDirectoryChecked(
      source, expected: expected, protectedPaths: protectedPaths, cancellation: cancellation,
      archivePlan: nil)
  }
  public func moveArchive(
    _ plan: ArchiveTransferPlan, pinned: Set<String>, retained: Set<String>,
    protectedPaths: [String] = [], cancellation: Cancellation = Cancellation()
  ) throws -> QuarantineEntry {
    guard !pinned.contains(plan.source.path), !retained.contains(plan.source.path),
      !Scanner.inside(plan.backup.path, root.path)
    else {
      throw CleanerError.message("Pinned, retained or unbacked archive cannot be moved")
    }
    return try moveDirectoryChecked(
      plan.source, expected: plan.manifest, protectedPaths: protectedPaths,
      cancellation: cancellation, archivePlan: plan)
  }
  private func moveDirectoryChecked(
    _ source: URL, expected: DirectoryManifest, protectedPaths: [String],
    cancellation: Cancellation, archivePlan: ArchiveTransferPlan?
  ) throws -> QuarantineEntry {
    lock.lock()
    defer { lock.unlock() }
    let fm = FileManager.default
    let path = source.standardizedFileURL.path
    let archiveAllowed: Bool
    if let plan = archivePlan {
      let archiveRoot = fm.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Developer/Xcode/Archives"
      ).path
      let parent = source.deletingLastPathComponent().path
      archiveAllowed =
        source.pathExtension == "xcarchive" && !Self.protected(parent)
        && (!Scanner.inside(
          path, fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").path)
          || Scanner.inside(path, archiveRoot))
      guard archiveAllowed else { throw CleanerError.message("Archive location is protected") }
      try ArchiveTransfer.validate(plan, cancellation: cancellation)
    } else {
      archiveAllowed = false
    }
    guard
      archiveAllowed
        || !Scanner.inside(
          path, fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").path),
      !["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].contains(where: {
        source == fm.homeDirectoryForCurrentUser.appendingPathComponent($0)
      }),
      source.resolvingSymlinksInPath().path == path,
      archiveAllowed || !Self.protected(path), !Scanner.inside(path, root.path),
      !Scanner.inside(root.path, path),
      path != fm.homeDirectoryForCurrentUser.path,
      ![
        "/", "/Users", "/Applications",
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").path,
      ].contains(path)
    else { throw CleanerError.message("Protected directory") }
    var ancestor = source
    while ancestor.path != "/" {
      guard !fm.fileExists(atPath: ancestor.appendingPathComponent(".git").path) else {
        throw CleanerError.message("Project directories are analysis-only")
      }
      ancestor.deleteLastPathComponent()
    }
    let device = (try fm.attributesOfItem(atPath: root.path)[.systemNumber] as? NSNumber)?
      .uint64Value
    guard expected.items.first(where: { $0.relative.isEmpty })?.device == device else {
      throw CleanerError.message(
        "Cross-volume folder quarantine is not supported; source is intact")
    }
    let actual = try DirectoryManifest.capture(source, cancellation: cancellation) { candidate in
      guard archiveAllowed || !Self.protected(candidate),
        !protectedPaths.contains(where: {
          Scanner.inside(candidate, $0) || Scanner.inside($0, candidate)
        })
      else {
        throw CleanerError.message("Folder contains protected or excluded data: \(candidate)")
      }
    }
    guard expected == actual else {
      throw CleanerError.message("Directory changed after preview; review it again")
    }
    var entry = QuarantineEntry(
      id: UUID(), original: path, bytes: expected.bytes, date: Date(), hash: try expected.digest,
      kind: "directory", archiveBackup: archivePlan?.backup.path, state: "prepared")
    try fm.createDirectory(
      at: folder(entry.id), withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    try save(entry)
    try cancellation.check()
    let payload = folder(entry.id).appendingPathComponent("payload")
    guard renameatx_np(AT_FDCWD, path, AT_FDCWD, payload.path, UInt32(RENAME_EXCL)) == 0 else {
      throw CleanerError.message("Could not move directory; source retained")
    }
    // Once moved, finish verification even if cancellation was requested.
    guard try DirectoryManifest.capture(payload).digest == entry.hash else {
      entry.state = "attention"
      try save(entry)
      throw CleanerError.message(
        "Directory changed during transfer. Payload retained in quarantine for inspection")
    }
    entry.state = "quarantined"
    try save(entry)
    return entry
  }
  private func payloadHash(_ entry: QuarantineEntry, _ payload: URL) throws -> String {
    if entry.kind == "directory" { return try DirectoryManifest.capture(payload).digest }
    return try Scanner.hash(payload)
  }
  public func recover() throws {
    lock.lock()
    defer { lock.unlock() }
    let fm = FileManager.default
    for dir in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
      guard
        var entry = try? JSONDecoder().decode(
          QuarantineEntry.self, from: Data(contentsOf: dir.appendingPathComponent("entry.json"))),
        dir.lastPathComponent == entry.id.uuidString
      else { continue }
      let payload = folder(entry.id).appendingPathComponent("payload")
      if entry.state == "prepared" || entry.state == "restoring" {
        if fm.fileExists(atPath: payload.path) {
          entry.state =
            (try? payloadHash(entry, payload)) == entry.hash ? "quarantined" : "attention"
        } else if entry.state == "restoring", let destination = entry.restoreDestination,
          (try? payloadHash(entry, URL(fileURLWithPath: destination))) == entry.hash
        {
          entry.state = "restored"
        } else if entry.state == "prepared", fm.fileExists(atPath: entry.original) {
          entry.state = "cancelled"
        } else {
          entry.state = "attention"
        }
        try save(entry)
      }
    }
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
    guard try payloadHash(entry, payload) == entry.hash else {
      throw CleanerError.message("Integrity check failed; quarantine retained")
    }
    guard FileManager.default.fileExists(atPath: dest.deletingLastPathComponent().path) else {
      throw CleanerError.message("Original folder missing; choose another destination")
    }
    let sourceDevice =
      (try FileManager.default.attributesOfItem(atPath: payload.path)[.systemNumber] as? NSNumber)?
      .uint64Value
    let destinationDevice =
      (try FileManager.default.attributesOfItem(atPath: dest.deletingLastPathComponent().path)[
        .systemNumber] as? NSNumber)?.uint64Value
    guard sourceDevice == destinationDevice else {
      throw CleanerError.message("Restore to the same disk; cross-volume restore is not supported")
    }
    var saved = entry
    saved.state = "restoring"
    saved.restoreDestination = dest.path
    try save(saved)
    guard renameatx_np(AT_FDCWD, payload.path, AT_FDCWD, dest.path, UInt32(RENAME_EXCL)) == 0 else {
      throw CleanerError.message("Restore failed; quarantine retained")
    }
    saved.state = "restored"
    try save(saved)
  }
  public func erase(_ entry: QuarantineEntry) throws {
    lock.lock()
    defer { lock.unlock() }
    let payload = folder(entry.id).appendingPathComponent("payload")
    guard entry.state == "quarantined", try payloadHash(entry, payload) == entry.hash else {
      throw CleanerError.message("Payload needs inspection; permanent deletion blocked")
    }
    guard FileManager.default.fileExists(atPath: payload.path) else {
      throw CleanerError.message("No quarantined payload")
    }
    if let backup = entry.archiveBackup {
      guard
        try ArchiveTransfer.sameContents(
          DirectoryManifest.capture(payload),
          DirectoryManifest.capture(URL(fileURLWithPath: backup)))
      else {
        throw CleanerError.message("Archive backup differs; permanent deletion blocked")
      }
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
