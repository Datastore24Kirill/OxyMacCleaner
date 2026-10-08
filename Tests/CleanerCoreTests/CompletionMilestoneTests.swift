import XCTest
@testable import CleanerCore

final class CompletionMilestoneTests: XCTestCase {
  func fixture() throws -> URL {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/OxyCompletionQA-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
  }
  func testDiscoverySkipsDependenciesLinksExclusionsAndReportsLimit() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    for path in ["app/Package.swift", "app/.git/config", "web/package.json", "web/node_modules/other/package.json", "excluded/Cargo.toml"] {
      let file = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try Data().write(to: file)
    }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("app"))
    let result = ProjectDiscovery.discover(root, exclusions: [root.appendingPathComponent("excluded").path])
    XCTAssertEqual(result.projects.map { $0.url.lastPathComponent }.sorted(), ["app", "web"])
    XCTAssertTrue(ProjectDiscovery.discover(root, limit: 1).incomplete)
    let token = Cancellation(); token.cancel(); XCTAssertTrue(ProjectDiscovery.discover(root, cancellation: token).incomplete)
  }
  func testFullReviewUnicodePaginationAndSearchBeyondFirstPage() throws {
    let text = String(repeating: "日本語 привет 👩‍💻\n", count: 12000) + "testRecovery FAILED\n"
    let transcript = Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: text, digest: "fixture")
    let reader = try TranscriptReview(transcript)
    var offset = 0; var joined = ""
    while offset < reader.total { let page = try reader.page(at: offset, limit: 101); XCTAssertGreaterThan(page.next, offset); joined += page.text; offset = page.next }
    XCTAssertEqual(joined, transcript.numbered)
    let found = try XCTUnwrap(reader.find("testRecovery FAILED")); XCTAssertGreaterThan(found, 64000)
    XCTAssertTrue(try reader.page(at: found).reviewLines.contains { $0.contains("FAILED") })
    let token = Cancellation(); token.cancel(); XCTAssertThrowsError(try reader.find("absent", cancellation: token))
  }
  func testReviewIndexFindsLaterChangesAndPreservesSourceOffsets() throws {
    let text = String(repeating: "Обычная строка 👩‍💻\n", count: 9000) + "Теперь вместо удаления оставляем копию\nTests passed\n"
    let reader = try TranscriptReview(Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: text, digest: "test"))
    let index = try reader.reviewIndex()
    XCTAssertEqual(index.matches, 2)
    XCTAssertEqual(index.shortenedRecords, 0)
    let first = try XCTUnwrap(index.items.first)
    XCTAssertGreaterThan(first.offset, 128_000)
    XCTAssertTrue(try reader.page(at: first.offset).text.hasPrefix("[L9001] Теперь вместо"))
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try reader.reviewIndex(cancellation: token))
  }
  func testReviewIndexBoundsResultsAndReportsLongRecordLimit() throws {
    let text = String(repeating: "Do not delete originals\n", count: 250) + String(repeating: "x", count: 200_000) + "\nOrdinary prose\n"
    let reader = try TranscriptReview(Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: text, digest: "test"))
    let index = try reader.reviewIndex()
    XCTAssertEqual(index.matches, 250)
    XCTAssertEqual(index.items.count, 200)
    XCTAssertEqual(index.shortenedRecords, 1)
  }
  func testSpaceAccountingAndNestedPaths() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a"); try Data(repeating: 0, count: 200).write(to: a)
    let b = root.appendingPathComponent("b"); try FileManager.default.linkItem(at: a, to: b)
    let value = SpaceEstimate(files: [try FileRecord.read(a), try FileRecord.read(b), try FileRecord.read(a)])
    XCTAssertEqual(value.count, 1); XCTAssertEqual(value.logical, 200); XCTAssertEqual(value.hardLinked, 1)
    XCTAssertEqual(SpaceEstimate.disjointPaths(["/a", "/a/b", "/ab", "/a"]), ["/a", "/ab"])
  }
  func testRecoveredDoubleCopyRemainsVisibleAndChangedDestinationBlocksTrash() throws {
    let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source"); try Data("original".utf8).write(to: source)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    var entry = try store.move(FileRecord.read(source))
    let destination = root.appendingPathComponent("restored"); try Data("original".utf8).write(to: destination)
    entry.state = "restoring"; entry.restoreDestination = destination.path; entry.restoreDigest = entry.hash
    try JSONEncoder().encode(entry).write(to: store.root.appendingPathComponent(entry.id.uuidString + "/entry.json"))
    try store.recover()
    let recovered = try XCTUnwrap(store.entries().first)
    XCTAssertEqual(recovered.state, "restored-copy")
    XCTAssertTrue(store.inspect(recovered).payloadValid); XCTAssertTrue(store.inspect(recovered).destinationValid)
    try Data("changed".utf8).write(to: destination)
    XCTAssertThrowsError(try store.trashRestoredCopy(recovered))
    XCTAssertTrue(store.inspect(recovered).payloadValid)
  }
  func testAiderPreservesLinesAndRejectsMergedSessions() throws {
    let text = "# aider chat started at 2026-10-08\n#### keep originals\nresponse\n> unknown log"
    let parsed = try AiderHistory.parse(text)
    XCTAssertTrue(parsed.numbered.contains("[L4] > unknown log"))
    XCTAssertThrowsError(try AiderHistory.parse(text + "\n" + text))
    XCTAssertThrowsError(try AiderHistory.parse("unrelated markdown"))
  }
}
