import Foundation
import Darwin
@testable import CleanerCore
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let journalURL = root.appendingPathComponent("interrupted.jsonl")
if CommandLine.arguments[2] == "write" {
  let journal = try ScanJournal(url: journalURL, roots: [root], volumeID: "crash-test")
  for i in 0..<300 {
    try journal.append(FileRecord(path: root.path + "/file-\(i)", bytes: 1, allocated: 1, modified: Date(), inode: UInt64(i), device: 1, links: 1))
  }
  _exit(9) // Simulate abrupt termination: no flush or deinit of pending records.
}
let saved = try ScanJournal.recover(journalURL)!
guard saved.report.files.count == 256, !saved.report.complete else { fatalError("Crash recovery mismatch") }
print("PASS: abrupt process exit recovered 256 durable records; pending 44 absent, marked partial")
