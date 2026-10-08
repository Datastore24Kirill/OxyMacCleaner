import Darwin
import Foundation

public struct QuarantineEntry: Codable, Identifiable, Sendable {
  public let id: UUID
  public let original: String
  public let bytes: Int64
  public let date: Date
  public var hash: String
  public var kind: String? = nil
  public var restoreDestination: String? = nil
  public var archiveBackup: String? = nil
  public var archive: Bool? = nil
  public var externalPayload: String? = nil
  public var restoreDigest: String? = nil
  public var previousPayload: String? = nil
  public var originalVolumeUUID: String? = nil
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
  private func payloadURL(_ entry: QuarantineEntry) -> URL {
    entry.externalPayload.map { URL(fileURLWithPath: $0) } ?? folder(entry.id).appendingPathComponent("payload")
  }
  private func checkPayloadPath(_ url: URL) throws {
    guard url.resolvingSymlinksInPath() == url.standardizedFileURL else {
      throw CleanerError.message("Quarantine path contains symbolic links")
    }
  }
  /// Relocate an already quarantined object; local journal retains its external location.
  public func relocate(_ entry: QuarantineEntry, to directory: URL, cancellation: Cancellation = Cancellation()) throws {
    lock.lock(); defer { lock.unlock() }
    let fm = FileManager.default
    let source = payloadURL(entry)
    if let previous = entry.previousPayload, fm.fileExists(atPath: previous) { throw CleanerError.message("Previous transfer copy remains; inspect it before relocating again") }
    try checkPayloadPath(source)
    guard entry.state == "quarantined", try payloadHash(entry, source) == entry.hash,
      directory.resolvingSymlinksInPath() == directory.standardizedFileURL,
      !Scanner.inside(directory.path, root.path), !Scanner.inside(directory.path, source.path),
      try directory.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey]).isDirectory == true,
      try directory.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem != true else {
      throw CleanerError.message("Choose a local folder outside the quarantine; source retained")
    }
    let capsule = directory.appendingPathComponent("OxyQuarantine-" + UUID().uuidString)
    try fm.createDirectory(at: capsule, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let destination = capsule.appendingPathComponent("payload")
    var published = false
    defer { if !published { try? fm.removeItem(at: capsule) } }
    try cancellation.check()
    try verifiedCopy(entry, from: source, to: destination, cancellation: cancellation)
    var next = entry; next.previousPayload = source.path; next.externalPayload = destination.path; next.hash = try payloadHash(entry, destination)
    try JSONEncoder().encode(next).write(to: capsule.appendingPathComponent("entry.json"), options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: capsule.appendingPathComponent("entry.json").path)
    try cancellation.check()
    guard try payloadHash(entry, source) == entry.hash else { throw CleanerError.message("Quarantine changed during copy; source retained") }
    try save(next); published = true
    // The verified external copy and local journal are durable before removing the old payload.
    do { try fm.removeItem(at: source); next.previousPayload = nil; try save(next) }
    catch { throw CleanerError.message("Verified external copy is ready, but the old payload could not be fully removed: " + source.path) }
  }
  private func verifiedCopy(_ entry: QuarantineEntry, from source: URL, to destination: URL,
    cancellation: Cancellation = Cancellation()) throws {
    try checkPayloadPath(source)
    guard try payloadHash(entry, source) == entry.hash else { throw CleanerError.message("Integrity check failed; source retained") }
    try cancellation.check()
    let space = try destination.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
    try Self.validateCopySpace(required: entry.bytes, available: space.map(Int64.init))
    try FileManager.default.copyItem(at: source, to: destination)
    try cancellation.check()
    if entry.kind == "directory" {
      guard try ArchiveTransfer.sameContents(DirectoryManifest.capture(source, cancellation: cancellation), DirectoryManifest.capture(destination, cancellation: cancellation)) else { throw CleanerError.message("Copied folder differs; source retained") }
    } else {
      guard try Scanner.hash(destination, cancellation: cancellation) == entry.hash else { throw CleanerError.message("Copied file differs; source retained") }
    }
    guard try payloadHash(entry, source) == entry.hash else { throw CleanerError.message("Source changed during copy; source retained") }
  }
  public static func validateCopySpace(required: Int64, available: Int64?) throws {
    guard required >= 0, let available, available >= 0 else { throw CleanerError.message("Cannot determine destination free space; source retained") }
    let (budget, overflow) = required.addingReportingOverflow(10_000_000)
    guard !overflow, available >= budget else { throw CleanerError.message("Insufficient space on destination; source retained") }
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
    entry.originalVolumeUUID = try source.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
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
    entry.originalVolumeUUID = try URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    try fm.createDirectory(
      at: folder(entry.id), withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    try save(entry)
    try cancellation.check()
    let payload = payloadURL(entry)
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
  private func payloadHash(_ entry: QuarantineEntry, _ payload: URL, cancellation: Cancellation = Cancellation()) throws -> String {
    try checkPayloadPath(payload)
    if entry.kind == "directory" { return try DirectoryManifest.capture(payload, cancellation: cancellation).digest }
    return try Scanner.hash(payload, cancellation: cancellation)
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
      let payload = payloadURL(entry)
      if entry.state == "prepared" || entry.state == "restoring" || (entry.state == "restored" && fm.fileExists(atPath: payload.path)) {
        if ["restoring", "restored"].contains(entry.state), let destination = entry.restoreDestination,
          (try? payloadHash(entry, URL(fileURLWithPath: destination))) == (entry.restoreDigest ?? entry.hash) {
          entry.state = fm.fileExists(atPath: payload.path) ? "restored-copy" : "restored"
        } else if fm.fileExists(atPath: payload.path) {
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
  public func restore(_ entry: QuarantineEntry, destination: URL? = nil, cancellation: Cancellation = Cancellation()) throws {
    lock.lock()
    defer { lock.unlock() }
    try cancellation.check()
    let dest = destination ?? URL(fileURLWithPath: entry.original)
    let payload = payloadURL(entry)
    try Self.validateRestoreVolume(entry, destination: dest)
    guard !FileManager.default.fileExists(atPath: dest.path) else {
      throw CleanerError.message("Destination already exists; choose another name")
    }
    guard
      dest.deletingLastPathComponent().resolvingSymlinksInPath()
        == dest.deletingLastPathComponent().standardizedFileURL
    else { throw CleanerError.message("Destination parent contains symbolic links") }
    guard try payloadHash(entry, payload, cancellation: cancellation) == entry.hash else {
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
    if sourceDevice != destinationDevice {
      let stage = dest.deletingLastPathComponent().appendingPathComponent(".oxy-restore-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: stage) }
      try verifiedCopy(entry, from: payload, to: stage, cancellation: cancellation)
      try cancellation.check()
      var saved = entry; saved.state = "restoring"; saved.restoreDestination = dest.path
      saved.restoreDigest = try payloadHash(entry, stage)
      try save(saved)
      try Self.validateRestoreVolume(entry, destination: dest)
      guard renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, dest.path, UInt32(RENAME_EXCL)) == 0 else {
        throw CleanerError.message("Restore destination changed; quarantine retained")
      }
      saved.state = "restored"; try save(saved)
      // If removal fails, both verified copies remain; never remove the restored copy.
      do { try FileManager.default.removeItem(at: payload) }
      catch { saved.state = "restored-copy"; try save(saved); throw CleanerError.message("Restored successfully; old quarantine payload remains: " + payload.path) }
      return
    }
    try cancellation.check()
    var saved = entry
    saved.state = "restoring"
    saved.restoreDestination = dest.path
    try save(saved)
    try Self.validateRestoreVolume(entry, destination: dest)
    guard renameatx_np(AT_FDCWD, payload.path, AT_FDCWD, dest.path, UInt32(RENAME_EXCL)) == 0 else {
      throw CleanerError.message("Restore failed; quarantine retained")
    }
    saved.state = "restored"
    try save(saved)
  }
  /// UUID survives remounts, unlike a device number. Explicit alternative destinations remain allowed.
  static func validateRestoreVolume(_ entry: QuarantineEntry, destination: URL) throws {
    guard destination.standardizedFileURL.path == URL(fileURLWithPath: entry.original).standardizedFileURL.path,
      let expected = entry.originalVolumeUUID else { return }
    let actual = try? destination.deletingLastPathComponent().resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    guard actual == expected else {
      throw CleanerError.message("Original volume disconnected or replaced; reconnect it or choose another restore destination. Quarantine retained")
    }
  }
  public struct Inspection: Sendable {
    public let payload: String
    public let payloadValid: Bool
    public let payloadPresent: Bool
    public let destination: String?
    public let destinationValid: Bool
    public let previous: String?
  }
  public func inspect(_ entry: QuarantineEntry, cancellation: Cancellation = Cancellation()) -> Inspection {
    lock.lock(); defer { lock.unlock() }
    let payload = payloadURL(entry)
    let previous = entry.previousPayload ?? (entry.externalPayload != nil ? folder(entry.id).appendingPathComponent("payload").path : nil)
    return Inspection(payload: payload.path, payloadValid: (try? payloadHash(entry, payload, cancellation: cancellation)) == entry.hash,
      payloadPresent: FileManager.default.fileExists(atPath: payload.path), destination: entry.restoreDestination,
      destinationValid: entry.restoreDestination.map { (try? payloadHash(entry, URL(fileURLWithPath: $0), cancellation: cancellation)) == (entry.restoreDigest ?? entry.hash) } ?? false,
      previous: previous.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil })
  }
  public func trashRestoredCopy(_ entry: QuarantineEntry) throws {
    lock.lock(); defer { lock.unlock() }
    guard let fresh = try? JSONDecoder().decode(QuarantineEntry.self, from: Data(contentsOf: folder(entry.id).appendingPathComponent("entry.json"))), fresh.id == entry.id, fresh.state == "restored-copy",
      let destination = fresh.restoreDestination,
      try payloadHash(fresh, URL(fileURLWithPath: destination)) == (fresh.restoreDigest ?? fresh.hash),
      try payloadHash(fresh, payloadURL(fresh)) == fresh.hash else { throw CleanerError.message("Both copies must be verified; nothing removed") }
    var resulting: NSURL?
    try FileManager.default.trashItem(at: payloadURL(fresh), resultingItemURL: &resulting)
    var saved = fresh; saved.state = "restored"; try save(saved)
  }
  public func erase(_ entry: QuarantineEntry) throws {
    lock.lock()
    defer { lock.unlock() }
    let payload = payloadURL(entry)
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
