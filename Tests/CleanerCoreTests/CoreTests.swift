import XCTest

@testable import CleanerCore

final class CoreTests: XCTestCase {
  var temp: URL!
  override func setUpWithError() throws {
    temp = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Caches/OxyMacCleanerTests"
    ).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }
  func file(_ name: String, _ data: String) throws -> URL {
    let u = temp.appendingPathComponent(name)
    try Data(data.utf8).write(to: u)
    return u
  }
  func testScanDeduplicatesRootsAndSkipsSymlink() throws {
    let a = try file("a.txt", "hello")
    let link = temp.appendingPathComponent("loop")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: temp)
    let r = Scanner.scan(roots: [temp, temp], excluded: [], cancellation: Cancellation())
    XCTAssertTrue(r.complete)
    XCTAssertEqual(r.files.map(\.path), [a.path])
    XCTAssertEqual(r.total, 5)
  }
  func testCancellationAndExclusions() throws {
    _ = try file("a.txt", "hello")
    let c = Cancellation()
    c.cancel()
    XCTAssertFalse(Scanner.scan(roots: [temp], excluded: [], cancellation: c).complete)
    XCTAssertTrue(
      Scanner.scan(roots: [temp], excluded: [temp.path], cancellation: Cancellation()).files.isEmpty
    )
  }
  func testDuplicatesNotJustSize() throws {
    _ = try file("a.txt", "hello")
    _ = try file("b.txt", "hello")
    _ = try file("c.txt", "world")
    let r = Scanner.scan(roots: [temp], excluded: [], cancellation: Cancellation())
    let groups = try Scanner.duplicates(r.files, cancellation: Cancellation())
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups[0].count, 2)
  }
  func testChangedFileRejected() throws {
    let u = try file("a.txt", "before")
    let record = try FileRecord.read(u)
    try Data("after changed".utf8).write(to: u)
    XCTAssertThrowsError(try record.validate())
  }
  func testHardLinksAreNotDuplicates() throws {
    let u = try file("a.txt", "hello")
    try FileManager.default.linkItem(at: u, to: temp.appendingPathComponent("b.txt"))
    let r = Scanner.scan(roots: [temp], excluded: [], cancellation: Cancellation())
    XCTAssertEqual(r.files.count, 1)
    XCTAssertTrue(try Scanner.duplicates(r.files, cancellation: Cancellation()).isEmpty)
  }
  func testProtectionRules() {
    XCTAssertTrue(QuarantineStore.protected("/Users/test/.ssh/id_rsa"))
    XCTAssertTrue(QuarantineStore.protected("/Users/test/project/.env.local"))
    XCTAssertTrue(QuarantineStore.protected("/Users/test/source.swift"))
    XCTAssertTrue(QuarantineStore.protected("/System/a.txt"))
    XCTAssertTrue(QuarantineStore.protected("/Users/test/App.app/Contents/Info.plist"))
    XCTAssertTrue(QuarantineStore.protected("/Users/test/.codex/sessions/a.jsonl"))
    XCTAssertFalse(QuarantineStore.protected("/Users/test/Downloads/a.zip"))
  }
  func testQuarantineRoundTripAndConflict() throws {
    let u = try file("a.txt", "keep this")
    let q = try QuarantineStore(root: temp.appendingPathComponent("q"))
    let entry = try q.move(FileRecord.read(u))
    XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))
    XCTAssertEqual(q.entries().first?.state, "quarantined")
    try Data("conflict".utf8).write(to: u)
    XCTAssertThrowsError(try q.restore(entry))
    XCTAssertEqual(try String(contentsOf: u), "conflict")
    let restored = temp.appendingPathComponent("restored.txt")
    try q.restore(entry, destination: restored)
    XCTAssertEqual(try String(contentsOf: restored), "keep this")
    XCTAssertEqual(q.entries().first?.state, "restored")
  }
  func testCorruptQuarantineIsNotRestored() throws {
    let u = try file("a.txt", "keep this")
    let q = try QuarantineStore(root: temp.appendingPathComponent("q"))
    let e = try q.move(FileRecord.read(u))
    try Data("corrupt".utf8).write(
      to: q.root.appendingPathComponent(e.id.uuidString).appendingPathComponent("payload"))
    XCTAssertThrowsError(try q.restore(e))
    XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))
  }
  func testPermanentDeletionAndPreparedJournalRecovery() throws {
    let u = try file("a.txt", "delete test fixture")
    let q = try QuarantineStore(root: temp.appendingPathComponent("q"))
    let e = try q.move(FileRecord.read(u))
    try q.erase(e)
    XCTAssertEqual(q.entries().first?.state, "deleted")
    XCTAssertThrowsError(try q.restore(e))
  }

  func testReminderEveryFiveDaysAndEmpty() {
    let now = Date()
    let e = QuarantineEntry(
      id: UUID(), original: "x", bytes: 2, date: now.addingTimeInterval(-6 * 86400), hash: "",
      state: "quarantined")
    XCTAssertTrue(QuarantineStore.reminderDue(entries: [e], last: nil, now: now))
    XCTAssertFalse(
      QuarantineStore.reminderDue(entries: [e], last: now.addingTimeInterval(-4 * 86400), now: now))
    XCTAssertFalse(QuarantineStore.reminderDue(entries: [], last: nil, now: now))
  }
  func testTranscriptBackupAndChunkCoverage() throws {
    let u = try file("session.md", "goal\nзадача\nnext")
    let t = try Transcript.load(u, agent: "codex")
    let backup = try t.backup(in: temp.appendingPathComponent("backups"))
    XCTAssertEqual(try Scanner.hash(backup), t.digest)
    XCTAssertEqual(ContextPlan.chunks(t.numbered, maxCharacters: 7).joined(), t.numbered)
    XCTAssertTrue(t.numbered.contains("[L2] задача"))
  }
  func testRejectDatabaseImport() throws {
    let u = try file("data.db", "not history")
    XCTAssertThrowsError(try Transcript.load(u, agent: "cursor"))
  }
}
