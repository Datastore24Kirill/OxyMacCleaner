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
  public var archive: Bool? = nil
  public var isArchive: Bool { archive == true || archiveBackup != nil }
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
    protected(path, archiveStorage: false)
  }
  // Only the dedicated archive operation may enter the standard Xcode Archives tree.
  private static func protected(_ path: String, archiveStorage: Bool) -> Bool {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let components = url.pathComponents.map { $0.lowercased() }
    let archives = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Developer/Xcode/Archives").path
    if components.contains("library") && !(archiveStorage && Scanner.inside(url.path, archives)) {
      return true
    }
    let blocked: Set<String> = [
      ".git", ".svn", ".hg", ".ssh", ".gnupg", ".aws", ".azure", "keychains",
      "mobiledevice", "coresimulator", ".codex", ".claude", ".gemini", ".continue",
      ".aider", ".ollama", ".config", ".cursor", ".windsurf", ".vscode", ".kilo",
      ".opencode", ".local", "application support", "workspacestorage", "globalstorage",
      "backups.backupdb", ".timemachine", ".documentrevisions-v100",
    ]
    let packages: Set<String> = [
      "app", "xcarchive", "framework", "bundle", "xcodeproj", "xcworkspace", "playground",
      "xcassets", "dsym", "photoslibrary", "photolibrary", "aplibrary", "musiclibrary",
      "sparsebundle", "backupbundle", "vmwarevm", "pvm",
    ]
    if !blocked.isDisjoint(with: components)
      || components.contains(where: { packages.contains(URL(fileURLWithPath: $0).pathExtension) }) {
      return true
    }
    let name = url.lastPathComponent.lowercased()
    if name == ".env" || name.hasPrefix(".env.")
      || ["package.swift", "package.resolved", "podfile", "podfile.lock", "cartfile",
          "cartfile.resolved", ".netrc", ".npmrc", ".pypirc"].contains(name)
      || ["key", "pem", "p12", "pfx", "p8", "mobileprovision", "provisionprofile", "cer",
          "keychain", "keychain-db", "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp",
          "py", "js", "jsx", "ts", "tsx", "rs", "go", "kt", "java", "dart", "cs",
          "pbxproj", "xcconfig", "entitlements", "storyboard", "xib", "sparseimage"
      ].contains(url.pathExtension.lowercased()) {
      return true
    }
    // Apply system-root rules to mounted disks as well as the startup disk.
    let systemPath = components.count >= 3 && components[1] == "volumes"
      ? "/" + components.dropFirst(3).joined(separator: "/") : url.path.lowercased()
    return ["/system", "/library", "/usr", "/bin", "/sbin", "/private", "/dev",
            "/etc", "/var", "/applications", "/opt"].contains {
      Scanner.inside(systemPath, $0)
    }
  }
  private static func projectDirectory(_ directory: URL) -> Bool {
    let fm = FileManager.default
    let markers = [".git", ".hg", ".svn", "Package.swift", "package.json", "Cargo.toml",
                   "pyproject.toml", "go.mod", "pubspec.yaml", "build.gradle", "CMakeLists.txt"]
    if markers.contains(where: { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
      return true
    }
    // Protect assets/configuration alongside an Xcode project, even without a Git repository.
    return ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).contains {
      ["xcodeproj", "xcworkspace"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
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
      if Self.projectDirectory(parent) {
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
      !(plan.backup.map { Scanner.inside($0.path, root.path) } ?? false)
    else {
      throw CleanerError.message("Protected or retained archive cannot be moved")
    }
    return try moveDirectoryChecked(
      plan.source, expected: plan.manifest, protectedPaths: protectedPaths,
      cancellation: cancellation, archivePlan: plan)
  }
  /// Explicit permanent deletion after a confirmed cleanup plan. Backup is optional.
  /// No quarantine payload is created; without a backup this is irreversible.
  public func deleteArchive(
    _ plan: ArchiveTransferPlan, pinned: Set<String>, retained: Set<String>,
    protectedPaths: [String] = [], cancellation: Cancellation = Cancellation(),
    idle: () throws -> Void = DeveloperActivity.assertArchivesIdle
  ) throws {
    lock.lock()
    defer { lock.unlock() }
    try cancellation.check()
    try idle()
    let fm = FileManager.default
    let source = plan.source.standardizedFileURL
    let path = source.path
    let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    let archives = library.appendingPathComponent("Developer/Xcode/Archives")
    guard source.pathExtension == "xcarchive",
      !pinned.contains(path), !retained.contains(path),
      !Self.protected(source.deletingLastPathComponent().path, archiveStorage: true),
      !Scanner.inside(path, library.path) || Scanner.inside(path, archives.path),
      source.resolvingSymlinksInPath() == source,
      !Scanner.inside(path, root.path), !Scanner.inside(root.path, path),
      !(plan.backup.map { Scanner.inside($0.path, root.path) } ?? false),
      !(plan.backup.map { Scanner.inside($0.path, path) || Scanner.inside(path, $0.path) } ?? false)
    else { throw CleanerError.message("Protected or retained archive cannot be deleted") }
    var ancestor = source
    while ancestor.path != "/" {
      guard !Self.projectDirectory(ancestor) else {
        throw CleanerError.message("Project directories are analysis-only")
      }
      ancestor.deleteLastPathComponent()
    }
    try ArchiveTransfer.validate(plan, cancellation: cancellation)
    let actual = try DirectoryManifest.capture(source, cancellation: cancellation) { candidate in
      guard
        !protectedPaths.contains(where: {
          Scanner.inside(candidate, $0) || Scanner.inside($0, candidate)
        })
      else { throw CleanerError.message("Archive contains excluded data") }
    }
    guard actual == plan.manifest else {
      throw CleanerError.message("Archive changed after preview; deletion blocked")
    }
    try idle()
    try cancellation.check()
    // Cancellation is observed between archives, never during recursive deletion.
    do {
      try fm.removeItem(at: source)
    } catch {
      throw CleanerError.message(
        "Archive deletion failed and may be partial. "
          + (plan.backup.map { "Retained backup: " + $0.path }
            ?? "No backup was requested; deleted files cannot be restored by this app")
          + ". " + error.localizedDescription)
    }
  }
  public func moveDerivedData(
    _ plan: DerivedDataPlan, protectedPaths: [String] = [],
    cancellation: Cancellation = Cancellation(),
    idle: () throws -> Void = DeveloperActivity.assertIdle
  ) throws -> QuarantineEntry {
    try idle()
    guard DerivedData.allowed(plan.source) else {
      throw CleanerError.message("Unknown DerivedData path")
    }
    return try moveDirectoryChecked(
      plan.source, expected: plan.manifest, protectedPaths: protectedPaths,
      cancellation: cancellation, archivePlan: nil, derived: true, derivedIdle: idle)
  }
  private func moveDirectoryChecked(
    _ source: URL, expected: DirectoryManifest, protectedPaths: [String],
    cancellation: Cancellation, archivePlan: ArchiveTransferPlan?, derived: Bool = false,
    derivedIdle: () throws -> Void = DeveloperActivity.assertIdle
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
        source.pathExtension == "xcarchive" && !Self.protected(parent, archiveStorage: true)
        && (!Scanner.inside(
          path, fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").path)
          || Scanner.inside(path, archiveRoot))
      guard archiveAllowed else { throw CleanerError.message("Archive location is protected") }
      try ArchiveTransfer.validate(plan, cancellation: cancellation)
    } else {
      archiveAllowed = false
    }
    let generatedAllowed = derived && DerivedData.allowed(source)
    guard
      archiveAllowed || generatedAllowed
        || !Scanner.inside(
          path, fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").path),
      !["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].contains(where: {
        source == fm.homeDirectoryForCurrentUser.appendingPathComponent($0)
      }),
      source.resolvingSymlinksInPath().path == path,
      archiveAllowed || generatedAllowed || !Self.protected(path), !Scanner.inside(path, root.path),
      !Scanner.inside(root.path, path),
      path != fm.homeDirectoryForCurrentUser.path,
      ![
        "/", "/Users", "/Applications",
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").path,
      ].contains(path)
    else { throw CleanerError.message("Protected directory") }
    var ancestor = source
    while ancestor.path != "/" {
      guard !Self.projectDirectory(ancestor) else {
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
      if derived && DerivedData.protectedContent(candidate) {
        throw CleanerError.message("Cache contains protected data")
      }
      guard archiveAllowed || generatedAllowed || !Self.protected(candidate),
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
      kind: "directory", archiveBackup: archivePlan?.backup?.path, archive: archivePlan != nil,
      state: "prepared")
    try fm.createDirectory(
      at: folder(entry.id), withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    try save(entry)
    try cancellation.check()
    let payload = folder(entry.id).appendingPathComponent("payload")
    if derived { try derivedIdle() }
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
