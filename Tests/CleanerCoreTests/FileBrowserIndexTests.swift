import XCTest
@testable import CleanerCore

final class FileBrowserIndexTests: XCTestCase {
  func file(_ path: String, bytes: Int64 = 42, links: UInt64 = 1, date: Date = .distantPast) -> FileRecord {
    FileRecord(path: path, bytes: bytes, allocated: bytes, modified: date, inode: UInt64(abs(path.hashValue % 100000)), device: 1, links: links)
  }
  func testDefaultHidesProtectedAndReviewModeCannotSelectThem() throws {
    let files = [file("/Users/test/Downloads/photo.jpg"), file("/System/cache.bin"), file("/Users/test/Library/file.bin"), file("/Users/test/code.swift"), file("/Users/test/Downloads/linked.zip", links: 2), file("/Users/test/excluded/file.zip"), file("/Users/test/quarantine/file.zip")]
    let index = try FileBrowserIndex(files: files, excluded: ["/Users/test/excluded"], quarantine: "/Users/test/quarantine", downloads: "/Users/test/Downloads")
    var query = FileBrowserIndex.Query()
    let normal = try index.filter(query)
    XCTAssertEqual(normal.matches, 1); XCTAssertEqual(normal.hiddenProtected, 6)
    query.showProtected = true
    let all = try index.filter(query)
    XCTAssertEqual(all.matches, 7); XCTAssertEqual(all.rows.filter(\.selectable).count, 1)
  }
  func testArchivesIncludeDownloadsAndIgnoreHiddenCategoryWithPaging() throws {
    let index = try FileBrowserIndex(files: [file("/Users/test/Downloads/Photo.JPG", bytes: 99), file("/Users/test/Desktop/old.zip", bytes: 100), file("/Users/test/Desktop/picture.jpg", bytes: 200)], excluded: [], quarantine: "/Users/test/quarantine", downloads: "/Users/test/Downloads")
    var query = FileBrowserIndex.Query(); query.archivesAndDownloads = true; query.category = "Video"; query.limit = 1
    let first = try index.filter(query)
    XCTAssertEqual(first.matches, 2); XCTAssertEqual(first.bytes, 199); XCTAssertEqual(first.rows.count, 1)
    XCTAssertEqual(first.rows.first?.file.name, "old.zip")
    query.text = "photo"; XCTAssertEqual(try index.filter(query).rows.first?.file.name, "Photo.JPG")
    query.text = "not-found"; XCTAssertEqual(try index.filter(query).matches, 0)
  }
  func testAgeSizeAndCancellation() throws {
    let now = Date()
    let index = try FileBrowserIndex(files: [file("/Users/test/old.mp4", bytes: 200_000_000, date: now.addingTimeInterval(-100*86400)), file("/Users/test/new.mp4", bytes: 200_000_000, date: now)], excluded: [], quarantine: "/q", downloads: "/d")
    var query = FileBrowserIndex.Query(); query.minimumMB = 100; query.olderThanDays = 90
    XCTAssertEqual(try index.filter(query, now: now).rows.map(\.file.name), ["old.mp4"])
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try index.filter(query, cancellation: token))
    XCTAssertThrowsError(try FileBrowserIndex(files: [file("/Users/test/a")], excluded: [], quarantine: "/q", downloads: "/d", cancellation: token))
  }
  func testCachedClassificationMatchesRulesForSpecialNamesAndParents() throws {
    let parents = ["/Users/test", "/Users/test/Library", "/Users/test/Build", "/Users/test/.cache", "/System", "/Volumes/Disk/Library", "/Users/test/Pictures.photoslibrary"]
    let names = ["a.zip", "b.zip", "Package.resolved", "ordinary.resolved", "Podfile.lock", "ordinary.lock", ".env", ".env.production", ".git", "library", "Library", "caches", "file.app", "file.swift", "file.key", "file.jpg", "file.JPG"]
    let files = parents.flatMap { parent in names.map { file(parent + "/" + $0) } }
    let index = try FileBrowserIndex(files: files, excluded: [], quarantine: "/q", downloads: "/d")
    var query = FileBrowserIndex.Query(); query.showProtected = true; query.limit = 1000
    for row in try index.filter(query).rows {
      XCTAssertEqual(row.selectable, !QuarantineStore.protected(row.file.path), row.file.path)
      XCTAssertEqual(row.category, row.file.category, row.file.path)
    }
  }
  func testHundredThousandRowsRemainPagedAndReusable() throws {
    let files = (0..<100_000).map { file("/Users/test/Downloads/file-\($0).zip", bytes: Int64($0 + 1)) }
    let begin = Date()
    let index = try FileBrowserIndex(files: files, excluded: [], quarantine: "/q", downloads: "/Users/test/Downloads")
    let built = Date()
    var query = FileBrowserIndex.Query()
    let result = try index.filter(query)
    XCTAssertEqual(result.matches, 100_000); XCTAssertEqual(result.rows.count, 200)
    query.text = "file-99999"
    XCTAssertEqual(try index.filter(query).matches, 1)
    print("BROWSER_BENCH 100k build=\(built.timeIntervalSince(begin))s two_cached_queries=\(Date().timeIntervalSince(built))s")
  }
}
