import Foundation
import CleanerCore

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let target = URL(fileURLWithPath: CommandLine.arguments[2])
let source = root.appendingPathComponent("source")
try FileManager.default.createDirectory(at: source.appendingPathComponent("empty"), withIntermediateDirectories: true)
try Data("cross-volume-payload".utf8).write(to: source.appendingPathComponent("a.txt"))
let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
let original = try DirectoryManifest.capture(source)
let entry = try store.moveDirectory(source, expected: original)
try store.relocate(entry, to: target)
let relocated = store.entries()[0]
guard let external = relocated.externalPayload, external.hasPrefix(target.path), !FileManager.default.fileExists(atPath: source.path) else { fatalError("Relocation not published") }
try store.restore(relocated)
guard try String(contentsOf: source.appendingPathComponent("a.txt"), encoding: .utf8) == "cross-volume-payload",
  FileManager.default.fileExists(atPath: source.appendingPathComponent("empty").path),
  !FileManager.default.fileExists(atPath: external) else { fatalError("Restore failed") }
print("PASS: separate target volume, folder plus empty child, verified copy, restore, old payload removed")
