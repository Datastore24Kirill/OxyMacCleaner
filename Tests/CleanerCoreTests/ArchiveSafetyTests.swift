import XCTest

@testable import CleanerCore

final class ArchiveSafetyTests: XCTestCase {
  var root: URL!
  override func setUpWithError() throws {
    root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Downloads/OxyArchiveTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
  func word(_ value: UInt32, little: Bool = true) -> [UInt8] {
    let b = [
      UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
      UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24),
    ]
    return little ? b : b.reversed()
  }
  func macho(_ uuid: UInt8 = 1, little: Bool = true, type: UInt32 = 2) -> Data {
    Data(
      [UInt32(0xfeed_facf), 0x100000c, 0, type, 1, 24, 0, 0, 0x1b, 24].flatMap {
        word($0, little: little)
      } + Array(repeating: uuid, count: 16))
  }
  func writePlist(_ value: [String: Any], _ url: URL) throws {
    try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(
      to: url)
  }
  func fixture() throws -> URL {
    let source = root.appendingPathComponent("Test.xcarchive")
    let app = source.appendingPathComponent("Products/Applications/Test.app")
    let dwarf = source.appendingPathComponent("dSYMs/Test.app.dSYM/Contents/Resources/DWARF")
    for dir in [app, dwarf] {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    try writePlist(
      [
        "ArchiveVersion": 2, "CreationDate": Date(timeIntervalSince1970: 100),
        "ApplicationProperties": [
          "ApplicationPath": "Applications/Test.app", "CFBundleIdentifier": "test.app",
          "Team": "TEAM", "CFBundleVersion": "1", "CFBundleShortVersionString": "1",
        ],
      ], source.appendingPathComponent("Info.plist"))
    try writePlist(["CFBundleExecutable": "Test"], app.appendingPathComponent("Info.plist"))
    try macho().write(to: app.appendingPathComponent("Test"))
    try macho(type: 10).write(to: dwarf.appendingPathComponent("Test"))
    try age(source)
    return source
  }
  func age(_ source: URL) throws {
    let paths =
      [source]
      + (FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil)?.allObjects
        as? [URL] ?? [])
    for path in paths {
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: path.path)
    }
  }
  func testThinEndianAndMalformedBounds() throws {
    let file = root.appendingPathComponent("macho")
    for little in [true, false] {
      try macho(little: little).write(to: file)
      XCTAssertEqual(try MachOUUIDs.read(file)?.count, 1)
    }
    var invalid = macho()
    invalid.replaceSubrange(36..<40, with: word(UInt32.max))
    try invalid.write(to: file)
    XCTAssertThrowsError(try MachOUUIDs.read(file))
    try Data("text".utf8).write(to: file)
    XCTAssertNil(try MachOUUIDs.read(file))
  }
  func testFatSlicesAndTruncation() throws {
    let file = root.appendingPathComponent("fat")
    let thin = macho()
    let header = [UInt32(0xcafe_babe), 1, 0x100000c, 0, 28, UInt32(thin.count), 0].flatMap {
      word($0, little: false)
    }
    try (Data(header) + thin).write(to: file)
    XCTAssertEqual(try MachOUUIDs.read(file)?.count, 1)
    try Data(header).write(to: file)
    XCTAssertThrowsError(try MachOUUIDs.read(file))
  }
  func testMatchesAndMissingSymbols() throws {
    let source = try fixture()
    XCTAssertTrue(try ArchiveSymbols.inspect(source).complete)
    try macho(2).write(
      to: source.appendingPathComponent("dSYMs/Test.app.dSYM/Contents/Resources/DWARF/Test"))
    let result = try ArchiveSymbols.inspect(source)
    XCTAssertFalse(result.complete)
    XCTAssertEqual(result.missing.count, 1)
    XCTAssertEqual(result.matched, 0)
  }
  func testExecutableCannotMasqueradeAsDSYM() throws {
    let source = try fixture()
    try macho().write(
      to: source.appendingPathComponent("dSYMs/Test.app.dSYM/Contents/Resources/DWARF/Test"))
    let report = try ArchiveSymbols.inspect(source)
    XCTAssertFalse(report.complete)
    XCTAssertFalse(report.issues.isEmpty)
  }
  func testCancelledBackupLeavesSourceAndNoDestination() throws {
    let source = try fixture()
    let backup = root.appendingPathComponent("Backup.xcarchive")
    let token = Cancellation()
    token.cancel()
    XCTAssertThrowsError(
      try ArchiveTransfer.createBackup(source: source, destination: backup, cancellation: token))
    XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
  func testEscapingApplicationMetadataRejected() throws {
    let source = try fixture()
    try writePlist(
      ["ApplicationProperties": ["ApplicationPath": "../escape.app"]],
      source.appendingPathComponent("Info.plist"))
    XCTAssertThrowsError(try ArchiveSymbols.inspect(source))
  }
  func testVerifiedBackupAndArchiveRoundTrip() throws {
    let source = try fixture()
    let backup = root.appendingPathComponent("Backup.xcarchive")
    try ArchiveTransfer.createBackup(source: source, destination: backup)
    let plan = try ArchiveTransfer.prepare(archive: XcodeArchives.read(source), backup: backup)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    XCTAssertThrowsError(try store.moveDirectory(source, expected: plan.manifest))
    XCTAssertThrowsError(try store.moveArchive(plan, pinned: [source.path], retained: []))
    XCTAssertThrowsError(try store.moveArchive(plan, pinned: [], retained: [source.path]))
    let entry = try store.moveArchive(plan, pinned: [], retained: [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    try store.restore(entry)
    XCTAssertEqual(try DirectoryManifest.capture(source), plan.manifest)
  }
  func testChangedBackupAndRecentArchiveBlocked() throws {
    let source = try fixture()
    let backup = root.appendingPathComponent("Backup.xcarchive")
    try ArchiveTransfer.createBackup(source: source, destination: backup)
    let plan = try ArchiveTransfer.prepare(archive: XcodeArchives.read(source), backup: backup)
    try Data("changed".utf8).write(to: backup.appendingPathComponent("extra"))
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    XCTAssertThrowsError(try store.moveArchive(plan, pinned: [], retained: []))
    XCTAssertThrowsError(
      try ArchiveTransfer.prepare(archive: XcodeArchives.read(source), backup: backup))
    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: source.path)
    XCTAssertThrowsError(
      try ArchiveTransfer.prepare(archive: XcodeArchives.read(source), backup: backup))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
  func testMissingBackupBlocksEraseButAllowsRestore() throws {
    let source = try fixture()
    let backup = root.appendingPathComponent("Backup.xcarchive")
    try ArchiveTransfer.createBackup(source: source, destination: backup)
    let plan = try ArchiveTransfer.prepare(archive: XcodeArchives.read(source), backup: backup)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    let entry = try store.moveArchive(plan, pinned: [], retained: [])
    XCTAssertEqual(entry.archiveBackup, backup.path)
    try FileManager.default.removeItem(at: backup)
    XCTAssertThrowsError(try store.erase(entry))
    try store.restore(entry)
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
  func testChangedArchiveSnapshotCannotAuthorizeTransfer() throws {
    let source = try fixture()
    let old = try XcodeArchives.read(source)
    let backup = root.appendingPathComponent("Backup.xcarchive")
    try Data("another file".utf8).write(to: source.appendingPathComponent("added"))
    try age(source)
    try ArchiveTransfer.createBackup(source: source, destination: backup)
    XCTAssertThrowsError(try ArchiveTransfer.prepare(archive: old, backup: backup))
  }
  func testExclusionsAndBackupOverwriteBlocked() throws {
    let source = try fixture()
    let backup = root.appendingPathComponent("Backup.xcarchive")
    try ArchiveTransfer.createBackup(source: source, destination: backup)
    XCTAssertThrowsError(try ArchiveTransfer.createBackup(source: source, destination: backup))
    let plan = try ArchiveTransfer.prepare(archive: XcodeArchives.read(source), backup: backup)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    XCTAssertThrowsError(
      try store.moveArchive(plan, pinned: [], retained: [], protectedPaths: [source.path]))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
  func directPlan() throws -> (ArchiveTransferPlan, QuarantineStore) {
    let source = try fixture()
    let backup = root.appendingPathComponent("Backup.xcarchive")
    try ArchiveTransfer.createBackup(source: source, destination: backup)
    return (
      try ArchiveTransfer.prepare(archive: XcodeArchives.read(source), backup: backup),
      try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    )
  }
  func testDirectDeletionRetainsVerifiedBackupWithoutQuarantine() throws {
    let (plan, store) = try directPlan()
    try store.deleteArchive(plan, pinned: [], retained: [], idle: {})
    XCTAssertFalse(FileManager.default.fileExists(atPath: plan.source.path))
    XCTAssertTrue(
      ArchiveTransfer.sameContents(
        plan.manifest, try DirectoryManifest.capture(XCTUnwrap(plan.backup))))
    XCTAssertTrue(store.entries().isEmpty)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.root.path).isEmpty)
  }
  func testDirectDeletionProtectsRetentionExclusionsActivityAndCancellation() throws {
    let (plan, store) = try directPlan()
    XCTAssertThrowsError(
      try store.deleteArchive(plan, pinned: [plan.source.path], retained: [], idle: {}))
    XCTAssertThrowsError(
      try store.deleteArchive(plan, pinned: [], retained: [plan.source.path], idle: {}))
    XCTAssertThrowsError(
      try store.deleteArchive(
        plan, pinned: [], retained: [],
        protectedPaths: [plan.source.appendingPathComponent("Info.plist").path], idle: {}))
    XCTAssertThrowsError(
      try store.deleteArchive(
        plan, pinned: [], retained: [], idle: { throw CleanerError.message("Active build") }))
    var checks = 0
    XCTAssertThrowsError(
      try store.deleteArchive(
        plan, pinned: [], retained: [],
        idle: {
          checks += 1
          if checks == 2 { throw CleanerError.message("Build started during validation") }
        }))
    XCTAssertEqual(checks, 2)
    let token = Cancellation()
    token.cancel()
    XCTAssertThrowsError(
      try store.deleteArchive(plan, pinned: [], retained: [], cancellation: token, idle: {}))
    XCTAssertEqual(try DirectoryManifest.capture(plan.source), plan.manifest)
  }
  func testDirectDeletionRejectsChangedSource() throws {
    let (plan, store) = try directPlan()
    try Data("new data".utf8).write(to: plan.source.appendingPathComponent("added"))
    XCTAssertThrowsError(try store.deleteArchive(plan, pinned: [], retained: [], idle: {}))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: plan.source.appendingPathComponent("added").path))
  }
  func testDirectDeletionRejectsChangedOrMissingBackup() throws {
    let (plan, store) = try directPlan()
    try Data("changed".utf8).write(to: XCTUnwrap(plan.backup).appendingPathComponent("Info.plist"))
    XCTAssertThrowsError(try store.deleteArchive(plan, pinned: [], retained: [], idle: {}))
    try FileManager.default.removeItem(at: XCTUnwrap(plan.backup))
    XCTAssertThrowsError(try store.deleteArchive(plan, pinned: [], retained: [], idle: {}))
    XCTAssertEqual(try DirectoryManifest.capture(plan.source), plan.manifest)
  }
  func testDirectDeletionRejectsProjectAndQuarantineBackup() throws {
    let (plan, store) = try directPlan()
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(".git"), withIntermediateDirectories: false)
    XCTAssertThrowsError(try store.deleteArchive(plan, pinned: [], retained: [], idle: {}))
    try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
    let unsafeStore = try QuarantineStore(root: root)
    XCTAssertThrowsError(try unsafeStore.deleteArchive(plan, pinned: [], retained: [], idle: {}))
    XCTAssertEqual(try DirectoryManifest.capture(plan.source), plan.manifest)
  }

  func testDirectDeletionRejectsBackupInsideQuarantine() throws {
    let (plan, store) = try directPlan()
    let unsafeBackup = store.root.appendingPathComponent("Stored.xcarchive")
    try ArchiveTransfer.createBackup(source: plan.source, destination: unsafeBackup)
    let unsafePlan = try ArchiveTransfer.prepare(
      archive: XcodeArchives.read(plan.source), backup: unsafeBackup)
    XCTAssertThrowsError(try store.deleteArchive(unsafePlan, pinned: [], retained: [], idle: {}))
    XCTAssertEqual(try DirectoryManifest.capture(plan.source), plan.manifest)
  }
  func testDirectDeletionRejectsSourceReplacedBySymlink() throws {
    let (plan, store) = try directPlan()
    let preserved = root.appendingPathComponent("Preserved.xcarchive")
    try FileManager.default.moveItem(at: plan.source, to: preserved)
    try FileManager.default.createSymbolicLink(at: plan.source, withDestinationURL: preserved)
    XCTAssertThrowsError(try store.deleteArchive(plan, pinned: [], retained: [], idle: {}))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: preserved.appendingPathComponent("Info.plist").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(plan.backup).path))
  }

  func testCleanupWithoutBackupOrSymbols() throws {
    let source = try fixture()
    try FileManager.default.removeItem(at: source.appendingPathComponent("dSYMs"))
    try age(source)
    let plan = try ArchiveTransfer.prepare(archive: XcodeArchives.read(source))
    XCTAssertNil(plan.backup)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    try store.deleteArchive(plan, pinned: [], retained: [], idle: {})
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertTrue(store.entries().isEmpty)
  }
  func testQuarantineWithoutBackupCanRestoreAndErase() throws {
    let source = try fixture()
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    let plan = try ArchiveTransfer.prepare(archive: XcodeArchives.read(source))
    let entry = try store.moveArchive(plan, pinned: [], retained: [])
    XCTAssertNil(entry.archiveBackup)
    XCTAssertTrue(entry.isArchive)
    XCTAssertTrue(try XCTUnwrap(store.entries().first).isArchive)
    try store.restore(entry)
    XCTAssertEqual(try DirectoryManifest.capture(source), plan.manifest)
    let newPlan = try ArchiveTransfer.prepare(archive: XcodeArchives.read(source))
    let second = try store.moveArchive(newPlan, pinned: [], retained: [])
    try store.erase(second)
    XCTAssertEqual(store.entries().first(where: { $0.id == second.id })?.state, "deleted")
  }
  func testLegacyArchiveEntryStillClassified() throws {
    let entry = QuarantineEntry(
      id: UUID(), original: "/archive", bytes: 1, date: Date(), hash: "hash",
      archiveBackup: "/backup", state: "quarantined")
    let decoded = try JSONDecoder().decode(QuarantineEntry.self, from: JSONEncoder().encode(entry))
    XCTAssertNil(decoded.archive)
    XCTAssertTrue(decoded.isArchive)
  }
  func testArchiveFromOneHourAgoEligibleButRecentWritesProtected() throws {
    let source = try fixture()
    let paths =
      [source]
      + (FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil)?.allObjects
        as? [URL] ?? [])
    for path in paths {
      try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: path.path)
    }
    XCTAssertNoThrow(try ArchiveTransfer.prepare(archive: XcodeArchives.read(source)))
    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: source.path)
    XCTAssertThrowsError(try ArchiveTransfer.prepare(archive: XcodeArchives.read(source)))
  }

}
