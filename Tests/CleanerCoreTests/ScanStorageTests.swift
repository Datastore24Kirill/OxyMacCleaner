import XCTest

@testable import CleanerCore

final class ScanStorageTests: XCTestCase {
  var root: URL!
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OxyScanTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
  func testRoundTripPartialAndCompleteAndPrivacy() throws {
    let input = root.appendingPathComponent("input")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try Data("12345".utf8).write(to: input.appendingPathComponent("a.txt"))
    let report = Scanner.scan(roots: [input], excluded: [], cancellation: Cancellation())
    let store = ScanStore(url: root.appendingPathComponent("state/latest.plist"))
    XCTAssertNil(try store.load())
    var progress = ScanProgress()
    progress.files = 1
    progress.bytes = 5
    progress.phase = .finished
    try store.save(
      SavedScan(roots: [input], volumeID: "custom", report: report, progress: progress))
    let loaded = try XCTUnwrap(store.load())
    XCTAssertEqual(loaded.report.files, report.files)
    XCTAssertEqual(loaded.report.folders, report.folders)
    XCTAssertTrue(loaded.report.complete)
    XCTAssertEqual(loaded.progress.phase, .finished)
    let attrs = try FileManager.default.attributesOfItem(atPath: store.url.path)
    XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    var partial = report
    partial.complete = false
    progress.phase = .cancelled
    try store.save(
      SavedScan(roots: [input], volumeID: "custom", report: partial, progress: progress))
    XCTAssertFalse(try XCTUnwrap(store.load()).report.complete)
    try Data("changed".utf8).write(to: input.appendingPathComponent("a.txt"))
    XCTAssertThrowsError(try loaded.report.files[0].validate())
  }
  func testCorruptionIsReported() throws {
    let store = ScanStore(url: root.appendingPathComponent("broken.plist"))
    try Data("broken".utf8).write(to: store.url)
    XCTAssertThrowsError(try store.load())
  }
  func testMapOnlySumsImmediateChildren() throws {
    let sub = root.appendingPathComponent("child/grandchild")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 20).write(to: sub.appendingPathComponent("deep.bin"))
    try Data(repeating: 1, count: 10).write(to: root.appendingPathComponent("direct.bin"))
    let report = Scanner.scan(roots: [root], excluded: [], cancellation: Cancellation())
    let nodes = try XCTUnwrap(
      DiskIndex(report: report).children[root.resolvingSymlinksInPath().path])
    XCTAssertEqual(nodes.count, 2)
    XCTAssertEqual(nodes.reduce(0) { $0 + $1.bytes }, report.total)
    XCTAssertTrue(nodes[0].directory)
  }
  func testMapAreaAndBounds() {
    let weights: [Int64] = [50, 30, 20, 0]
    let tiles = DiskLayout.tiles(weights: weights, width: 800, height: 400)
    XCTAssertEqual(tiles.count, 3)
    for tile in tiles {
      XCTAssertEqual(
        tile.width * tile.height, Double(weights[tile.index]) / 100 * 320000, accuracy: 0.01)
      XCTAssertGreaterThanOrEqual(tile.x, 0)
      XCTAssertGreaterThanOrEqual(tile.y, 0)
      XCTAssertLessThanOrEqual(tile.x + tile.width, 800.001)
      XCTAssertLessThanOrEqual(tile.y + tile.height, 400.001)
    }
    XCTAssertTrue(DiskLayout.tiles(weights: [0, 0], width: 100, height: 100).isEmpty)
  }
}
