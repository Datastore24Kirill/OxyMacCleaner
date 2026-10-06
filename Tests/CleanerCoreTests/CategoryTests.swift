import XCTest

@testable import CleanerCore

final class CategoryTests: XCTestCase {
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
