import XCTest
@testable import CleanerCore

final class ArchivePaginationTests: XCTestCase {
  func testRetentionOrPinsShrinkingTwentyResultsToTenReturnsToFirstPage() {
    let inventory = (0..<21).map { index in
      XcodeArchive(path: "/Archives/\(index).xcarchive", name: "App", bundleID: "test.app",
        team: "TEAM", version: "1", build: String(index), created: Date(timeIntervalSince1970: Double(index)),
        bytes: 100, dsymCount: 1, issues: [])
    }
    func beyondLimit(keep: Int, pinned: Set<String>) -> [String] {
      let decisions = ArchiveRetention.decisions(inventory, keep: keep, pinned: pinned)
      return inventory.filter { decisions[$0.path] == .review }.map(\.path)
    }
    let before = beyondLimit(keep: 1, pinned: [])
    XCTAssertEqual(before.count, 20)
    let afterRetention = beyondLimit(keep: 11, pinned: [])
    let afterPinning = beyondLimit(keep: 1, pinned: Set(before.suffix(10)))
    for filtered in [afterRetention, afterPinning] {
      // The underlying inventory stays at 21: watching its count misses both changes.
      XCTAssertEqual(inventory.count, 21)
      XCTAssertEqual(filtered.count, 10)
      var pagination = ArchivePagination()
      pagination.update(paths: before)
      pagination.page = 1
      XCTAssertEqual(Array(before.dropFirst(pagination.page * 10).prefix(10)), Array(before.suffix(10)))
      pagination.update(paths: filtered)
      XCTAssertEqual(pagination.page, 0)
      XCTAssertEqual(Array(filtered.dropFirst(pagination.page * 10).prefix(10)), filtered)
    }
  }

  func testUnchangedResultsPreserveNextAndPreviousNavigation() {
    let paths = (0..<30).map { "/Archives/\($0).xcarchive" }
    var pagination = ArchivePagination()
    pagination.update(paths: paths)
    pagination.page += 1
    pagination.update(paths: paths)
    XCTAssertEqual(pagination.page, 1)
    pagination.page += 1
    pagination.update(paths: paths)
    XCTAssertEqual(pagination.page, 2)
    pagination.page -= 1
    pagination.update(paths: paths)
    XCTAssertEqual(pagination.page, 1)
  }

  func testSameCountMembershipChangeAndEmptyResultsResetPage() {
    let paths = (0..<20).map { "/Archives/\($0).xcarchive" }
    var pagination = ArchivePagination()
    pagination.update(paths: paths)
    pagination.page = 1
    pagination.update(paths: Array(paths.dropFirst()) + ["/Archives/new.xcarchive"])
    XCTAssertEqual(pagination.page, 0)
    pagination.page = 1
    pagination.update(paths: [])
    XCTAssertEqual(pagination.page, 0)
  }
}
