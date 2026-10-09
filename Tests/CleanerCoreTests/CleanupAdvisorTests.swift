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
  func testLargeCatalogSearchAndOrderingDoNotTruncateOrChangeEligibility() {
    var files: [FileRecord] = []
    for index in 0..<1505 {
      let path = "Downloads/fixture-\(index).dmg"
      let record = file(path, size: Int64(index + 1), days: 90 + index, inode: UInt64(index + 1))
      files.append(record)
    }
    let all = candidates(files)
    XCTAssertEqual(all.count, 1505)
    for sort in CandidateSort.allCases {
      let ordered = CandidateList.matching(all, sort: sort)
      XCTAssertEqual(Set(ordered.map(\.id)), Set(all.map(\.id)))
      var revealed: [String] = []
      for start in stride(from: 0, to: ordered.count, by: 100) {
        revealed += ordered.dropFirst(start).prefix(100).map(\.id)
      }
      XCTAssertEqual(revealed.count, 1505)
      XCTAssertEqual(Set(revealed).count, 1505)
      XCTAssertEqual(SpaceEstimate(files: ordered.map(\.file)).logical, 1_133_265)
    }
    XCTAssertEqual(CandidateList.matching(all, query: " FIXTURE-1504.DMG ").count, 1)
    XCTAssertTrue(CandidateList.matching(all, rule: "largeOldFile").isEmpty)
    XCTAssertEqual(CandidateList.matching(all, sort: .oldest).first?.ageDays, 1594)
    XCTAssertEqual(CandidateList.matching(all, sort: .size).first?.file.bytes, 1505)
  }

  func testTypeSortKeepsPersonalMediaSeparateAndUsesStableTieBreak() {
    let items = candidates([
      file("Movies/b.mp4", inode: 1), file("Pictures/a.jpg", inode: 2),
      file("Movies/a.mp4", inode: 3), file("Downloads/installer.dmg", inode: 4)
    ])
    let sorted = CandidateList.matching(items, sort: .type)
    XCTAssertEqual(sorted.map(\.file.name), ["installer.dmg", "a.jpg", "a.mp4", "b.mp4"])
    XCTAssertFalse(sorted.contains { $0.file.category == FileCategory.caches.rawValue })
  }

  func testRecommendedInstallerRoundTripAndFreshList() throws {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let root = home.appendingPathComponent("Downloads/OxyAdvisorQA-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("fixture.dmg")
    let payload = Data("Disposable installer fixture, never executable".utf8)
    try payload.write(to: source)
    try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-100 * 86400)], ofItemAtPath: source.path)
    let record = try FileRecord.read(source)
    let candidates = CleanupAdvisor.candidates(files: [record], home: home, exclusions: [])
    XCTAssertEqual(candidates.count, 1)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    let entry = try store.move(try XCTUnwrap(candidates.first).file)
    XCTAssertFalse(fm.fileExists(atPath: source.path))
    XCTAssertTrue(store.inspect(entry).payloadValid)
    var report = ScanReport(); report.files = [record]
    let saved = SavedScan(roots: [root], volumeID: "fixture", report: report, progress: ScanProgress())
    let updated = ScanReconciliation.removing([source.path], from: saved)
    XCTAssertTrue(CleanupAdvisor.candidates(files: updated.report.files, home: home, exclusions: []).isEmpty)
    try store.restore(entry)
    XCTAssertEqual(try Data(contentsOf: source), payload)
    XCTAssertEqual(CleanupAdvisor.candidates(files: [try FileRecord.read(source)], home: home, exclusions: []).count, 1)
  }

}
