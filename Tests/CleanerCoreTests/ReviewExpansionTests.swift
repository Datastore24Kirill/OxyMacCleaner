import XCTest
@testable import CleanerCore

final class ReviewExpansionTests: XCTestCase {
  func testBoundedCacheEvictsByCostAndRecency() {
    let cache = BoundedCache<String, Int>(capacity: 2, budget: 3)
    cache.insert(1, for: "a", cost: 1); cache.insert(2, for: "b", cost: 1)
    XCTAssertEqual(cache.value(for: "a"), 1)
    cache.insert(3, for: "c", cost: 2)
    XCTAssertNil(cache.value(for: "b")); XCTAssertEqual(cache.value(for: "a"), 1)
    cache.insert(4, for: "huge", cost: 4)
    XCTAssertNil(cache.value(for: "huge")); XCTAssertEqual(cache.value(for: "c"), 3)
  }
  func testCachedQueriesKeepCancellationAgeAndExclusions() throws {
    let now = Date()
    let file = FileRecord(path: "/Users/test/Downloads/a.zip", bytes: 10, allocated: 10, modified: now, inode: 1, device: 1, links: 1)
    let index = try FileBrowserIndex(files: [file], excluded: [], quarantine: "/q", downloads: "/d")
    var query = FileBrowserIndex.Query()
    XCTAssertEqual(try index.filter(query).matches, 1)
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try index.filter(query, cancellation: token))
    query.olderThanDays = 1
    XCTAssertEqual(try index.filter(query, now: now).matches, 0)
    XCTAssertEqual(try index.filter(query, now: now.addingTimeInterval(172800)).matches, 1)
    query.olderThanDays = 0
    let changed = try FileBrowserIndex(files: [file], excluded: [file.path], quarantine: "/q", downloads: "/d")
    XCTAssertEqual(try changed.filter(query).matches, 0)
  }
  func testSecondPageIsPreparedWithFirstWithoutChangingVisibleSelection() throws {
    let files = (1...700).map { FileRecord(path: "/Users/test/Downloads/\($0).zip", bytes: Int64($0), allocated: 1, modified: .distantPast, inode: UInt64($0), device: 1, links: 1) }
    let index = try FileBrowserIndex(files: files, excluded: [], quarantine: "/q", downloads: "/d")
    var query = FileBrowserIndex.Query()
    let first = try index.filter(query)
    XCTAssertEqual(first.rows.count, 200)
    query.limit = 400
    let progress = BoundedCache<String, [Double]>(capacity: 1, budget: 100)
    let next = try index.filter(query) { value in
      progress.insert((progress.value(for: "values") ?? []) + [value], for: "values", cost: 1)
    }
    XCTAssertEqual(progress.value(for: "values"), [1])
    XCTAssertEqual(next.rows.count, 400)
    XCTAssertEqual(Array(next.rows.prefix(200)).map(\.file), first.rows.map(\.file))
    XCTAssertEqual(next.matches, first.matches)
  }
  func testSearchPreservesCaseDiacriticsAndUnicodePaths() throws {
    let paths = ["/Users/test/Downloads/Café.zip", "/Users/test/Downloads/CAFÉ-2.zip", "/Users/test/Downloads/日本語.zip", "/Users/test/Downloads/Архив.zip"]
    let files = paths.enumerated().map { FileRecord(path: $0.element, bytes: Int64($0.offset + 1), allocated: 1, modified: .distantPast, inode: UInt64($0.offset), device: 1, links: 1) }
    let index = try FileBrowserIndex(files: files, excluded: [], quarantine: "/q", downloads: "/d")
    for text in ["cafe", "CAFÉ", "日本", "архив", "absent"] {
      var query = FileBrowserIndex.Query(); query.text = text
      let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      let expected = paths.filter { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(folded) }
      XCTAssertEqual(Set(try index.filter(query).rows.map(\.file.path)), Set(expected))
    }
  }
  func testMapCacheDoesNotCrossSnapshotOrPrefixBoundaries() throws {
    var scan = ScanReport(); scan.folders = ["/": 10, "/apps": 5, "/apps2": 5, "/apps/one": 5]
    let index = DiskIndex(report: scan)
    XCTAssertEqual(try index.nodes(in: "/apps").0.map(\.path), ["/apps/one"])
    XCTAssertEqual(try index.nodes(in: "/apps").0.map(\.path), ["/apps/one"])
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try index.nodes(in: "/apps", cancellation: token))
    XCTAssertTrue(try DiskIndex(report: ScanReport()).nodes(in: "/apps").0.isEmpty)
  }
  func testOwnershipRequiresExactIDAndAvoidsAmbiguousOrSharedGroups() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/OxyOwnershipTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Fixture.app")
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"com.example.fixture", "CFBundleName":"Fixture"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    let catalog = try OwnershipCatalog.load(appRoots: [root], projectRoots: [])
    XCTAssertEqual(catalog.applications.count, 1)
    let home = URL(fileURLWithPath: "/Users/test")
    let path = "/Users/test/Library/Containers/com.example.fixture/Data/db"
    let owner = catalog.identify(path, home: home, russian: true)
    XCTAssertEqual(owner.name, "Fixture"); XCTAssertTrue(owner.evidence.contains("Info.plist"))
    XCTAssertNotEqual(catalog.identify(path.replacingOccurrences(of: "fixture/", with: "fixtureOther/"), home: home, russian: true).name, "Fixture")
    let duplicate = OwnershipCatalog(applications: catalog.applications + catalog.applications)
    XCTAssertEqual(duplicate.identify(path, home: home, russian: true).name, "com.example.fixture")
    XCTAssertNotEqual(catalog.identify("/Users/test/Library/Group Containers/com.example.fixture/Data", home: home, russian: true).name, "Fixture")
    XCTAssertTrue(QuarantineStore.protected(path))
  }
  func testCoverageSeparatesCitationFromVerbatimAndRechecksEdits() throws {
    let facts = [ContextFact(category: .constraint, text: "Never delete archives.", line: 1, quote: "Never delete archives."), ContextFact(category: .pending, text: "Next step: test rollback.", line: 2, quote: "Next step: test rollback.")]
    let output = "## Constraints and prohibitions\n- Delete archives. [L1]\n## Pending work and next steps\n- Next step: test rollback. [L2]"
    let rows = try ContextCoverage.compare(facts: facts, output: output)
    XCTAssertEqual(rows.first { $0.category == .constraint }?.referenced, 1)
    XCTAssertEqual(rows.first { $0.category == .constraint }?.verbatim, 0)
    XCTAssertEqual(rows.first { $0.category == .pending }?.verbatim, 1)
    let edited = try ContextCoverage.compare(facts: facts, output: "Nothing retained")
    XCTAssertTrue(edited.allSatisfy { $0.referenced == 0 && $0.verbatim == 0 })
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try ContextCoverage.compare(facts: facts, output: output, cancellation: token))
  }
  func testCoverageHandlesQuotedMultilineSourceAndRedaction() throws {
    let fact = ContextFact(category: .user, text: "First line\nNever delete backups.", line: 1, quote: "source")
    let rows = try ContextCoverage.compare(facts: [fact], output: "- [L1]\n  > First line\n  > Never delete backups.")
    XCTAssertEqual(rows.first?.verbatim, 1)
    let secret = ContextFact(category: .constraint, text: "token=synthetic_fixture_secret", line: 2, quote: "source")
    XCTAssertEqual(try ContextCoverage.compare(facts: [secret], output: "[REDACTED] [L2]").first?.verbatim, 1)
  }
}
