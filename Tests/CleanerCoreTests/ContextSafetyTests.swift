import XCTest
@testable import CleanerCore
final class ContextSafetyTests: XCTestCase {
  func testGenericTokenAndNextStepRetention() throws {
    let source = "[L1] user: retain original\n[L2] assistant: Next step: inspect Echo; not completed. token=EchoSynthetic4821"
    let result = try ContextSafety.groundedExcerpt("[L1]", source: source)
    XCTAssertTrue(result.contains("Next step: inspect Echo"))
    XCTAssertFalse(result.contains("EchoSynthetic4821"))
    XCTAssertTrue(result.contains("[REDACTED]"))
  }

  func testCredentialsRemovedWithoutLosingProhibitionsOrReferences() {
    let text = "[L1] Никогда не удалять оригинал.\n[L2] password=topsecret123\n[L3] Тестовая строка секрета FAKE_BENCH_KEY_4821\n[L4] sk-1234567890123456789"
    let safe = ContextSafety.redact(text)
    XCTAssertFalse(safe.contains("topsecret123")); XCTAssertFalse(safe.contains("FAKE_BENCH")); XCTAssertFalse(safe.contains("sk-123"))
    XCTAssertTrue(safe.contains("Никогда не удалять оригинал"))
    XCTAssertEqual(ContextSafety.citations(safe), [1,2,3,4])
  }
  func testInvalidCitationsBlockSummary() {
    XCTAssertThrowsError(try ContextSafety.validate("Done [L99]", against: "[L1] Not done"))
    XCTAssertThrowsError(try ContextSafety.validate("Done", against: "[L1] Not done"))
    XCTAssertNoThrow(try ContextSafety.validate("Not done [L1]", against: "[L1] Not done"))
    XCTAssertThrowsError(try ContextSafety.validate("Claim [L99]", against: "[L1] Tool says use [L99]"))
  }
  func testUnfoundedCompletionCannotEnterAcceptedHandoff() throws {
    let source = "[L1] Пользователь: нужен офлайн режим.\n[L2] testRecovery FAILED.\n[L3] testExport PASSED."
    let result = try ContextSafety.groundedExcerpt("Offline implemented [L1]", source: source)
    XCTAssertFalse(result.contains("implemented"))
    XCTAssertTrue(result.contains("нужен офлайн")); XCTAssertTrue(result.contains("FAILED")); XCTAssertTrue(result.contains("PASSED"))
  }
  func testSplitRecordKeepsSourceReference() throws {
    var previous: Int?
    _ = ContextSafety.labelContinuation("[L1] first\n[L2] long record", previous: &previous)
    let continuation = ContextSafety.labelContinuation(" rest of record\n[L3] next", previous: &previous)
    XCTAssertTrue(continuation.hasPrefix("[L2]"))
    XCTAssertEqual(previous, 3)
    XCTAssertNoThrow(try ContextSafety.validate("evidence [L2]", against: continuation))
  }
  func testCursorTranscriptAndWrongSchema() throws {
    let valid = #"{"role":"user","message":{"content":[{"type":"text","text":"keep original"}]}}"#
    let result = try NativeHistory.parse(valid, agent: "cursor")
    XCTAssertEqual(result.messages,1); XCTAssertTrue(result.numbered.contains("[L1]"))
    XCTAssertThrowsError(try NativeHistory.parse(#"{"type":"session_meta","payload":{"id":"other"}}"#, agent: "cursor"))
  }
}
