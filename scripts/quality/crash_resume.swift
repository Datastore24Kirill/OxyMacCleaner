import Foundation
import Darwin
import CleanerCore
let root = URL(fileURLWithPath: CommandLine.arguments[2])
let files = root.appendingPathComponent("files")
let journalURL = root.appendingPathComponent("journal.jsonl")
let mode = CommandLine.arguments[1]
if mode == "crash" {
  let journal = try ScanJournal(url: journalURL, roots: [files], volumeID: "fixture", excluded: [])
  var completed = 0
  _ = Scanner.scan(roots: [files], excluded: [], cancellation: Cancellation(), record: { try journal.append($0) }, completedDirectory: {
    try journal.completeDirectory($0); completed += 1
    if completed == 3 { try journal.flush(); kill(getpid(), SIGKILL) }
  })
  fatalError("Expected intentional fixture process termination")
} else {
  guard let saved = try ScanJournal.recover(journalURL), let checkpoint = saved.report.checkpoint,
    checkpoint.completedDirectories.count == 3, saved.report.files.count == 60 else { fatalError("Recovery missing committed prefix") }
  let report = Scanner.scan(roots: [files], excluded: [], cancellation: Cancellation(), resuming: saved.report)
  guard report.complete, report.files.count == 200, report.total == 600,
    Set(report.files.map(\.path)).count == 200 else { fatalError("Resume mismatch") }
  print("PASS: SIGKILL after three committed folders; recovered 60 files; resumed to 200 unique files / 600 bytes")
}
