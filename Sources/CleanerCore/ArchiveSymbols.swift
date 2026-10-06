import Foundation

/// Reads only bounded Mach-O headers and load commands, never executes archive binaries.
public enum MachOUUIDs {
  public struct Slice: Hashable, Codable, Sendable {
    public let cpu: UInt32
    public let uuid: String
  }
  public static func read(_ url: URL, expectedType: UInt32? = nil) throws -> Set<Slice>? {
    let record = try FileRecord.read(url)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let size = UInt64(record.bytes)
    func bytes(_ offset: UInt64, _ count: Int) throws -> [UInt8] {
      guard count >= 0, count <= 16_777_216, offset <= size, UInt64(count) <= size - offset else {
        throw CleanerError.message("Invalid Mach-O bounds: " + url.lastPathComponent)
      }
      try handle.seek(toOffset: offset)
      let data = try handle.read(upToCount: count) ?? Data()
      guard data.count == count else { throw CleanerError.message("Truncated Mach-O") }
      return Array(data)
    }
    func number(_ b: [UInt8], _ offset: Int, _ count: Int = 4, _ little: Bool = false) -> UInt64 {
      let values = b[offset..<(offset + count)]
      return (little ? Array(values.reversed()) : Array(values)).reduce(0) {
        ($0 << 8) | UInt64($1)
      }
    }
    guard size >= 4 else { return nil }
    let magic = number(try bytes(0, 4), 0)
    let thin: Set<UInt64> = [0xfeed_face, 0xcefa_edfe, 0xfeed_facf, 0xcffa_edfe]
    let fat: Set<UInt64> = [0xcafe_babe, 0xbeba_feca, 0xcafe_babf, 0xbfba_feca]
    guard thin.contains(magic) || fat.contains(magic) else { return nil }
    var ranges: [(UInt64, UInt64)] = [(0, size)]
    if fat.contains(magic) {
      let little = magic == 0xbeba_feca || magic == 0xbfba_feca
      let wide = magic == 0xcafe_babf || magic == 0xbfba_feca
      let count = number(try bytes(0, 8), 4, 4, little)
      guard count > 0 && count <= 64 else {
        throw CleanerError.message("Invalid Mach-O slice count")
      }
      let stride = wide ? 32 : 20
      let table = try bytes(8, Int(count) * stride)
      ranges = []
      for i in 0..<Int(count) {
        let start = number(table, i * stride + 8, wide ? 8 : 4, little)
        let length = number(table, i * stride + (wide ? 16 : 12), wide ? 8 : 4, little)
        guard start >= UInt64(8 + table.count), start <= size, length <= size - start,
          !ranges.contains(where: { start < $0.0 + $0.1 && $0.0 < start + length })
        else {
          throw CleanerError.message("Invalid or overlapping Mach-O slices")
        }
        ranges.append((start, length))
      }
    }
    var result = Set<Slice>()
    for (offset, length) in ranges {
      guard length >= 28 else { throw CleanerError.message("Truncated Mach-O slice") }
      let header = try bytes(offset, 28)
      let magic = number(header, 0)
      guard thin.contains(magic) else { throw CleanerError.message("Unsupported Mach-O slice") }
      let little = magic == 0xcefa_edfe || magic == 0xcffa_edfe
      let headerSize: UInt64 = (magic == 0xfeed_facf || magic == 0xcffa_edfe) ? 32 : 28
      if let expectedType, number(header, 12, 4, little) != UInt64(expectedType) {
        throw CleanerError.message("Unexpected Mach-O file type")
      }
      let cpu = UInt32(number(header, 4, 4, little))
      let count = number(header, 16, 4, little)
      let commandsSize = number(header, 20, 4, little)
      guard count <= 65536, headerSize <= length, commandsSize <= length - headerSize else {
        throw CleanerError.message("Invalid Mach-O commands")
      }
      let commands = try bytes(offset + headerSize, Int(commandsSize))
      var position = 0
      var found: Slice?
      for _ in 0..<count {
        guard position <= commands.count - 8 else {
          throw CleanerError.message("Truncated load command")
        }
        let kind = number(commands, position, 4, little)
        let commandSize = number(commands, position + 4, 4, little)
        guard commandSize >= 8, commandSize <= UInt64(commands.count - position) else {
          throw CleanerError.message("Invalid load command size")
        }
        if kind == 0x1b {
          guard commandSize == 24, found == nil else {
            throw CleanerError.message("Invalid LC_UUID")
          }
          let uuid = commands[(position + 8)..<(position + 24)].map { String(format: "%02X", $0) }
            .joined()
          guard uuid != String(repeating: "0", count: 32) else {
            throw CleanerError.message("Empty UUID")
          }
          found = Slice(cpu: cpu, uuid: uuid)
        }
        position += Int(commandSize)
      }
      guard position == commands.count, let found else {
        throw CleanerError.message("Missing UUID or invalid load commands")
      }
      result.insert(found)
    }
    try record.validate()
    return result
  }
}

