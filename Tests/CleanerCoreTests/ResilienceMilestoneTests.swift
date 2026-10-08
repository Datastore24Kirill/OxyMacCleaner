import XCTest
@testable import CleanerCore

final class ResilienceMilestoneTests: XCTestCase {
  func testRestoreRefusesDifferentOriginalVolumeButAllowsChosenAlternative() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("source"); try Data("safe".utf8).write(to: file)
    let store = try QuarantineStore(root: root.appendingPathComponent("q"))
    var entry = try store.move(FileRecord.read(file))
    XCTAssertNotNil(entry.originalVolumeUUID)
    entry.originalVolumeUUID = "unavailable-volume"
    XCTAssertThrowsError(try store.restore(entry))
    XCTAssertTrue(store.inspect(entry).payloadValid)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    let alternative = root.appendingPathComponent("alternative")
    try store.restore(entry, destination: alternative)
    XCTAssertEqual(try String(contentsOf: alternative), "safe")
  }
  func testEveryAgentExplainsItsImportBoundary() {
    XCTAssertEqual(Agents.catalog.filter { $0.nativeFormat != nil }.count, 9)
    for agent in Agents.catalog {
      XCTAssertTrue(agent.importLimitations(russian: true).contains("оригинал"))
      XCTAssertTrue(agent.importLimitations(russian: false).contains("original"))
    }
  }
  func fixture() throws -> URL {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/OxyResilienceQA-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
  }
  func testResumeAndPersistCompletedSubtreesWithoutDoubleCounting() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    for i in 0..<80 {
      let directory = root.appendingPathComponent("d\(i)"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for j in 0..<10 { try Data(repeating: 1, count: 5).write(to: directory.appendingPathComponent("f\(j)")) }
    }
    let token = Cancellation(); var count = 0
    let partial = Scanner.scan(roots: [root], excluded: [], cancellation: token, record: { _ in count += 1; if count == 253 { token.cancel() } })
    XCTAssertFalse(partial.complete); XCTAssertFalse(try XCTUnwrap(partial.checkpoint).completedDirectories.isEmpty)
    let store = ScanStore(url: root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".scan"))
    defer { try? FileManager.default.removeItem(at: store.url) }
    try store.save(SavedScan(roots: [root], volumeID: "test", report: partial, progress: ScanProgress()))
    let restored = try XCTUnwrap(store.load()).report
    let resumed = Scanner.scan(roots: [root], excluded: [], cancellation: Cancellation(), resuming: restored)
    XCTAssertTrue(resumed.complete); XCTAssertEqual(resumed.files.count, 800); XCTAssertEqual(resumed.total, 4000)
    XCTAssertEqual(resumed.folders[root.path], 4000)
    XCTAssertEqual(Set(resumed.files.map(\.path)).count, 800)
    let rejected = Scanner.scan(roots: [root], excluded: [root.path], cancellation: Cancellation(), resuming: partial)
    XCTAssertFalse(rejected.complete); XCTAssertEqual(rejected.files.count, partial.files.count)
    XCTAssertTrue(rejected.issues.contains { $0.contains("checkpoint") })
  }
  func testOfflinePayloadAndCancelledRestoreRetainJournalAndData() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("file"); try Data("original".utf8).write(to: source)
    let store = try QuarantineStore(root: root.appendingPathComponent("q"))
    let entry = try store.move(FileRecord.read(source))
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try store.restore(entry, cancellation: token))
    XCTAssertTrue(store.inspect(entry).payloadValid)
    let payload = root.appendingPathComponent("q/\(entry.id.uuidString)/payload")
    let offline = root.appendingPathComponent("offline"); try FileManager.default.moveItem(at: payload, to: offline)
    XCTAssertThrowsError(try store.restore(entry))
    XCTAssertEqual(store.entries().first?.state, "quarantined")
    XCTAssertEqual(try String(contentsOf: offline), "original")
    try FileManager.default.moveItem(at: offline, to: payload)
    try store.restore(entry); XCTAssertEqual(try String(contentsOf: source), "original")
  }
  func testCrashJournalOrdersFilesBeforeCompletedFoldersAndDropsTornTail() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let files = root.appendingPathComponent("files"); try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    let file = files.appendingPathComponent("a"); try Data("123".utf8).write(to: file)
    let journal = try ScanJournal(url: root.appendingPathComponent("journal"), roots: [files], volumeID: "test", excluded: [])
    try journal.append(FileRecord.read(file)); try journal.appendIssue("fixture permission denied"); try journal.completeDirectory(files.path); try journal.flush()
    let recovered = try XCTUnwrap(ScanJournal.recover(journal.url))
    XCTAssertEqual(recovered.report.files.count, 1)
    XCTAssertTrue(recovered.report.issues.contains("fixture permission denied"))
    XCTAssertEqual(recovered.report.checkpoint?.completedDirectories, [files.path])
    XCTAssertTrue(Scanner.canResume(recovered.report, roots: [files], excluded: []))
    let resumed = Scanner.scan(roots: [files], excluded: [], cancellation: Cancellation(), resuming: recovered.report)
    XCTAssertTrue(resumed.complete); XCTAssertEqual(resumed.total, 3)
    let complete = try Data(contentsOf: journal.url)
    let lines = complete.split(separator: 10)
    var torn = Data(); for line in lines.dropLast() { torn.append(contentsOf: line); torn.append(10) }; torn.append(contentsOf: lines.last!.prefix(12))
    let partialURL = root.appendingPathComponent("torn"); try torn.write(to: partialURL)
    let partial = try XCTUnwrap(ScanJournal.recover(partialURL))
    XCTAssertEqual(partial.report.files.count, 1); XCTAssertEqual(partial.report.checkpoint?.completedDirectories.count, 0)
    let retry = Scanner.scan(roots: [files], excluded: [], cancellation: Cancellation(), resuming: partial.report)
    XCTAssertEqual(retry.files.count, 1); XCTAssertEqual(retry.total, 3)
  }
  func testCopySpaceAndActionableErrors() throws {
    XCTAssertThrowsError(try QuarantineStore.validateCopySpace(required: 100, available: 0))
    XCTAssertThrowsError(try QuarantineStore.validateCopySpace(required: Int64.max, available: Int64.max))
    XCTAssertThrowsError(try QuarantineStore.validateCopySpace(required: 100, available: nil))
    XCTAssertNoThrow(try QuarantineStore.validateCopySpace(required: 100, available: 20_000_000))
    XCTAssertTrue(ErrorPresentation.message("Destination changed", russian: true).contains("имя"))
    XCTAssertTrue(ErrorPresentation.message("No space left", russian: false).contains("Keep the source"))
    XCTAssertTrue(ErrorPresentation.message("cancelled", russian: true).contains("остановлена"))
  }
  func testOpenCodeExportPreservesPartsAndRejectsMixedSession() throws {
    let text = #"{"info":{"id":"s1","title":"test"},"unknown":"retained","messages":[{"info":{"id":"m1","sessionID":"s1","role":"user"},"parts":[{"type":"text","sessionID":"s1","messageID":"m1","text":"Do not delete"},{"type":"future","sessionID":"s1","messageID":"m1","extra":123}]}]}"#
    let result = try JSONHistory.parse(text, agent: "opencode", filename: "export.json")
    XCTAssertEqual(result.messages, 1); XCTAssertTrue(result.numbered.contains("future")); XCTAssertTrue(result.numbered.contains("retained"))
    XCTAssertThrowsError(try JSONHistory.parse(text.replacingOccurrences(of: #""sessionID":"s1""#, with: #""sessionID":"s2""#), agent: "opencode", filename: "export.json"))
  }
}
