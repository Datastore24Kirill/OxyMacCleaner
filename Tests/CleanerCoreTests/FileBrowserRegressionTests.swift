import XCTest
@testable import CleanerCore

final class FileBrowserRegressionTests: XCTestCase {
  private let dockerPath = "/Users/test/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
  private let moviePath = "/Users/test/Downloads/movie.mp4"

  private func index() throws -> FileBrowserIndex {
    let files = [
      FileRecord(path: dockerPath, bytes: 1_000_000_000_000, allocated: 2_000_000_000,
                 modified: .distantPast, inode: 1, device: 1, links: 1),
      FileRecord(path: moviePath, bytes: 10_000_000_000, allocated: 10_000_000_000,
                 modified: .distantPast, inode: 2, device: 1, links: 1)
    ]
    return try FileBrowserIndex(files: files, excluded: [], quarantine: "/Users/test/quarantine",
                                downloads: "/Users/test/Downloads")
  }

  func testMixedSparseAndOrdinaryFilesHaveSeparateTotalsAndLogicalOrdering() throws {
    let index = try index()
    var query = FileBrowserIndex.Query()
    query.showProtected = true
    query.limit = 1
    let first = try index.filter(query)
    XCTAssertEqual(first.matches, 2)
    XCTAssertEqual(first.bytes, 1_010_000_000_000)
    XCTAssertEqual(first.allocatedBytes, 12_000_000_000)
    XCTAssertEqual(first.rows.map(\.file.path), [dockerPath])
    XCTAssertEqual(first.rows.first?.selectable, false)

    query.limit = 200
    let full = try index.filter(query)
    XCTAssertEqual(full.rows.map(\.file.path), [dockerPath, moviePath])
    XCTAssertEqual(full.rows.map(\.selectable), [false, true])
    XCTAssertEqual(full.bytes, first.bytes)
    XCTAssertEqual(full.allocatedBytes, first.allocatedBytes)

    // The prefetched second page must retain both independently computed totals.
    query.limit = 400
    let cached = try index.filter(query)
    XCTAssertEqual(cached.bytes, full.bytes)
    XCTAssertEqual(cached.allocatedBytes, full.allocatedBytes)
  }

  func testSizeThresholdUsesLogicalSizeWithoutMakingDockerDeletable() throws {
    let index = try index()
    var query = FileBrowserIndex.Query()
    query.showProtected = true
    query.minimumMB = 20_000
    let result = try index.filter(query)
    XCTAssertEqual(result.rows.map(\.file.path), [dockerPath])
    XCTAssertEqual(result.bytes, 1_000_000_000_000)
    XCTAssertEqual(result.allocatedBytes, 2_000_000_000)
    XCTAssertEqual(result.rows.first?.selectable, false)
  }

  func testHiddenProtectedTotalsAndExplicitDockerReviewRemainSafe() throws {
    let index = try index()
    var query = FileBrowserIndex.Query()
    let normal = try index.filter(query)
    XCTAssertEqual(normal.rows.map(\.file.path), [moviePath])
    XCTAssertEqual(normal.hiddenProtected, 1)
    XCTAssertEqual(normal.bytes, 10_000_000_000)
    XCTAssertEqual(normal.allocatedBytes, 10_000_000_000)

    query.category = FileCategory.docker.rawValue
    let docker = try index.filter(query)
    XCTAssertEqual(docker.rows.map(\.file.path), [dockerPath])
    XCTAssertTrue(docker.rows.allSatisfy { !$0.selectable })
    XCTAssertEqual(docker.bytes, 1_000_000_000_000)
    XCTAssertEqual(docker.allocatedBytes, 2_000_000_000)
  }

  func testPageExpansionRequiresOnlyAnIncreasingLimit() {
    let previous = FileBrowserIndex.Query()
    var next = previous
    next.limit = 400
    XCTAssertTrue(next.isPageExpansion(of: previous))
    XCTAssertFalse(previous.isPageExpansion(of: previous))
    XCTAssertFalse(previous.isPageExpansion(of: next))

    let changes: [(String, (inout FileBrowserIndex.Query) -> Void)] = [
      ("search", { $0.text = "archive" }),
      ("category", { $0.category = FileCategory.docker.rawValue }),
      ("minimum size", { $0.minimumMB = 100 }),
      ("age", { $0.olderThanDays = 30 }),
      ("archives", { $0.archivesAndDownloads = true }),
      ("protected", { $0.showProtected = true })
    ]
    for (name, change) in changes {
      var changed = next
      change(&changed)
      XCTAssertFalse(changed.isPageExpansion(of: previous), name)
      var expanded = changed
      expanded.limit += 200
      XCTAssertTrue(expanded.isPageExpansion(of: changed), name)
    }
  }
}
