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
  /// Bounded, local review index. Signals require human interpretation, never override decisions.
  public struct Finding: Sendable, Identifiable {
    public let offset: Int
    public let excerpt: String
    public var id: Int { offset }
  }
  public struct Findings: Sendable {
    public let items: [Finding]
    public let matches: Int
    public let shortenedRecords: Int
  }
  public func reviewIndex(cancellation: Cancellation = Cancellation(), progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> Findings {
    var items: [Finding] = []; var matches = 0; var shortened = 0
    var prefix = Data(); var lineStart = 0; var lineLength = 0; var offset = 0
    func finish() {
      if lineLength > 64_000 { shortened += 1 }
      // A capped prefix can end inside a UTF-8 codepoint; decoding replaces only that boundary.
      let text = String(decoding: prefix, as: UTF8.self)
      if Self.hasReviewSignal(text) {
        matches += 1
        if items.count < 200 { items.append(Finding(offset: lineStart, excerpt: String(text.prefix(700)))) }
      }
      prefix.removeAll(keepingCapacity: true); lineLength = 0
    }
    while offset < total {
      try cancellation.check()
      let chunk = try bytes(at: offset, count: 128_000)
      guard !chunk.isEmpty else { throw CleanerError.message("History snapshot ended unexpectedly") }
      var begin = chunk.startIndex
      for index in chunk.indices where chunk[index] == 10 {
        let length = index - begin
        prefix.append(chunk[begin..<min(index, begin + max(0, 64_000 - prefix.count))])
        lineLength += length; finish(); lineStart = offset + index + 1; begin = index + 1
      }
      prefix.append(chunk[begin..<min(chunk.endIndex, begin + max(0, 64_000 - prefix.count))])
      lineLength += chunk.endIndex - begin
      offset += chunk.count; progress(offset, total)
    }
    try cancellation.check()
    if lineLength > 0 { finish() }
    return Findings(items: items, matches: matches, shortenedRecords: shortened)
  }
  private static func hasReviewSignal(_ text: String) -> Bool {
    let value = text.lowercased()
    let phrases = ["отменя", "отменить", "уточня", "вместо", "больше не", "не удал", "запрещ", "изменил решение", "never delete", "do not delete", "don't delete", "instead", "supersed", "changed my mind", "test failed", "tests failed", "tests passed"]
    return phrases.contains { value.contains($0) }
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
