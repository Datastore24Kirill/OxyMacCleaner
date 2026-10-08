import Foundation
import CleanerCore
let fm = FileManager.default
let mode = CommandLine.arguments[1]
let root = URL(fileURLWithPath: CommandLine.arguments[2])
let disk = URL(fileURLWithPath: CommandLine.arguments[3])
let source = root.appendingPathComponent("source")
let store = try QuarantineStore(root: root.appendingPathComponent("q"))
func require(_ ok: Bool, _ message: String) throws { if !ok { throw CleanerError.message(message) } }
switch mode {
case "prepare":
  try Data(repeating: 71, count: 128_000_000).write(to: source)
  _ = try store.move(FileRecord.read(source))
case "relocate":
  var refused = false
  do { try store.relocate(store.entries()[0], to: disk) } catch { refused = true }
  try require(refused && store.inspect(store.entries()[0]).payloadValid && store.entries()[0].externalPayload == nil, "Lost local source or missed disconnect")
  print("PASS: interrupted relocation retained verified local source")
case "online":
  try store.relocate(store.entries()[0], to: disk)
  try require(store.inspect(store.entries()[0]).payloadValid, "Relocated payload invalid")
case "restore-interrupted":
  do { try store.restore(store.entries()[0]) } catch { print("Observed interruption:", error.localizedDescription) }
  let fresh = store.entries()[0]
  if fm.fileExists(atPath: source.path) {
    try require(try Scanner.hash(source) == fresh.hash && ["restored", "restored-copy"].contains(fresh.state), "Published invalid restore")
    print("PASS: restore publication won detach race; complete verified destination remains, state", fresh.state)
  } else {
    try require(fresh.state == "quarantined", "Interrupted restore lost journal")
    print("PASS: restore interrupted before publication; quarantine retained")
  }
case "offline":
  var refused = false
  do { try store.restore(store.entries()[0]) } catch { refused = true }
  try require(refused && !fm.fileExists(atPath: source.path) && store.entries()[0].state == "quarantined", "Offline restore changed state")
  print("PASS: disconnected restore refused without publishing destination")
case "restore":
  if !fm.fileExists(atPath: source.path) { try store.restore(store.entries()[0]) }
  try require(try Data(contentsOf: source).count == 128_000_000, "Restore after reconnect failed")
  print("PASS: reconnect restores the verified payload")
case "scan":
  for i in 0..<100 { try Data("fixture".utf8).write(to: disk.appendingPathComponent("scan-\(i)")) }
  var count = 0
  let result = Scanner.scan(roots: [disk], excluded: [], cancellation: Cancellation(), record: { _ in
    count += 1
    if count == 10 {
      let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); p.arguments = ["detach", "-force", disk.path]
      try p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else { throw CleanerError.message("Fixture detach failed") }
    }
  })
  try require(!result.complete || !result.issues.isEmpty, "Disconnected scan presented as complete")
  print("PASS: disconnect during scan reports incomplete/error result; records \(result.files.count)")
default: throw CleanerError.message("Unknown fixture mode")
}
