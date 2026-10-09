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
  public enum Signal: String, CaseIterable, Sendable {
    case requirement, changedDecision, restriction, pending, testEvidence
    public func title(russian: Bool) -> String {
      switch self {
      case .requirement: return russian ? "Требования" : "Requirements"
      case .changedDecision: return russian ? "Изменения решений" : "Changed decisions"
      case .restriction: return russian ? "Запреты" : "Restrictions"
      case .pending: return russian ? "Незавершённые задачи" : "Pending work"
      case .testEvidence: return russian ? "Результаты тестов" : "Test evidence"
      }
    }
  }
  public static func signals(in text: String) -> [Signal] {
    let value = text.lowercased()
    func contains(_ words: [String]) -> Bool { words.contains { value.contains($0) } }
    var result: [Signal] = []
    if contains(["пользователь:", "user:", "message (user)", "требован", "requirement"]) { result.append(.requirement) }
    if contains(["отменя", "отменить", "отменён", "отменен", "отмена", "cancel the", "cancel my", "withdraw", "уточня", "вместо", "больше не", "изменил решение", "instead", "supersed", "changed my mind", "revoke"]) { result.append(.changedDecision) }
    if contains(["не удал", "запрещ", "never delete", "do not delete", "don't delete", "must not"]) { result.append(.restriction) }
    if contains(["следующий шаг", "не выполнен", "не проверен", "не опубликован", "next step", "not completed", "not verified", "pending", "todo"]) { result.append(.pending) }
    if contains(["failed", "passed", "тест падает", "тест не прош", "тест прош"]) { result.append(.testEvidence) }
    return result
  }
  public struct Finding: Sendable, Identifiable {
    public let offset: Int
    public let excerpt: String
    public let signals: [Signal]
    public var id: Int { offset }
    /// A citation alone is not evidence that the text survived editing or selection.
    /// Only this displayed, possibly shortened fragment is checked, not the entire record.
    public func fragmentPresent(in result: String) -> Bool {
      result.contains(ContextSafety.redact(excerpt))
    }
  }
  public struct Attribution: Sendable {
    public let author: String?
    public let project: String?
    public let body: String
  }
  /// Only explicit leading labels; quoted role words inside content do not identify its author.
  public static func attribution(_ excerpt: String) -> Attribution {
    var body = excerpt.replacingOccurrences(of: #"^\[L[0-9]+\]\s*"#, with: "", options: .regularExpression)
    var author: String?
    for (label, role) in [("MESSAGE (user):", "user"), ("MESSAGE (assistant):", "assistant"), ("User:", "user"), ("Пользователь:", "user"), ("Assistant:", "assistant"), ("Ассистент:", "assistant"), ("Tool:", "tool")] {
      if body.lowercased().hasPrefix(label.lowercased()) {
        author = role; body = String(body.dropFirst(label.count)).trimmingCharacters(in: .whitespaces); break
      }
    }
    if body.hasPrefix("RECORD (") { author = "record" }
    var project: String?
    // Optional explicit export label. Do not infer project ownership from arbitrary paths in prose.
    if body.hasPrefix("[project="), let end = body.firstIndex(of: "]") {
      let value = String(body[body.index(body.startIndex, offsetBy: 9)..<end])
      if !value.isEmpty { project = value }
      body = String(body[body.index(after: end)...]).trimmingCharacters(in: .whitespaces)
    } else if let data = body.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let cwd = object["cwd"] as? String, !cwd.isEmpty {
      project = cwd
    }
    return Attribution(author: author, project: project, body: body)
  }
  /// Candidate pairs, not semantic verdicts. Matching uses shared literal identifiers.
  public struct DecisionPair: Sendable, Identifiable {
    public let earlier: Finding
    public let later: Finding
    public let sharedTerms: [String]
    public var id: String { "\(earlier.offset):\(later.offset)" }
    public var attributionKnown: Bool {
      let a = TranscriptReview.attribution(earlier.excerpt)
      let b = TranscriptReview.attribution(later.excerpt)
      return a.author == "user" && b.author == "user" && a.project != nil && a.project == b.project
    }
  }
  public static func decisionPairs(in items: [Finding]) -> [DecisionPair] {
    let stop: Set<String> = ["user", "пользователь", "requirement", "требование", "delete", "удалить", "удаление", "never", "instead", "только", "вместо", "отменяю", "следующий", "проверить", "please", "нужно", "будет", "теперь", "после", "before", "after", "with", "this", "that", "must", "request", "earlier", "cancel", "content", "message", "input", "output", "text", "type", "payload", "assistant", "role", "project", "session", "timestamp"]
    func terms(_ text: String) -> Set<String> {
      // Drop the source citation so different lines cannot match through L123.
      let body = attribution(text).body
      return Set(body.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 4 && !stop.contains($0) && $0.rangeOfCharacter(from: .letters) != nil })
    }
    let ordered = items.sorted { $0.offset < $1.offset }
    var result: [DecisionPair] = []
    for (index, later) in ordered.enumerated() where later.signals.contains(.changedDecision) || later.signals.contains(.restriction) {
      let laterContext = attribution(later.excerpt)
      guard laterContext.author == nil || laterContext.author == "user" else { continue }
      let laterTerms = terms(later.excerpt)
      for earlier in ordered[..<index].reversed() {
        guard earlier.signals.contains(.requirement) || earlier.signals.contains(.changedDecision) || earlier.signals.contains(.restriction) else { continue }
        let earlierContext = attribution(earlier.excerpt)
        guard earlierContext.author == nil || earlierContext.author == "user" else { continue }
        if let a = earlierContext.project, let b = laterContext.project, a != b { continue }
        let shared = terms(earlier.excerpt).intersection(laterTerms).sorted()
        guard !shared.isEmpty else { continue }
        result.append(DecisionPair(earlier: earlier, later: later, sharedTerms: shared))
        break // nearest earlier matching signal, never choose an authoritative decision
      }
      if result.count == 50 { break }
    }
    return result
  }
  public struct Findings: Sendable {
    public let items: [Finding]
    public let matches: Int
    public let shortenedRecords: Int
    public let skipped: Int
    public let nextOffset: Int?
  }
  public func reviewIndex(after: Int? = nil, cancellation: Cancellation = Cancellation(), progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> Findings {
    var items: [Finding] = []; var matches = 0; var shortened = 0; var skipped = 0; var remaining = 0
    var prefix = Data(); var lineStart = 0; var lineLength = 0; var offset = 0
    func finish() {
      if lineLength > 64_000 { shortened += 1 }
      // A capped prefix can end inside a UTF-8 codepoint; decoding replaces only that boundary.
      let text = String(decoding: prefix, as: UTF8.self)
      let signals = Self.signals(in: text)
      if !signals.isEmpty {
        matches += 1
        if let after, lineStart <= after { skipped += 1 }
        else {
          remaining += 1
          if items.count < 200 { items.append(Finding(offset: lineStart, excerpt: String(text.prefix(700)), signals: signals)) }
        }
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
    return Findings(items: items, matches: matches, shortenedRecords: shortened, skipped: skipped, nextOffset: remaining > items.count ? items.last?.offset : nil)
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
