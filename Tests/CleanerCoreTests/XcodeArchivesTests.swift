import XCTest

@testable import CleanerCore

final class XcodeArchivesTests: XCTestCase {
  func archive(
    _ path: String, team: String? = "A", bundle: String = "app", date: Double = 1,
    issues: [String] = []
  ) -> XcodeArchive {
    XcodeArchive(
      path: path, name: path, bundleID: bundle, team: team, version: "1", build: "1",
      created: Date(timeIntervalSince1970: date), bytes: 1, dsymCount: 0, issues: issues)
  }
  func testRetentionSeparatesAppsAndTeamsAndKeepsPinsAdditionally() {
    let values = [
      archive("old"), archive("middle", date: 2), archive("new", date: 3),
      archive("team", team: "B"), archive("app", bundle: "other"),
    ]
    let result = ArchiveRetention.decisions(values, keep: 1, pinned: ["old"])
    XCTAssertEqual(result["old"], .pinned)
    XCTAssertEqual(result["middle"], .review)
    for path in ["new", "team", "app"] { XCTAssertEqual(result[path], .latest) }
  }
  func testIncompleteArchivesNeverBecomeReviewCandidates() {
    let values = [
      archive("bad", issues: ["unreadable"]), archive("unknown-team", team: nil),
      archive("good", date: 3),
    ]
    let result = ArchiveRetention.decisions(values, keep: 0, pinned: [])
    XCTAssertEqual(result["bad"], .unknown)
    XCTAssertEqual(result["unknown-team"], .unknown)
    XCTAssertEqual(result["good"], .latest)
  }
  func fixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OxyArchives-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return root
  }
  func testInventoryReadsMetadataSizeAndDSYMPackages() throws {
    let root = try fixture()
    let package = root.appendingPathComponent("Test.xcarchive")
    try FileManager.default.createDirectory(
      at: package.appendingPathComponent("dSYMs/Test.app.dSYM"), withIntermediateDirectories: true)
    let plist: [String: Any] = [
      "ArchiveVersion": 2, "Name": "Test", "CreationDate": Date(timeIntervalSince1970: 100),
      "ApplicationProperties": [
        "CFBundleIdentifier": "test.app", "CFBundleVersion": "42",
        "CFBundleShortVersionString": "1.2", "Team": "A",
      ],
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .binary, options: 0)
    try data.write(to: package.appendingPathComponent("Info.plist"))
    try Data([1, 2, 3]).write(to: package.appendingPathComponent("binary"))
    let result = XcodeArchives.scan(root: root, cancellation: Cancellation())
    XCTAssertTrue(result.complete)
    XCTAssertEqual(result.archives.count, 1)
    let item = try XCTUnwrap(result.archives.first)
    XCTAssertEqual(item.build, "42")
    XCTAssertEqual(item.dsymCount, 1)
    XCTAssertEqual(item.bytes, Int64(data.count + 3))
    XCTAssertTrue(item.eligibleForRetention)
  }
  func testMissingMetadataAndSymlinkRemainUntrusted() throws {
    let root = try fixture()
    let package = root.appendingPathComponent("Broken.xcarchive")
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: package.appendingPathComponent("link"), withDestinationURL: root)
    let result = XcodeArchives.scan(root: root, cancellation: Cancellation())
    let item = try XCTUnwrap(result.archives.first)
    XCTAssertFalse(item.eligibleForRetention)
    XCTAssertGreaterThanOrEqual(item.issues.count, 2)
    XCTAssertEqual(item.bytes, 0)
  }
  func testCancelledEmptyScanDoesNotReportComplete() throws {
    let root = try fixture()
    let cancellation = Cancellation()
    cancellation.cancel()
    XCTAssertFalse(XcodeArchives.scan(root: root, cancellation: cancellation).complete)
  }
}
