import Foundation
@testable import CleanerCore

// In-memory metadata only: no filesystem scan, deletion, or user paths.
let count = Int(CommandLine.arguments.dropFirst().first ?? "10000")!
let now = Date(timeIntervalSince1970: 1_800_000_000)
let home = URL(fileURLWithPath: "/Users/benchmark-fixture")
var files: [FileRecord] = []
for i in 0..<count {
  files.append(FileRecord(path: home.path + "/Downloads/item-\(i).dmg", bytes: 600_000_000,
    allocated: 600_000_000, modified: now.addingTimeInterval(-200 * 86400),
    inode: UInt64(i+1), device: 1, links: 1))
}
let start = Date()
let candidates = CleanupAdvisor.candidates(files: files, home: home, exclusions: [], now: now)
let classified = Date()
let catalog = SmartRecommendations.catalog(personal: candidates, snapshotDate: now,
  archives: ArchiveInventory(), archiveDate: nil, keep: 3, pinned: [], derived: [],
  derivedDate: nil, derivedIssue: nil, duplicates: [], duplicateDate: nil,
  projects: [], projectDate: nil, projectIssue: nil, worktrees: [], worktreeDate: nil,
  worktreeIssue: nil, simulators: SimulatorInventory(), simulatorDate: nil,
  simulatorIssue: nil, testDevices: [], testDate: nil, testIssue: nil,
  exclusions: [], russian: false, now: now)
let built = Date()
let preview = RecommendationPreview(catalog)
let finished = Date()
precondition(catalog.count == count && preview.objects.count == count)
precondition(preview.knownLogicalBytes == Int64(count) * 600_000_000)
print("RECOMMENDATIONS_BENCH count=\(count) classify=\(classified.timeIntervalSince(start)) catalog=\(built.timeIntervalSince(classified)) preview=\(finished.timeIntervalSince(built)) total=\(finished.timeIntervalSince(start))")
