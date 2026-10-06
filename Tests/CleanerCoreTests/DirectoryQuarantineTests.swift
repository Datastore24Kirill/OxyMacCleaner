import XCTest

@testable import CleanerCore

final class DirectoryQuarantineTests: XCTestCase {
  var temp: URL!
  var source: URL!
  var store: QuarantineStore!
  override func setUpWithError() throws {
    temp = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Downloads/OxyDirectoryTests-" + UUID().uuidString)
    source = temp.appendingPathComponent("source")
    try FileManager.default.createDirectory(
      at: source.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
    try Data("payload".utf8).write(to: source.appendingPathComponent("nested/file.txt"))
    store = try QuarantineStore(root: temp.appendingPathComponent("quarantine"))
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: temp) }
  func move() throws -> QuarantineEntry {
    try store.moveDirectory(source, expected: DirectoryManifest.capture(source))
  }
  func testRoundTripPreservesNestedAndEmptyFolders() throws {
    let manifest = try DirectoryManifest.capture(source)
    let entry = try move()
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertEqual(entry.kind, "directory")
    try store.restore(entry)
    XCTAssertEqual(try DirectoryManifest.capture(source), manifest)
  }
  func testChangedOrProtectedFolderIsRejected() throws {
    let before = try DirectoryManifest.capture(source)
    try Data("new".utf8).write(to: source.appendingPathComponent("added.txt"))
    XCTAssertThrowsError(try store.moveDirectory(source, expected: before))
    try Data("secret".utf8).write(to: source.appendingPathComponent(".env"))
    XCTAssertThrowsError(try move())
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
  func testSymlinkAndGitProtection() throws {
    try FileManager.default.createSymbolicLink(
      at: source.appendingPathComponent("link"), withDestinationURL: temp)
    XCTAssertThrowsError(try DirectoryManifest.capture(source))
    try FileManager.default.removeItem(at: source.appendingPathComponent("link"))
    try FileManager.default.createDirectory(
      at: source.appendingPathComponent(".git"), withIntermediateDirectories: false)
    XCTAssertThrowsError(try move())
  }
  func testRestoreConflictRetainsPayload() throws {
    let entry = try move()
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
    XCTAssertThrowsError(try store.restore(entry))
    try store.restore(entry, destination: temp.appendingPathComponent("restored"))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: temp.appendingPathComponent("restored/nested/file.txt").path))
  }
  func testCorruptPayloadCannotRestoreOrErase() throws {
    let entry = try move()
    let file = store.root.appendingPathComponent(entry.id.uuidString + "/payload/nested/file.txt")
    try Data("changed".utf8).write(to: file)
    XCTAssertThrowsError(try store.restore(entry))
    XCTAssertThrowsError(try store.erase(entry))
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
  }
  func testRecoveryAfterRenameBeforeJournalCommit() throws {
    var entry = try move()
    entry.state = "prepared"
    try JSONEncoder().encode(entry).write(
      to: store.root.appendingPathComponent(entry.id.uuidString + "/entry.json"))
    try store.recover()
    XCTAssertEqual(store.entries().first?.state, "quarantined")
    try store.restore(try XCTUnwrap(store.entries().first))
  }
  func testRecoveryAfterRestoreBeforeJournalCommit() throws {
    var entry = try move()
    try store.restore(entry)
    entry.state = "restoring"
    entry.restoreDestination = source.path
    try JSONEncoder().encode(entry).write(
      to: store.root.appendingPathComponent(entry.id.uuidString + "/entry.json"))
    try store.recover()
    XCTAssertEqual(store.entries().first?.state, "restored")
  }
  func testHardLinksAndExcludedDescendantsAreRejected() throws {
    try FileManager.default.linkItem(
      at: source.appendingPathComponent("nested/file.txt"),
      to: source.appendingPathComponent("copy.txt"))
    XCTAssertThrowsError(try DirectoryManifest.capture(source))
    try FileManager.default.removeItem(at: source.appendingPathComponent("copy.txt"))
    let manifest = try DirectoryManifest.capture(source)
    XCTAssertThrowsError(
      try store.moveDirectory(
        source, expected: manifest, protectedPaths: [source.appendingPathComponent("nested").path]))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
  func testCancelledBeforeMoveAndPermanentEraseFixture() throws {
    let manifest = try DirectoryManifest.capture(source)
    let token = Cancellation()
    token.cancel()
    XCTAssertThrowsError(try store.moveDirectory(source, expected: manifest, cancellation: token))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    let entry = try move()
    try store.erase(entry)
    XCTAssertEqual(store.entries().first?.state, "deleted")
  }
}