public struct ArchiveSymbolReport: Sendable {
  public let binaries: Int
  public let matched: Int
  public let missing: [String]
  public let issues: [String]
  public var complete: Bool {
    binaries > 0 && matched == binaries && missing.isEmpty && issues.isEmpty
  }
}
public enum ArchiveSymbols {
  public static func inspect(_ root: URL, cancellation: Cancellation = Cancellation()) throws
    -> ArchiveSymbolReport
  {
    guard root.pathExtension == "xcarchive",
      root.resolvingSymlinksInPath() == root.standardizedFileURL
    else {
      throw CleanerError.message("Select a local archive without symbolic links")
    }
    func plist(_ url: URL) throws -> [String: Any] {
      let file = try FileRecord.read(url)
      guard file.bytes < 4_000_000 else { throw CleanerError.message("Metadata too large") }
      let result =
        try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: Any] ?? [:]
      try file.validate()
      return result
    }
    let metadata = try plist(root.appendingPathComponent("Info.plist"))
    guard let properties = metadata["ApplicationProperties"] as? [String: Any],
      let relative = properties["ApplicationPath"] as? String,
      !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."),
      relative.hasSuffix(".app")
    else {
      throw CleanerError.message("Main application path is missing or invalid")
    }
    let application = root.appendingPathComponent("Products").appendingPathComponent(relative)
    guard application.resolvingSymlinksInPath() == application.standardizedFileURL else {
      throw CleanerError.message("Main application path contains links")
    }
    let macLayout = FileManager.default.fileExists(
      atPath: application.appendingPathComponent("Contents/Info.plist").path)
    let info = try plist(
      application.appendingPathComponent(macLayout ? "Contents/Info.plist" : "Info.plist"))
    guard let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
      !executable.contains("/"), executable != ".", executable != ".."
    else {
      throw CleanerError.message("Main executable is missing")
    }
    let main = application.appendingPathComponent(
      macLayout ? "Contents/MacOS/" + executable : executable)
    guard try MachOUUIDs.read(main, expectedType: 2) != nil else {
      throw CleanerError.message("Main executable is not Mach-O")
    }
    var binaries: [(String, Set<MachOUUIDs.Slice>)] = []
    var symbols = Set<MachOUUIDs.Slice>()
    var issues: [String] = []
    for folder in ["Products", "dSYMs"] {
      let base = root.appendingPathComponent(folder)
      let baseValues = try base.resourceValues(forKeys: [
        .isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
      ])
      guard baseValues.isDirectory == true, baseValues.isSymbolicLink != true,
        baseValues.isUbiquitousItem != true
      else {
        throw CleanerError.message("Archive content directory is not local or contains links")
      }
      var traversalError: Error?
      guard
        let enumerator = FileManager.default.enumerator(
          at: base, includingPropertiesForKeys: nil,
          errorHandler: { _, error in
            traversalError = error
            return false
          })
      else {
        issues.append("Cannot read " + folder)
        continue
      }
      for case let url as URL in enumerator {
        try cancellation.check()
        do {
          let values = try url.resourceValues(forKeys: [
            .isSymbolicLinkKey, .isUbiquitousItemKey, .isRegularFileKey,
          ])
          guard values.isSymbolicLink != true, values.isUbiquitousItem != true else {
            enumerator.skipDescendants()
            throw CleanerError.message("Skipped link/cloud object")
          }
          guard values.isRegularFile == true else { continue }
          if folder == "dSYMs" && !url.path.contains(".dSYM/Contents/Resources/DWARF/") { continue }
          if let uuids = try MachOUUIDs.read(url, expectedType: folder == "dSYMs" ? 10 : nil) {
            if folder == "Products" {
              binaries.append((String(url.path.dropFirst(root.path.count + 1)), uuids))
            } else {
              symbols.formUnion(uuids)
            }
          }
        } catch {
          if issues.count < 20 {
            issues.append(url.lastPathComponent + ": " + error.localizedDescription)
          }
        }
      }
      if let traversalError { issues.append(traversalError.localizedDescription) }
    }
    let missing = binaries.filter { !$0.1.isSubset(of: symbols) }.map(\.0)
    return ArchiveSymbolReport(
      binaries: binaries.count, matched: binaries.count - missing.count, missing: missing,
      issues: issues)
  }
}
