import Foundation
import CleanerCore
let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let disk = URL(fileURLWithPath: CommandLine.arguments[2])
let source = root.appendingPathComponent("source")
try Data(repeating: 17, count: 32_000_000).write(to: source)
let store = try QuarantineStore(root: root.appendingPathComponent("q"))
let entry = try store.move(FileRecord.read(source))
let filler = disk.appendingPathComponent("fixture-fill")
fm.createFile(atPath: filler.path, contents: nil)
let handle = try FileHandle(forWritingTo: filler)
let block = Data(repeating: 23, count: 1_000_000)
while (try disk.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0) > 15_000_000 { do { try handle.write(contentsOf: block); try handle.synchronize() } catch { break } }
try handle.close()
do { try store.relocate(entry, to: disk); fatalError("Expected insufficient space") }
catch { let e = error as NSError; guard error.localizedDescription.contains("Insufficient space") || e.code == 640 || e.code == 28 else { throw error } }
guard store.inspect(entry).payloadValid, store.entries().first?.externalPayload == nil else { fatalError("Original lost") }
try fm.removeItem(at: filler)
try store.relocate(entry, to: disk)
try store.restore(store.entries()[0])
guard try Data(contentsOf: source).count == 32_000_000 else { fatalError("Restore failed") }
print("PASS: real full APFS image rejects copy, source remains verified; freed destination then relocates and restores successfully")
