import Foundation
import Darwin
import CleanerCore
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("OxyLargeQA-" + UUID().uuidString).resolvingSymlinksInPath()
try fm.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: root) }
let files = root.appendingPathComponent("files")
try fm.createDirectory(at: files, withIntermediateDirectories: false)
let directories = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 100
for directory in 0..<directories {
  let folder = files.appendingPathComponent(String(directory)); try fm.createDirectory(at: folder, withIntermediateDirectories: false)
  for file in 0..<1000 { try autoreleasepool { try Data("fixture".utf8).write(to: folder.appendingPathComponent("\(file).txt")) } }
}
var usage = rusage(); getrusage(RUSAGE_SELF, &usage); print("Peak RSS after fixture creation:", usage.ru_maxrss)
let started = Date()
let report = Scanner.scan(roots: [files], excluded: [], cancellation: Cancellation())
guard report.files.count == directories * 1000, report.complete else { fatalError("Incomplete synthetic scan") }
print("\(directories * 1000)-file scan seconds:", Date().timeIntervalSince(started))
let token = Cancellation(); var visited = 0
let partial = Scanner.scan(roots: [files], excluded: [], cancellation: token, record: { _ in
  visited += 1; if visited == min(5000, directories * 500) { token.cancel() }
})
let resumeStarted = Date()
let resumed = Scanner.scan(roots: [files], excluded: [], cancellation: Cancellation(), resuming: partial)
guard resumed.complete, resumed.files.count == report.files.count, resumed.total == report.total, resumed.folders == report.folders else { fatalError("Resume accounting differs") }
getrusage(RUSAGE_SELF, &usage)
print("Resume seconds:", Date().timeIntervalSince(resumeStarted), "peak RSS:", usage.ru_maxrss)
let history = root.appendingPathComponent("large.jsonl")
fm.createFile(atPath: history.path, contents: nil)
let handle = try FileHandle(forWritingTo: history)
try handle.write(contentsOf: Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"synthetic-large\"}}\n".utf8))
let line = Data(("{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":\"" + String(repeating: "x", count: 10000) + "\"}}\n").utf8)
for _ in 0..<10000 { try handle.write(contentsOf: line) }
try handle.close()
let load = Date()
let transcript = try Transcript.loadNative(history, agent: "codex")
guard transcript.nativeHistory?.messages == 10000, transcript.streaming != nil else { fatalError("Lost records") }
let copy = try transcript.backup(in: root.appendingPathComponent("backups"))
guard try Scanner.hash(copy) == transcript.digest, try Scanner.hash(history) == transcript.digest else { fatalError("Backup mismatch") }
print("100 MB import and verified backup seconds:",Date().timeIntervalSince(load))
print("Synthetic scan/import/backup PASS; originals unchanged")
