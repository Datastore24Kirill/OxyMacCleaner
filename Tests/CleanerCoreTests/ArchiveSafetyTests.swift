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
}
