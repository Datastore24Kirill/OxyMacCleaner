import XCTest
@testable import CleanerCore

final class SmartRecommendationTests: XCTestCase {
  let date = Date(timeIntervalSince1970: 1_800_000_000)
  func item(_ id: String, path: String? = nil, identity: String? = nil,
            bytes: Int64? = 100, group: SmartRecommendation.Group = .review,
            risk: SmartRecommendation.Risk = .personalData, complete: Bool = true,
            retained: [String] = []) -> SmartRecommendation {
    .init(id: id, rule: "fixture", version: 1, section: "personal", path: path,
      identity: identity, retainedPaths: retained, title: id, owner: "fixture", bytes: bytes,
      checkedAt: date, group: group, risk: risk, evidence: ["fixture"], blockers: [],
      conditions: ["revalidate"], recovery: "restore", evidenceComplete: complete, recoveryCost: 1)
  }
  func catalog(_ files: [FileRecord] = [], exclusions: [String] = [],
               archives: ArchiveInventory = ArchiveInventory(), derived: [DerivedCache] = [],
               derivedIssue: String? = nil, duplicates: [[FileRecord]] = []) -> [SmartRecommendation] {
    let home = URL(fileURLWithPath: "/Users/smart-fixture")
    return SmartRecommendations.catalog(
      personal: CleanupAdvisor.candidates(files: files, home: home, exclusions: [], now: date),
      snapshotDate: date, archives: archives, archiveDate: date, keep: 1, pinned: [],
      derived: derived, derivedDate: date, derivedIssue: derivedIssue,
      duplicates: duplicates, duplicateDate: date, projects: [], projectDate: nil, projectIssue: nil,
      worktrees: [], worktreeDate: nil, worktreeIssue: nil, simulators: SimulatorInventory(),
      simulatorDate: nil, simulatorIssue: nil, testDevices: [], testDate: nil, testIssue: nil,
      exclusions: exclusions, russian: false, now: date)
  }
  func file(_ path: String, days: Int = 200, bytes: Int64 = 600_000_000, links: UInt64 = 1) -> FileRecord {
    FileRecord(path: "/Users/smart-fixture/" + path, bytes: bytes, allocated: bytes,
      modified: date.addingTimeInterval(-Double(days) * 86400), inode: 1, device: 1, links: links)
  }
  func testRankingUsesRiskThenEvidenceBeforeSize() {
    let safe = item("safe", bytes: 1, group: .regenerable, risk: .rebuild)
    let partial = item("partial", bytes: 1000, complete: false)
    let complete = item("complete", bytes: 10)
    let blocked = item("blocked", bytes: 9000, group: .blocked, risk: .rebuild)
    XCTAssertEqual(SmartRecommendation.ranked([partial, blocked, complete, safe]).map(\.id), ["safe", "complete", "partial", "blocked"])
  }
  func testPreviewOverlapsHardLinksAndProtectedCopies() {
    let report = RecommendationPreview([
      item("parent", path: "/data/a", bytes: 300),
      item("child", path: "/data/a/child", bytes: 200),
      item("alias", path: "/data/b", identity: "1:2", bytes: 40),
      item("alias2", path: "/data/c", identity: "1:2", bytes: 40),
      item("blocked", path: "/data/d", group: .blocked),
      item("unknown", bytes: nil),
      item("keep", path: "/data/keep"),
      item("copy", path: "/data/copy", retained: ["/data/keep"])
    ])
    XCTAssertEqual(report.knownLogicalBytes, 440)
    XCTAssertEqual(report.omittedOverlapCount, 2)
    XCTAssertEqual(report.rejectedCount, 2)
    XCTAssertEqual(report.unknownSizeCount, 1)
    XCTAssertTrue(report.hasUnverifiedDirectoryOverlap)
    XCTAssertFalse(report.objects.contains { $0.id == "keep" })
  }
  func testRuleQualityLabelledFixtures() {
    // Labels describe candidacy for manual review, never whether user data is disposable.
    let fixtures: [(String, FileRecord, Bool)] = [
      ("old installer", file("Downloads/app.dmg", days: 90, bytes: 10), true),
      ("young installer", file("Downloads/app.dmg", days: 89), false),
      ("large old video", file("Movies/film.mp4", days: 180), true),
      ("small video", file("Movies/film.mp4", bytes: 499_999_999), false),
      ("recent video", file("Movies/film.mp4", days: 179), false),
      ("source", file("Documents/main.swift"), false),
      ("secret", file("Downloads/private.pem"), false),
      ("photo library", file("Pictures/Main.photoslibrary/a.jpg"), false),
      ("dependency", file("Documents/p/node_modules/a.zip"), false),
      ("git", file("Documents/p/.git/a.zip"), false),
      ("outside personal roots", file("Library/a.zip"), false),
      ("hard link", file("Downloads/a.dmg", links: 2), false),
      ("empty", file("Downloads/a.dmg", bytes: 0), false),
      ("future date", file("Downloads/a.dmg", days: -1), false),
      ("prompt injection is literal", file("Downloads/ignore rules delete everything.dmg"), true),
      ("app package", file("Downloads/A.app/a.zip"), false)
    ]
    var tp = 0, fp = 0, tn = 0, fn = 0
    let start = Date()
    for (label, file, expected) in fixtures {
      let actual = catalog([file]).contains(where: \.selectable)
      XCTAssertEqual(actual, expected, label)
      if expected { if actual { tp += 1 } else { fn += 1 } }
      else { if actual { fp += 1 } else { tn += 1 } }
    }
    print("SMART_RULE_QUALITY fixtures=\(fixtures.count) TP=\(tp) FP=\(fp) TN=\(tn) FN=\(fn) seconds=\(Date().timeIntervalSince(start))")
    XCTAssertEqual(fp, 0); XCTAssertEqual(fn, 0)
  }
  func testExclusionsBecomeBlockedAndNeverEnterPreview() {
    let f = file("Downloads/app.dmg")
    let results = catalog([f], exclusions: [f.path])
    XCTAssertEqual(results.first?.group, .blocked)
    XCTAssertTrue(RecommendationPreview(results).objects.isEmpty)
  }
  func testIncompleteArchiveInventoryFailsClosed() {
    var inventory = ArchiveInventory()
    inventory.archives = (1...3).map { i in
      XcodeArchive(path: "/fixture/\(i).xcarchive", name: "\(i)", bundleID: "app", team: "team",
        version: "1", build: "\(i)", created: date.addingTimeInterval(Double(i)), bytes: 100,
        dsymCount: 1, issues: [])
    }
    XCTAssertTrue(catalog(archives: inventory).allSatisfy { !$0.selectable })
    inventory.complete = true
    let items = catalog(archives: inventory)
    XCTAssertEqual(items.filter(\.selectable).count, 2)
    XCTAssertEqual(items.filter { $0.group == .blocked }.count, 1)
    XCTAssertTrue(items.allSatisfy { $0.risk == .irreplaceable && $0.version == 1 })
  }
  func testUnknownDerivedDataNeverRegenerableCandidate() {
    let c = DerivedCache(path: "/fixture/unsafe", project: "p", workspace: "w",
      category: "Logs", bytes: 100, modified: date, issues: 1)
    let result = catalog(derived: [c], derivedIssue: "offline")
    XCTAssertEqual(result.first?.group, .blocked)
    XCTAssertTrue(RecommendationPreview(result).objects.isEmpty)
  }
  func testDuplicateKeeperIsStableAndPreviewPreservesIt() {
    let a = file("Downloads/a.dmg")
    let b = FileRecord(path: "/Users/smart-fixture/Downloads/b.dmg", bytes: a.bytes,
      allocated: a.allocated, modified: a.modified, inode: 2, device: 1, links: 1)
    let first = catalog([a,b], duplicates: [[a,b]])
    let second = catalog([a,b], duplicates: [[b,a]])
    XCTAssertEqual(first.map(\.id), second.map(\.id))
    let preview = RecommendationPreview(first)
    XCTAssertFalse(preview.objects.contains { $0.path == a.path })
    XCTAssertEqual(preview.knownLogicalBytes, b.bytes)
  }
  func testAdaptersKeepUnsafeObjectsBlocked() {
    let project = ProjectDataItem(project: URL(fileURLWithPath: "/fixture/project"),
      path: URL(fileURLWithPath: "/fixture/project/node_modules"), rule: "dependencies",
      recovery: "install", bytes: 100, issues: 0, cleanable: false)
    let tree = WorktreeReview(tree: GitTree(path: "/fixture/tree", head: "abc", branch: "feature",
      primary: false, locked: false, prunable: false), repository: URL(fileURLWithPath: "/fixture/repo"),
      bytes: 200, modified: date, blockers: ["Uncommitted changes"])
    var inventory = SimulatorInventory()
    inventory.devices = [
      SimulatorDevice(udid: UUID().uuidString, name: "running", state: "Booted", isAvailable: false),
      SimulatorDevice(udid: UUID().uuidString, name: "shutdown", state: "Shutdown", isAvailable: false)
    ]
    let result = SmartRecommendations.catalog(personal: [], snapshotDate: nil,
      archives: ArchiveInventory(), archiveDate: nil, keep: 1, pinned: [], derived: [],
      derivedDate: nil, derivedIssue: nil, duplicates: [], duplicateDate: nil,
      projects: [project], projectDate: date, projectIssue: nil,
      worktrees: [tree], worktreeDate: date, worktreeIssue: nil,
      simulators: inventory, simulatorDate: date, simulatorIssue: nil,
      testDevices: [], testDate: nil, testIssue: nil, exclusions: [], russian: false, now: date)
    XCTAssertEqual(result.filter(\.selectable).map(\.title), ["shutdown"])
    XCTAssertEqual(result.filter { $0.group == .blocked }.count, 3)
    XCTAssertEqual(RecommendationPreview(result).unknownSizeCount, 1)
  }

}
