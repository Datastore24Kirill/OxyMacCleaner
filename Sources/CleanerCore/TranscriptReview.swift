import Foundation

public struct ReviewPage: Sendable {
  public let text: String
  public let offset: Int
  public let next: Int
  public let total: Int
  public var reviewLines: [String] {
    text.components(separatedBy: "\n").filter {
      let line = $0.lowercased()
      return ["отмен", "уточн", "запрет", "не удал", "failed", "passed", "never", "instead", "supersed"].contains { line.contains($0) }
    }.prefix(20).map { String($0.prefix(500)) }
  }
}
public final class TranscriptReview: @unchecked Sendable {
  private let transcript: Transcript
  private let memory: Data?
  private let file: URL?
  public let total: Int
  public init(_ transcript: Transcript) throws {
    self.transcript = transcript
    if let streaming = transcript.streaming {
      file = streaming.numbered; memory = nil
      total = (try FileManager.default.attributesOfItem(atPath: streaming.numbered.path)[.size] as? NSNumber)?.intValue ?? 0
    } else { let data = Data(transcript.numbered.utf8); memory = data; file = nil; total = data.count }
  }
  private func bytes(at offset: Int, count: Int) throws -> Data {
    if let memory { return memory.subdata(in: offset..<min(total, offset + count)) }
    let handle = try FileHandle(forReadingFrom: file!); defer { try? handle.close() }
    try handle.seek(toOffset: UInt64(offset)); return try handle.read(upToCount: count) ?? Data()
  }
  public func page(at offset: Int = 0, limit: Int = 64_000) throws -> ReviewPage {
    guard offset >= 0, offset <= total, limit >= 4 else { throw CleanerError.message("Invalid history page") }
    var data = try bytes(at: offset, count: limit)
    while !data.isEmpty && String(data: data, encoding: .utf8) == nil { data.removeLast() }
    guard !data.isEmpty || offset == total else { throw CleanerError.message("Invalid history text boundary") }
    return ReviewPage(text: String(decoding: data, as: UTF8.self), offset: offset, next: offset + data.count, total: total)
  }
  public func find(_ text: String, from start: Int = 0, cancellation: Cancellation = Cancellation()) throws -> Int? {
    let query = Data(text.utf8)
    guard !query.isEmpty, query.count <= 4096, start >= 0, start <= total else { return nil }
    var offset = start
    while offset < total {
      try cancellation.check()
      let data = try bytes(at: offset, count: 128_000)
      if let range = data.range(of: query) { return offset + range.lowerBound }
      if data.count < 128_000 { return nil }
      offset += data.count - query.count + 1
    }
    return nil
  }
}
