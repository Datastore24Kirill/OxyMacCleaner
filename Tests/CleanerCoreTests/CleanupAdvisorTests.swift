import XCTest

@testable import CleanerCore

final class CleanupAdvisorTests: XCTestCase {
  let home = URL(fileURLWithPath: "/Users/advisor-test")
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  func file(
    _ path: String, size: Int64 = 600_000_000, days: Int = 200, inode: UInt64 = 1, links: UInt64 = 1
  ) -> FileRecord {
    FileRecord(
      path: home.appendingPathComponent(path).path, bytes: size, allocated: size,
      modified: now.addingTimeInterval(-Double(days) * 86400), inode: inode, device: 1, links: links
    )
  }
  func candidates(_ files: [FileRecord], excluded: [String] = []) -> [CleanupCandidate] {
    CleanupAdvisor.candidates(files: files, home: home, exclusions: excluded, now: now)
  }
  func testInstallerBoundaryAndRulePriority() {
    XCTAssertEqual(
      candidates([file("Downloads/App.DMG", size: 100, days: 90)]).first?.rule, .oldInstaller)
    XCTAssertTrue(candidates([file("Downloads/App.dmg", days: 89)]).isEmpty)
    XCTAssertEqual(candidates([file("Downloads/App.dmg")]).count, 1)
    XCTAssertEqual(candidates([file("Downloads/App.dmg")]).first?.rule, .oldInstaller)
  }
  func testLargeOldBoundaryAndPersonalScope() {
    XCTAssertEqual(
      candidates([file("Movies/film.mp4", size: 500_000_000, days: 180)]).first?.rule, .largeOldFile
    )
    XCTAssertTrue(candidates([file("Movies/film.mp4", size: 499_999_999)]).isEmpty)
    XCTAssertTrue(candidates([file("Library/secret.mp4"), file("Downloads2/app.dmg")]).isEmpty)
    XCTAssertTrue(candidates([file("Movies/film.mp4", days: -1)]).isEmpty)
  }
  func testProtectedDataDependenciesAndExclusions() {
    for path in [
      "Downloads/key.pem", "Documents/code.swift", "Downloads/Foo.app/video.mp4",
      "Pictures/Photos.photoslibrary/original.jpg", "Documents/project/node_modules/archive.zip",
      "Documents/project/vendor/archive.zip", "Documents/.git/a.zip",
    ] {
      XCTAssertTrue(candidates([file(path)]).isEmpty, path)
    }
    let candidate = file("Downloads/App.dmg")
    XCTAssertTrue(
      candidates([candidate], excluded: [home.appendingPathComponent("Downloads").path]).isEmpty)
  }
  func testNoDoubleCountAndNoHardLinkCandidates() {
    XCTAssertEqual(candidates([file("Downloads/App.dmg"), file("Movies/same.mp4")]).count, 1)
    XCTAssertTrue(candidates([file("Downloads/App.dmg", links: 2)]).isEmpty)
    XCTAssertTrue(candidates([file("Downloads/empty.dmg", size: 0)]).isEmpty)
  }
}
