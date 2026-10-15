import XCTest
@testable import CleanerCore

final class FileBrowserPerformanceTests: XCTestCase {
  private func record(_ name: String, inode: UInt64) -> FileRecord {
    FileRecord(path: "/Users/test/Downloads/" + name, bytes: 10, allocated: 8,
               modified: .distantPast, inode: inode, device: 1, links: 1)
  }

  private func index(_ files: [FileRecord]) throws -> FileBrowserIndex {
    try FileBrowserIndex(files: files, excluded: [], quarantine: "/Users/test/Quarantine",
                         downloads: "/Users/test/Downloads")
  }

  func testNamedLeavesNeverBorrowProtectionFromOrdinarySiblingsInEitherOrder() throws {
    let pairs = [
      ("Podfile", "README"), ("Cartfile", "CHANGELOG"),
      ("Podfile.lock", "ordinary.lock"), ("Package.resolved", "ordinary.resolved"),
      ("com.docker.docker", "ordinary.docker"), ("group.com.docker", "ordinary.docker"),
      ("Docker.raw", "camera.raw"), ("Docker.qcow2", "ordinary.qcow2"),
      ("backups.backupdb", "ordinary.backupdb")
    ]
    for (special, ordinary) in pairs {
      let protected = record(special, inode: 1)
      let unprotected = record(ordinary, inode: 2)
      for records in [[unprotected, protected], [protected, unprotected]] {
        let browser = try index(records)
        var query = FileBrowserIndex.Query()
        let visible = try browser.filter(query)
        XCTAssertEqual(visible.rows.map(\.file.path), [unprotected.path], special)
        XCTAssertEqual(visible.hiddenProtected, 1, special)
        XCTAssertEqual(visible.matches, 1, special)
        XCTAssertEqual(visible.bytes, 10, special)
        XCTAssertEqual(visible.allocatedBytes, 8, special)

        query.showProtected = true
        let review = try browser.filter(query)
        XCTAssertEqual(review.rows.count, 2, special)
        for row in review.rows {
          XCTAssertEqual(row.selectable, row.file.path == unprotected.path, row.file.path)
          XCTAssertEqual(row.category, FileCategory.classify(row.file.path).rawValue, row.file.path)
        }
      }
    }
  }

  func testProtectedCountAndTotalsRemainCorrectAcrossClassificationCacheChurn() throws {
    // More distinct parent groups than the previous cache capacity; revisit them reversed.
    let ordinary = (0..<4_200).map { record("folder-\($0)/ordinary.docker", inode: UInt64($0 + 1)) }
    let protected = (0..<4_200).reversed().map { record("folder-\($0)/com.docker.docker", inode: UInt64($0 + 5_000)) }
    let result = try index(ordinary + protected).filter(.init())
    XCTAssertEqual(result.matches, 4_200)
    XCTAssertEqual(result.hiddenProtected, 4_200)
    XCTAssertEqual(result.rows.count, 200)
    XCTAssertEqual(result.bytes, 42_000)
    XCTAssertEqual(result.allocatedBytes, 33_600)
    XCTAssertTrue(result.rows.allSatisfy { $0.selectable && $0.file.name == "ordinary.docker" })
  }

  func testMidQueryCancellationDoesNotPublishOrCachePartialResults() throws {
    let files = (0..<1_024).map { record("file-\($0).zip", inode: UInt64($0 + 1)) }
    let browser = try index(files)
    let token = Cancellation()
    XCTAssertThrowsError(try browser.filter(.init(), cancellation: token) { _ in token.cancel() }) {
      XCTAssertTrue($0 is CancellationError)
    }
    let completed = try browser.filter(.init())
    XCTAssertEqual(completed.matches, files.count)
    XCTAssertEqual(completed.bytes, Int64(files.count * 10))
    XCTAssertEqual(completed.rows.count, 200)
  }

  func testSnapshotProtectionMatchesPublicPolicyForNoncanonicalAndUnicodePaths() {
    let paths = [
      "/System/cache.bin", "//System/cache.bin", "///usr/bin/tool", "/System//cache.bin",
      "/Users/test/Downloads/../Library/private.bin", "/Users/test/./Downloads/photo.jpg",
      "/Users/test/Downloads/Docker.raw/../photo.jpg", "./Library/Mail/file.bin",
      "../Library/Mail/file.bin", "relative/README", "/", "", "/Users/test/Downloads/",
      "/Users/test/Downloads/Проект/写真.jpg", "/Users/test/Downloads/Cafe\u{301}/photo.jpg",
      "/Users/test/Downloads/.app/file.bin", "/Users/test/Downloads/.hidden.app/file.bin",
      "/Users/test/Downloads/.swift", "/Users/test/Downloads/.env.production",
      "/Volumes/Backup/System/cache.bin", "/Volumes/Backup//System/cache.bin",
      "//Volumes/Backup/Applications/Tool.app/data.bin", "/Volumes/Backup/Systematic/data.bin",
      "/Volumes/Backup/Users/test/Downloads/photo.jpg", "/Volumes/Backup/Library/data.bin"
    ]
    for path in paths {
      XCTAssertEqual(QuarantineStore.protectedSnapshotPath(path), QuarantineStore.protected(path), path)
    }
  }

  func testCanonicalSystemAndPackageBoundariesRemainProtected() {
    let protected = [
      "/System/cache.bin", "/usr/local/bin/tool", "/Volumes/Backup/System/cache.bin",
      "/Volumes/Backup/Applications/Tool.app/data.bin", "/Users/test/Downloads/.hidden.app/data.bin",
      "/Users/test/Downloads/Photo.photoslibrary/data.bin", "/Users/test/Downloads/private.key",
      "/Users/test/Downloads/项目/.git/config", "/Users/test/Library/data.bin"
    ]
    let ordinary = [
      "/Users/test/Downloads/Systematic/photo.jpg", "/Volumes/Backup/Systematic/photo.jpg",
      "/Users/test/Downloads/App.app.notes/photo.jpg", "/Users/test/Downloads/private.key.notes",
      "/Users/test/Downloads/项目/git-notes.txt", "/Users/test/Downloads/.swift",
      "/Users/test/Downloads/.app/photo.jpg"
    ]
    for path in protected {
      XCTAssertTrue(QuarantineStore.protected(path), path)
      XCTAssertTrue(QuarantineStore.protectedSnapshotPath(path), path)
    }
    for path in ordinary {
      XCTAssertFalse(QuarantineStore.protected(path), path)
      XCTAssertFalse(QuarantineStore.protectedSnapshotPath(path), path)
    }
  }
}
