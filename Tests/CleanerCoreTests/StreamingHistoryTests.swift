import XCTest
@testable import CleanerCore
final class StreamingHistoryTests: XCTestCase {
  var root: URL!
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
  func source(_ extra: String = "") throws -> URL {
    let url = root.appendingPathComponent("history.jsonl")
    let text = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"one\"}}\n{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":\"Привет 🌍\"}}\n" + extra
    try Data(text.utf8).write(to: url)
    return url
  }
  func testStreamingMatchesParserAndBackupSurvivesSourceChange() throws {
    let url = try source("{\"type\":\"unknown\",\"value\":42}")
    let raw = try String(contentsOf: url, encoding: .utf8)
    let snapshot = try StreamingHistory.load(url, agent: "codex")
    let reader = try snapshot.chunks()
    var text = ""
    while let part = try reader.next() { XCTAssertLessThanOrEqual(part.count, 12000); text += part }
    XCTAssertEqual(text, try NativeHistory.parse(raw, agent: "codex").numbered + "\n")
    try Data("changed".utf8).write(to: url)
    let backup = try snapshot.backup(in: root.appendingPathComponent("backup"), cancellation: Cancellation())
    XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), raw)
  }
  func testLargeNativeImportUsesDiskAndReleasesTemporaryCopy() throws {
    let url = try source()
    let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd()
    let line = Data(("{\"type\":\"unknown\",\"value\":\"" + String(repeating: "x", count: 100_000) + "\"}\n").utf8)
    for _ in 0..<301 { try handle.write(contentsOf: line) }; try handle.close()
    var transcript: Transcript? = try Transcript.loadNative(url, agent: "codex")
    XCTAssertTrue(transcript!.text.isEmpty)
    XCTAssertEqual(transcript!.nativeHistory?.retainedRecords, 302)
    let directory = try XCTUnwrap(transcript!.streaming?.directory)
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    transcript = nil
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }
  func testCancellationAndChangingSourceRejected() throws {
    let url = try source()
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try StreamingHistory.load(url, agent: "codex", cancellation: token))
    XCTAssertThrowsError(try StreamingHistory.load(url, agent: "codex") { _, _ in
      try? Data("changed during copy".utf8).write(to: url)
    })
  }
  func testMalformedAndOversizedRecordRejected() throws {
    XCTAssertThrowsError(try StreamingHistory.load(source("{"), agent: "codex"))
    XCTAssertThrowsError(try StreamingHistory.load(source(String(repeating: "x", count: 8_388_609)), agent: "codex"))
  }
  func testMultibyteAcrossReadBoundaryAndFinalLine() throws {
    let text = String(repeating: "a", count: 65535) + "🌍終"
    let url = root.appendingPathComponent("text")
    try Data(text.utf8).write(to: url)
    let reader = try HistoryLineReader(url)
    XCTAssertEqual(try reader.next(), text)
    XCTAssertNil(try reader.next())
  }
}
