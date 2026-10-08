import XCTest
@testable import CleanerCore
final class CursorTurnTests: XCTestCase {
  func testTurnMetadataPreservedWithoutBecomingMessageOrTestSuccess() throws {
    let message = #"{"role":"user","message":{"content":[{"text":"Inspect failure"}]}}"#
    let ended = #"{"type":"turn_ended","status":"error","error":{"message":"synthetic failure"},"extra":"retained"}"#
    let value = try NativeHistory.parse(message + "\n" + ended, agent: "cursor")
    XCTAssertEqual(value.messages, 1); XCTAssertEqual(value.retainedRecords, 1)
    XCTAssertTrue(value.numbered.contains("[L2] RECORD (turn_ended): " + ended))
    XCTAssertFalse(value.numbered.contains("PASSED"))
    XCTAssertThrowsError(try NativeHistory.parse(ended, agent: "cursor"))
    XCTAssertThrowsError(try NativeHistory.parse(message + "\n" + #"{"type":"turn_ended","status":true}"#, agent: "cursor"))
    XCTAssertThrowsError(try NativeHistory.parse(message + "\n" + #"{"type":"turn_ended","status":"success","role":"user"}"#, agent: "cursor"))
  }
}
