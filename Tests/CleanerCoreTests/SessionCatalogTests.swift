import XCTest
@testable import CleanerCore
final class SessionCatalogTests: XCTestCase {
  var root: URL!
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
  func write(_ path: String, _ text: String = "not parsed by discovery") throws -> URL {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
  }
  func testNestedMetadataOnlyAndDuplicateRoots() throws {
    let old = try write("archived/old.jsonl")
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: old.path)
    let new = try write("sessions/2026/new.jsonl")
    _ = try write("database.sqlite")
    let result = try SessionCatalog.discover(roots: [root, root])
    XCTAssertEqual(result.files.map { $0.url.resolvingSymlinksInPath().path }, [new, old].map { $0.resolvingSymlinksInPath().path })
    XCTAssertEqual(result.issues, 0)
    XCTAssertFalse(result.limited)
    XCTAssertTrue(result.files.allSatisfy(\.importable))
  }
  func testSymlinksAreNotTraversed() throws {
    _ = try write("real/session.jsonl")
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root)
    let result = try SessionCatalog.discover(roots: [root])
    XCTAssertEqual(result.files.count, 1)
    XCTAssertEqual(result.issues, 1)
  }
  func testLimitsCancellationAndMissingRoot() throws {
    for index in 0..<10 { _ = try write("\(index).jsonl") }
    XCTAssertTrue(try SessionCatalog.discover(roots: [root], maximumEntries: 3).limited)
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try SessionCatalog.discover(roots: [root], cancellation: token))
    XCTAssertEqual(try SessionCatalog.discover(roots: [root.appendingPathComponent("missing")]).issues, 1)
  }
  func testEmptyAndOversizedFilesStayVisibleButCannotImport() throws {
    _ = try write("empty.jsonl", "")
    let big = try write("large.jsonl", "")
    let handle = try FileHandle(forWritingTo: big)
    try handle.truncate(atOffset: 30_000_001); try handle.close()
    let result = try SessionCatalog.discover(roots: [root])
    XCTAssertEqual(result.files.count, 2)
    XCTAssertTrue(result.files.allSatisfy { !$0.importable })
  }
}
