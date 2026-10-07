import CryptoKit
import Foundation

/// Owns private temporary snapshots; releasing the transcript removes only these copies.
public final class StreamingHistory: @unchecked Sendable {
  public let bytes: Int64
  public let digest: String
  public let report: NativeHistory.Result
  let directory: URL
  let original: URL
  let numbered: URL
  deinit { try? FileManager.default.removeItem(at: directory) }
  private init(directory: URL, bytes: Int64, digest: String, report: NativeHistory.Result) {
    self.directory = directory; self.bytes = bytes; self.digest = digest; self.report = report
    original = directory.appendingPathComponent("original.jsonl")
    numbered = directory.appendingPathComponent("numbered.txt")
  }
  public static func load(_ source: URL, agent: String, cancellation: Cancellation = Cancellation(),
    progress: @Sendable (Int64, Int64) -> Void = { _, _ in }) throws -> StreamingHistory {
    let record = try FileRecord.read(source)
    guard record.bytes > 0, record.bytes <= 1_000_000_000, source.pathExtension.lowercased() == "jsonl" else {
      throw CleanerError.message("Choose a nonempty JSONL history up to 1 GB")
    }
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("OxyHistory-" + UUID().uuidString)
    try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var success = false
    defer { if !success { try? fm.removeItem(at: directory) } }
    let original = directory.appendingPathComponent("original.jsonl")
    let numbered = directory.appendingPathComponent("numbered.txt")
    let hash = try copy(source, to: original, cancellation: cancellation) { done in progress(done, record.bytes * 2) }
    try record.validate()
    guard fm.createFile(atPath: numbered.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
      throw CleanerError.message("Cannot create private history snapshot")
    }
    let output = try FileHandle(forWritingTo: numbered)
    defer { try? output.close() }
    let reader = try HistoryLineReader(original)
    var validator = NativeHistory.Validator(agent: agent)
    var index = 0
    while let line = try reader.next(cancellation: cancellation) {
      if let labeled = try validator.consume(line, index: index) {
        try output.write(contentsOf: Data((labeled + "\n").utf8))
      }
      index += 1
      if index % 256 == 0 { progress(record.bytes + reader.consumed, record.bytes * 2) }
    }
    let report = try validator.finish()
    try cancellation.check()
    progress(record.bytes * 2, record.bytes * 2)
    success = true
    return StreamingHistory(directory: directory, bytes: record.bytes, digest: hash, report: report)
  }
  static func copy(_ source: URL, to target: URL, cancellation: Cancellation,
    progress: (Int64) -> Void = { _ in }) throws -> String {
    guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
      throw CleanerError.message("Cannot create history copy")
    }
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let output = try FileHandle(forWritingTo: target)
    defer { try? output.close() }
    var digest = SHA256(); var count: Int64 = 0
    while true {
      try cancellation.check()
      let data = try input.read(upToCount: 262144) ?? Data()
      if data.isEmpty { break }
      count += Int64(data.count)
      guard count <= 1_000_000_000 else { throw CleanerError.message("History grew beyond 1 GB") }
      digest.update(data: data)
      try output.write(contentsOf: data)
      progress(count)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
  public func backup(in folder: URL, cancellation: Cancellation) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let target = folder.appendingPathComponent(UUID().uuidString + ".jsonl")
    do {
      let copied = try Self.copy(original, to: target, cancellation: cancellation)
      guard copied == digest, try Scanner.hash(target, cancellation: cancellation) == digest else {
        throw CleanerError.message("Backup verification failed")
      }
      return target
    } catch { try? FileManager.default.removeItem(at: target); throw error }
  }
  public func chunks() throws -> HistoryChunkReader { try HistoryChunkReader(numbered) }
}

/// A bounded UTF-8 line reader; oversized single records fail explicitly, never truncate.
final class HistoryLineReader {
  let handle: FileHandle
  var buffer = Data()
  var ended = false
  var consumed: Int64 = 0
  init(_ url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
  deinit { try? handle.close() }
  func next(cancellation: Cancellation = Cancellation()) throws -> String? {
    while true {
      try cancellation.check()
      if let newline = buffer.firstIndex(of: 10) {
        let data = buffer[..<newline]
        guard data.count <= 8_388_608 else { throw CleanerError.message("JSONL record exceeds 8 MB") }
        guard let line = String(data: data, encoding: .utf8), !line.contains("\0") else {
          throw CleanerError.message("Invalid UTF-8 history")
        }
        buffer.removeSubrange(...newline)
        return line
      }
      guard buffer.count <= 8_388_608 else { throw CleanerError.message("JSONL record exceeds 8 MB") }
      if ended {
        guard !buffer.isEmpty else { return nil }
        guard let line = String(data: buffer, encoding: .utf8), !line.contains("\0") else { throw CleanerError.message("Invalid UTF-8 history") }
        buffer.removeAll(); return line
      }
      let data = try handle.read(upToCount: 65536) ?? Data()
      ended = data.isEmpty; consumed += Int64(data.count); buffer.append(data)
    }
  }
}
public final class HistoryChunkReader {
  private let reader: HistoryLineReader
  private var remaining = ""
  init(_ url: URL) throws { reader = try HistoryLineReader(url) }
  public func next(cancellation: Cancellation = Cancellation()) throws -> String? {
    var chunk = ""
    var count = 0
    while count < 12000 {
      try cancellation.check()
      if remaining.isEmpty {
        guard let line = try reader.next(cancellation: cancellation) else { break }
        remaining = line + "\n"
      }
      let end = remaining.index(remaining.startIndex, offsetBy: 12000 - count, limitedBy: remaining.endIndex) ?? remaining.endIndex
      let part = remaining[..<end]; chunk += part; count += part.count
      remaining = String(remaining[end...])
    }
    return chunk.isEmpty ? nil : chunk
  }
}
