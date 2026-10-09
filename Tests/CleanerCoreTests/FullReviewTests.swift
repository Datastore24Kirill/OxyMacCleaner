import XCTest
@testable import CleanerCore
final class FullReviewTests: XCTestCase {
  func testLateDecisionCanBeReachedWithoutDroppingMiddleSignals() throws {
    var lines = (0..<610).map { "User: requirement item \($0)" }
    lines[450] = "User: instead keep archive Aurora, never delete the original"
    let transcript = Transcript(source: URL(fileURLWithPath: "/synthetic.md"), agent: "test", text: lines.joined(separator: "\n"), digest: "fixture")
    let reader = try TranscriptReview(transcript)
    var cursor: Int?; var offsets = Set<Int>(); var foundLate = false; var count = 0
    repeat {
      let page = try reader.reviewIndex(after: cursor)
      XCTAssertEqual(page.matches, 610)
      XCTAssertEqual(page.skipped, count)
      XCTAssertLessThanOrEqual(page.items.count, 200)
      for item in page.items {
        XCTAssertTrue(offsets.insert(item.offset).inserted)
        XCTAssertTrue(try reader.page(at: item.offset).text.hasPrefix(item.excerpt))
        if item.excerpt.contains("instead keep archive") {
          XCTAssertTrue(item.signals.contains(.changedDecision)); XCTAssertTrue(item.signals.contains(.restriction)); foundLate = true
        }
      }
      count += page.items.count; cursor = page.nextOffset
    } while cursor != nil
    XCTAssertEqual(count, 610); XCTAssertTrue(foundLate)
  }
  func testCancelledReviewPageCannotReturnPartialSuccess() throws {
    let reader = try TranscriptReview(Transcript(source: URL(fileURLWithPath: "/test.md"), agent: "test", text: "User: goal", digest: "fixture"))
    let cancellation = Cancellation(); cancellation.cancel()
    XCTAssertThrowsError(try reader.reviewIndex(after: 0, cancellation: cancellation))
  }
}
