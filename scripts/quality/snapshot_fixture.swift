import Foundation
import Darwin
@testable import CleanerCore
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("OxySnapshotQA-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: root) }
var report = ScanReport(); report.complete = true
for i in 0..<1_000_000 {
  let parent = root.path + "/files/" + String(i / 1000)
  report.files.append(FileRecord(path: parent + "/" + String(i) + ".txt", bytes: 7, allocated: 4096, modified: Date(timeIntervalSince1970: 100), inode: UInt64(i), device: 1, links: 1))
  report.folders[parent, default: 0] += 7
}
let store = ScanStore(url: root.appendingPathComponent("snapshot"))
let start = Date()
try store.save(SavedScan(roots: [root], volumeID: "synthetic", report: report, progress: ScanProgress()))
print("Save seconds:", Date().timeIntervalSince(start))
let loading = Date()
let restored = try store.load()!
guard restored.report.files == report.files, restored.report.folders == report.folders else { fatalError("Snapshot mismatch") }
let index = DiskIndex(report: restored.report)
guard index.children.values.reduce(0, { $0 + $1.filter { !$0.directory }.count }) == 1_000_000 else { fatalError("Index mismatch") }
print("Load and index seconds:", Date().timeIntervalSince(loading))
print("PASS: million metadata records saved, restored and indexed; no real user files")
