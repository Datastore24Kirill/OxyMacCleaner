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
               derivedIssue: String? = nil, duplicates: [[FileRecord]] = [],
               pinned: Set<String> = [], checked: Bool = true,
               simulators: SimulatorInventory = SimulatorInventory(), simulatorIssue: String? = nil) -> [SmartRecommendation] {
    let home = URL(fileURLWithPath: "/Users/smart-fixture")
    return SmartRecommendations.catalog(
      personal: CleanupAdvisor.candidates(files: files, home: home, exclusions: [], now: date),
      snapshotDate: checked ? date : nil, archives: archives, archiveDate: checked ? date : nil, keep: 1, pinned: pinned,
      derived: derived, derivedDate: checked ? date : nil, derivedIssue: derivedIssue,
      duplicates: duplicates, duplicateDate: date, projects: [], projectDate: nil, projectIssue: nil,
      worktrees: [], worktreeDate: nil, worktreeIssue: nil, simulators: simulators,
      simulatorDate: checked ? date : nil, simulatorIssue: simulatorIssue, testDevices: [], testDate: nil, testIssue: nil,
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

  func testLabelledDevelopmentRules() {
    var cases: [(String, Bool, Bool)] = []
    func record(_ label: String, _ items: [SmartRecommendation], _ expected: Bool, path: String? = nil) {
      let actual = items.contains { $0.selectable && (path == nil || $0.path == path) }
      cases.append((label, actual, expected))
    }
    let old = XcodeArchive(path: "/fixture/old.xcarchive", name: "old", bundleID: "app", team: "team",
      version: "1", build: "1", created: date.addingTimeInterval(-86400), bytes: 100, dsymCount: 1, issues: [])
    let new = XcodeArchive(path: "/fixture/new.xcarchive", name: "new", bundleID: "app", team: "team",
      version: "1", build: "2", created: date, bytes: 100, dsymCount: 1, issues: [])
    var inventory = ArchiveInventory(); inventory.complete = true; inventory.archives = [old,new]
    record("archive over limit", catalog(archives: inventory), true, path: old.path)
    record("archive last retained", catalog(archives: inventory), false, path: new.path)
    record("archive pinned", catalog(archives: inventory, pinned: [old.path]), false, path: old.path)
    record("archive excluded", catalog(exclusions: [old.path], archives: inventory), false, path: old.path)
    record("archive missing timestamp", catalog(archives: inventory, checked: false), false)
    inventory.complete = false
    record("archive incomplete inventory", catalog(archives: inventory), false)
    inventory.complete = true
    inventory.archives = [XcodeArchive(path: old.path, name: "unknown", bundleID: nil, team: nil,
      version: nil, build: nil, created: nil, bytes: 100, dsymCount: 0, issues: ["unreadable"])]
    record("archive unknown identity", catalog(archives: inventory), false)

    func cache(_ category: String = "Index.noindex", age: Double = 601, issues: Int = 0, bytes: Int64 = 100) -> DerivedCache {
      DerivedCache(path: DerivedData.root.appendingPathComponent("OxyLabelFixture/" + category).path,
        project: "fixture", workspace: "/fixture", category: category, bytes: bytes,
        modified: date.addingTimeInterval(-age), issues: issues)
    }
    record("derived idle index", catalog(derived: [cache()]), true)
    record("derived idle intermediates", catalog(derived: [cache("Build/Intermediates.noindex")]), true)
    record("derived logs review", catalog(derived: [cache("Logs")]), true)
    XCTAssertEqual(catalog(derived: [cache("Logs")]).first?.group, .review)
    record("derived recent boundary", catalog(derived: [cache(age: 600)]), false)
    record("derived traversal error", catalog(derived: [cache(issues: 1)]), false)
    record("derived empty", catalog(derived: [cache(bytes: 0)]), false)
    record("derived unknown category", catalog(derived: [cache("SourcePackages")]), false)
    record("derived missing timestamp", catalog(derived: [cache()], checked: false), false)
    record("derived source error", catalog(derived: [cache()], derivedIssue: "offline"), false)
    record("derived excluded parent", catalog(exclusions: [DerivedData.root.path], derived: [cache()]), false)

    for (state, available, valid, expected) in [
      ("Shutdown", false, true, true), ("Booted", false, true, false),
      ("Creating", false, true, false), ("Shutdown", true, true, false),
      ("Shutdown", false, false, false)
    ] {
      var sim = SimulatorInventory()
      sim.devices = [SimulatorDevice(udid: valid ? UUID().uuidString : "bad", name: "fixture", state: state, isAvailable: available)]
      record("device \(state) available=\(available) valid=\(valid)", catalog(simulators: sim), expected)
    }
    var sim = SimulatorInventory()
    sim.devices = [SimulatorDevice(udid: UUID().uuidString, name: "fixture", state: "Shutdown", isAvailable: false)]
    record("device source unavailable", catalog(simulators: sim, simulatorIssue: "offline"), false)
    record("device not inspected", catalog(checked: false, simulators: sim), false)
    for (days, state, deletable, expected) in [(90, "Ready", true, true), (89, "Ready", true, false), (90, "Ready", false, false), (90, "Deleting", true, false)] {
      sim.devices = []
      sim.runtimes = [SimulatorRuntime(identifier: UUID().uuidString, runtimeIdentifier: "fixture",
        version: "1", build: "1", state: state, deletable: deletable, sizeBytes: 100,
        lastUsedAt: ISO8601DateFormatter().string(from: date.addingTimeInterval(-Double(days)*86400)))]
      record("runtime days=\(days) state=\(state) deletable=\(deletable)", catalog(simulators: sim), expected)
    }
    var tp=0, fp=0, tn=0, fn=0
    for (label, actual, expected) in cases {
      XCTAssertEqual(actual, expected, label)
      if expected { if actual { tp += 1 } else { fn += 1 } }
      else { if actual { fp += 1 } else { tn += 1 } }
    }
    print("SMART_DEVELOPMENT_QUALITY fixtures=\(cases.count) TP=\(tp) FP=\(fp) TN=\(tn) FN=\(fn)")
  }

  func testComponentBoundariesAndRetainedParentProtection() {
    XCTAssertEqual(SpaceEstimate.disjointPaths(["/a", "/a/file", "/ab/file", "/a-x", "/a/../a", "/z"]), ["/a", "/a-x", "/ab/file", "/z"])
    XCTAssertEqual(SpaceEstimate.disjointPaths(["/", "/a/b"]), ["/"])
    let preview = RecommendationPreview([
      item("folder", path: "/a"), item("neighbour", path: "/ab", bytes: 200),
      item("duplicate", path: "/copy", retained: ["/a/keep"])
    ])
    XCTAssertFalse(preview.objects.contains { $0.id == "folder" })
    XCTAssertEqual(preview.knownLogicalBytes, 300)
    XCTAssertEqual(preview.rejectedCount, 1)
  }

}
