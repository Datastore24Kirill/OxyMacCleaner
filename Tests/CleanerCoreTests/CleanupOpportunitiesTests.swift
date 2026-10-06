import XCTest

@testable import CleanerCore

final class CleanupOpportunitiesTests: XCTestCase {
  func testArchiveSummaryHonorsRetentionPinsExclusionsAndCompleteness() {
    var inventory = ArchiveInventory()
    inventory.complete = true
    inventory.archives = (1...4).map {
      XcodeArchive(
        path: "/Archives/\($0).xcarchive", name: "App", bundleID: "app", team: "A",
        version: "1", build: "\($0)", created: Date(timeIntervalSince1970: Double($0)),
        bytes: 100, dsymCount: 1, issues: [])
    }
    let result = CleanupOpportunities.archives(
      inventory, keep: 1,
      pinned: ["/Archives/1.xcarchive"], exclusions: ["/Archives/2.xcarchive/dSYMs"])
    XCTAssertEqual(result, OpportunitySummary(count: 1, bytes: 100))
    inventory.complete = false
    XCTAssertEqual(
      CleanupOpportunities.archives(inventory, keep: 1, pinned: [], exclusions: []),
      OpportunitySummary(count: 0, bytes: nil))
  }
  func testDuplicateEstimateKeepsOneAndRejectsProtectedExcludedAndRepeatedFiles() {
    func file(_ name: String, _ inode: UInt64) -> FileRecord {
      FileRecord(
        path: "/Users/test/Downloads/" + name, bytes: 100, allocated: 100,
        modified: .distantPast, inode: inode, device: 1, links: 1)
    }
    let a = file("a.zip", 1)
    let b = file("b.zip", 2)
    let c = file("c.zip", 3)
    let key = file("key.p12", 4)
    XCTAssertEqual(
      CleanupOpportunities.duplicates([[a, b, c, key], [a, b]], exclusions: [c.path]),
      OpportunitySummary(count: 1, bytes: 100))
    XCTAssertEqual(
      CleanupOpportunities.duplicates([[a, key]], exclusions: []),
      OpportunitySummary(count: 0, bytes: 0))
  }
  func testDerivedSummaryRejectsRecentUnknownIncompleteAndExcludedCaches() {
    let now = Date()
    func cache(_ name: String, age: Double = 1000, issues: Int = 0, category: String = "Logs")
      -> DerivedCache
    {
      DerivedCache(
        path: DerivedData.root.appendingPathComponent(name + "/" + category).path,
        project: name, workspace: "/project", category: category, bytes: 100,
        modified: now.addingTimeInterval(-age), issues: issues)
    }
    let excluded = cache("excluded")
    let result = CleanupOpportunities.derived(
      [
        cache("old"), cache("fresh", age: 30),
        cache("broken", issues: 1), cache("unknown", category: "SourcePackages"), excluded,
      ],
      exclusions: [excluded.path], now: now)
    XCTAssertEqual(result, OpportunitySummary(count: 1, bytes: 100))
  }
  func testSimulatorSummaryProtectsBusyAndUnknownLastUseAndReportsUnknownDeviceSize() {
    let id = "11111111-1111-1111-1111-111111111111"
    let runtimeID = "22222222-2222-2222-2222-222222222222"
    var inventory = SimulatorInventory()
    inventory.devices = [
      SimulatorDevice(udid: id, name: "Phone", state: "Booted", isAvailable: false, runtime: "r")
    ]
    inventory.runtimes = [
      SimulatorRuntime(
        identifier: runtimeID, runtimeIdentifier: "r",
        version: "17", build: "A", state: "Ready", deletable: true, sizeBytes: 500,
        lastUsedAt: "2020-01-01T00:00:00Z")
    ]
    XCTAssertEqual(CleanupOpportunities.simulators(inventory).count, 0)
    inventory.devices = [
      SimulatorDevice(udid: id, name: "Phone", state: "Shutdown", isAvailable: false, runtime: "r")
    ]
    XCTAssertEqual(
      CleanupOpportunities.simulators(inventory), OpportunitySummary(count: 2, bytes: nil))
    inventory.devices = []
    XCTAssertEqual(
      CleanupOpportunities.simulators(inventory), OpportunitySummary(count: 1, bytes: 500))
    inventory.runtimes = [
      SimulatorRuntime(
        identifier: runtimeID, runtimeIdentifier: "r",
        version: "17", build: "A", state: "Ready", deletable: true, sizeBytes: 500, lastUsedAt: nil)
    ]
    XCTAssertEqual(CleanupOpportunities.simulators(inventory).count, 0)
  }
}
