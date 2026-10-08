import XCTest
@testable import CleanerCore

final class ReviewHardeningTests: XCTestCase {
  func testUnlabelledCancellationRestrictionsAndNextStepsSurviveModelOmission() throws {
    let source = "[L1] Initial plan\n[L2] Отменяю удаление, вместо него только проверка.\n[L3] Не удалять оригинал.\n[L4] Следующий шаг: проверить восстановление.\n[L5] Cancel my earlier request.\n[L6] Must not upload histories.\n[L7] Next step: inspect backup."
    let result = try ContextSafety.groundedExcerpt("[L1]", source: source)
    for line in source.components(separatedBy: "\n") { XCTAssertTrue(result.contains(line), line) }
  }
  func testFragmentPresenceRequiresTextNotJustCitationAndAccountsForRedaction() throws {
    let transcript = Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: "Пользователь: token=SyntheticSecret1234 не переносить\nОтменяю удаление", digest: "fixture")
    let findings = try TranscriptReview(transcript).reviewIndex()
    XCTAssertEqual(findings.items.count, 2)
    XCTAssertFalse(findings.items[1].fragmentPresent(in: "[L2] Всё готово"))
    XCTAssertTrue(findings.items[0].fragmentPresent(in: "> " + ContextSafety.redact(findings.items[0].excerpt)))
    XCTAssertFalse(findings.items[1].fragmentPresent(in: "> [L1] unrelated"))
  }
  func testOperationSummarySeparatesFailuresFromUnstartedItems() {
    XCTAssertEqual(CleanupSummary(selected: 10, completed: 3, attempted: 5).text(russian: true), "Выполнено: 3/10 · не выполнено/пропущено: 2 · не начато: 5")
    XCTAssertEqual(CleanupSummary(selected: 2, completed: 2, attempted: 2).text(russian: false), "Completed: 2/2 · not completed/skipped: 0 · not started: 0")
  }
}
