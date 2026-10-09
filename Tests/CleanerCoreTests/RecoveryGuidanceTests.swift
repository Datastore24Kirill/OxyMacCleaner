import XCTest
@testable import CleanerCore
final class RecoveryGuidanceTests: XCTestCase {
  func testGuidanceKeepsExactEvidenceAndOffersOnlyNavigation() {
    let cases: [(String, RecoveryGuidance.Destination)] = [
      ("Permission denied", .settings), ("Operation not permitted", .settings),
      ("Connection refused", .engine), ("model qwen not found", .engine),
      ("Destination changed", .history), ("Integrity failed", .history),
      ("Unsupported history format", .agents), ("Select UTF-8 JSONL export", .agents),
      ("Unknown code 912", .history), ("Permission denied\nmodel not found", .history)
    ]
    for (raw, expected) in cases {
      for russian in [true, false] {
        let result = RecoveryGuidance(raw, russian: russian)
        XCTAssertEqual(result.details, raw)
        XCTAssertEqual(result.destination, expected)
        XCTAssertFalse(result.summary.isEmpty)
        XCTAssertFalse(result.summary.contains("Details:"))
        XCTAssertFalse(result.summary.contains("Подробности:"))
      }
    }
  }
  func testUnknownLongFailureHasShortGuidanceWithoutLosingDetails() {
    let raw = String(repeating: "Unexpected diagnostic 912; ", count: 1000)
    let result = RecoveryGuidance(raw, russian: true)
    XCTAssertLessThan(result.summary.count, 320)
    XCTAssertEqual(result.details, raw)
    XCTAssertTrue(result.summary.contains("Автоматического повтора не будет"))
  }
  func testExistingSpecificRussianExplanationIsRetained() {
    let raw = "Диск, папка или исключения изменились. Запустите новый скан; прежний результат сохранён."
    XCTAssertEqual(RecoveryGuidance(raw, russian: true).summary, raw)
  }
}
