import XCTest
@testable import CleanerCore

final class NativeHistoryTests: XCTestCase {
  let codex = """
    {"type":"session_meta","payload":{"id":"one"}}
    {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Keep tests"}]}}
    {"type":"response_item","payload":{"type":"function_call_output","output":"failed"}}
    {"type":"future_event","payload":{"important":"preserve me"}}
    """
  let claude = """
    {"type":"user","sessionId":"one","message":{"role":"user","content":"goal"}}
    {"type":"assistant","sessionId":"one","parentUuid":"branch","message":{"role":"assistant","content":[{"type":"tool_use","name":"test","input":{}}]}}
    """
  func testCodexRetainsEveryRecordAndSourceLine() throws {
    let result = try NativeHistory.parse(codex, agent: "codex")
    XCTAssertEqual(result.messages, 1)
    XCTAssertEqual(result.retainedRecords, 3)
    for line in codex.components(separatedBy: "\n") { XCTAssertTrue(result.numbered.contains(line)) }
    XCTAssertTrue(result.numbered.contains("[L4] RECORD (future_event)"))
  }
  func testClaudeRetainsBranchAndTools() throws {
    let result = try NativeHistory.parse(claude, agent: "claude")
    XCTAssertEqual(result.messages, 2)
    XCTAssertTrue(result.numbered.contains("parentUuid"))
    XCTAssertTrue(result.numbered.contains("tool_use"))
  }
  func testWrongAgentMixedSessionAndMalformedInputRejected() throws {
    XCTAssertThrowsError(try NativeHistory.parse(codex, agent: "claude"))
    XCTAssertThrowsError(try NativeHistory.parse(claude, agent: "codex"))
    XCTAssertThrowsError(try NativeHistory.parse(codex, agent: "cursor"))
    XCTAssertThrowsError(try NativeHistory.parse(codex + "\n{", agent: "codex"))
    XCTAssertThrowsError(try NativeHistory.parse(claude + "\n{\"sessionId\":\"other\"}", agent: "claude"))
    XCTAssertThrowsError(try NativeHistory.parse("{}", agent: "codex"))
  }
  func testBackupMatchesOriginalAfterSourceChanges() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("session.jsonl")
    try Data(codex.utf8).write(to: source)
    let transcript = try Transcript.loadNative(source, agent: "codex")
    try Data("new live data".utf8).write(to: source)
    let backup = try transcript.backup(in: root.appendingPathComponent("backup"))
    XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), codex)
    XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new live data")
    XCTAssertTrue(transcript.numbered.contains("MESSAGE (user)"))
  }
  func testBlankLinesPreserveLineReferences() throws {
    let result = try NativeHistory.parse("\n" + codex, agent: "codex")
    XCTAssertTrue(result.numbered.contains("[L3] MESSAGE"))
  }
}
