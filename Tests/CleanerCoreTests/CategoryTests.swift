import XCTest

@testable import CleanerCore

final class CategoryTests: XCTestCase {
  func testDockerOwnershipAndRelocatedDiskProtection() throws {
    for path in ["/Users/u/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                 "/Volumes/External/VM/Docker.qcow2", "/VM/Docker.raw", "/Users/u/.docker/config.json"] {
      XCTAssertEqual(FileCategory.classify(path), .docker)
      XCTAssertTrue(QuarantineStore.protected(path))
    }
    XCTAssertNotEqual(FileCategory.classify("/Photos/camera.raw"), .docker)
    XCTAssertNotEqual(FileCategory.classify("/Downloads/Docker.raw.notes"), .docker)
    // Records intentionally do not exist: duplicate detection must never open Docker disks.
    let records = ["/VM/Docker.raw", "/External/Docker.raw"].enumerated().map { i, path in
      FileRecord(path: path, bytes: 1_000_000, allocated: 4096, modified: Date(), inode: UInt64(i + 1), device: 1, links: 1)
    }
    XCTAssertTrue(try Scanner.duplicates(records, cancellation: Cancellation()).isEmpty)
    let index = try FileBrowserIndex(files: records, excluded: [], quarantine: "/quarantine", downloads: "/Downloads")
    var query = FileBrowserIndex.Query()
    XCTAssertEqual(try index.filter(query).matches, 0)
    query.category = FileCategory.docker.rawValue
    let result = try index.filter(query)
    XCTAssertEqual(result.matches, 2)
    XCTAssertEqual(result.bytes, 8192)
    XCTAssertTrue(result.rows.allSatisfy { !$0.selectable })
  }
  func testMediaAndDocuments() {
    for (path, expected) in [
      ("/Photos/IMG.HEIC", FileCategory.images), ("/Movies/a.MKV", .video),
      ("/Music/a.flac", .audio), ("/Documents/a.pdf", .documents), ("/Downloads/a.7z", .archive),
      ("/Projects/a.swift", .source),
    ] {
      XCTAssertEqual(FileCategory.classify(path), expected)
    }
  }
  func testContainerOwnershipPrecedesEmbeddedMedia() {
    XCTAssertEqual(FileCategory.classify("/Applications/Tool.app/Contents/a.png"), .applications)
    XCTAssertEqual(
      FileCategory.classify(
        "/Users/u/Library/Application Support/Steam/steamapps/common/Game/a.mp4"), .games)
    XCTAssertEqual(
      FileCategory.classify("/Users/u/Library/Application Support/Autodesk/a.png"), .appData)
    XCTAssertEqual(FileCategory.classify("/Users/u/Library/Caches/a.jpg"), .caches)
    XCTAssertEqual(FileCategory.classify("/System/Library/a.png"), .system)
  }
  func testDeveloperAndPhotoLibraryBoundaries() {
    XCTAssertEqual(FileCategory.classify("/DerivedData/app.app/a.png"), .derivedData)
    XCTAssertEqual(
      FileCategory.classify("/Archives/App.xcarchive/Products/App.app/a.jpg"), .xcodeArchive)
    XCTAssertEqual(FileCategory.classify("/Project/node_modules/test/a.png"), .build)
    XCTAssertEqual(FileCategory.classify("/Photos.photoslibrary/database/store.db"), .images)
    XCTAssertEqual(FileCategory.classify("/Downloads/my.app.notes/a.xyz"), .other)
    XCTAssertEqual(FileCategory.classify("/Downloads/steamapps.txt"), .documents)
  }
}
