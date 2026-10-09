import Foundation

public struct ModelPullProgress: Sendable {
  public let status: String
  public let completed: Double
  public let total: Double
  public var fraction: Double? { total > 0 ? min(1, max(0, completed / total)) : nil }
  public static func parse(_ data: Data) throws -> ModelPullProgress {
    guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CleanerError.message("Invalid download progress") }
    if let error = j["error"] as? String { throw CleanerError.message(error) }
    return ModelPullProgress(status: j["status"] as? String ?? "", completed: max(0, (j["completed"] as? NSNumber)?.doubleValue ?? 0), total: max(0, (j["total"] as? NSNumber)?.doubleValue ?? 0))
  }
}

public final class LocalModel: @unchecked Sendable {
  private let session: URLSession
  public init(configuration: URLSessionConfiguration? = nil) {
    let config = configuration ?? URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 600
    config.timeoutIntervalForResource = 3600
    config.connectionProxyDictionary = [:]
    session = URLSession(configuration: config, delegate: LocalOnlyRedirect(), delegateQueue: nil)
  }
  private func request(_ endpoint: String, _ body: [String: Any]? = nil) throws -> URLRequest {
    var r = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/" + endpoint)!)
    if let body {
      r.httpMethod = "POST"
      r.setValue("application/json", forHTTPHeaderField: "Content-Type")
      r.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    return r
  }
  public func models() async throws -> [String] {
    var query = try request("tags"); query.timeoutInterval = 5
    let (data, response) = try await session.data(for: query)
    try validate(response)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    // Remote/cloud models are not eligible for local context processing.
    return (json?["models"] as? [[String: Any]] ?? []).filter {
      $0["remote_host"] == nil && $0["remote_model"] == nil
    }.compactMap { $0["name"] as? String }.filter { !$0.lowercased().contains("cloud") }
  }
  public func pull(_ name: String, progress: @escaping @Sendable (ModelPullProgress) -> Void) async throws {
    guard ["qwen2.5:3b", "qwen2.5:7b"].contains(name) else {
      throw CleanerError.message("Choose an approved local model")
    }
    let (stream, response) = try await session.bytes(
      for: request("pull", ["model": name, "stream": true]))
    try validate(response)
    var succeeded = false
    for try await line in stream.lines {
      try Task.checkCancellation()
      guard !line.isEmpty else { continue }
      let item = try ModelPullProgress.parse(Data(line.utf8))
      succeeded = item.status == "success"
      progress(item)
    }
    guard succeeded else { throw CleanerError.message("Model download interrupted before completion. Retry to resume.") }
  }
  public func generate(_ prompt: String, model: String, system: String = ContextPlan.system, json: Bool = false, schema: String? = nil) async throws -> String {
    let available = try await models()
    guard available.contains(model) else {
      throw CleanerError.message("Select an installed local model")
    }
    let (metadata, metadataResponse) = try await session.data(
      for: request("show", ["model": model]))
    try validate(metadataResponse)
    guard let details = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
      details["remote_host"] == nil, details["remote_model"] == nil,
      (details["details"] as? [String: Any])?["format"] as? String == "gguf"
    else { throw CleanerError.message("Only verified local GGUF models are allowed") }
    var body: [String: Any] = [
      "model": model, "system": system, "prompt": ContextSafety.redact(prompt), "stream": false,
      "options": ["temperature": 0.1, "num_ctx": 16384, "num_predict": json ? 4096 : 1024], "keep_alive": "5m",
    ]
    if let schema { body["format"] = try JSONSerialization.jsonObject(with: Data(schema.utf8)) }
    else if json { body["format"] = "json" }
    let r = try request("generate", body)
    let (data, response) = try await session.data(for: r)
    try validate(response)
    try Task.checkCancellation()
    let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    if let error = j?["error"] as? String { throw CleanerError.message(error) }
    guard let result = j?["response"] as? String,
      !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw CleanerError.message("Empty model response") }
    return ContextSafety.redact(result)
  }
  public func summarize(
    _ transcript: Transcript, model: String, style: String,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> String {
    let reader = try transcript.streaming?.chunks(redacting: true)
    var small = (reader == nil ? ContextPlan.chunks(ContextSafety.redact(transcript.numbered)) : []).makeIterator()
    var notes: [String] = []
    var noteBytes = 0
    var part = 0
    var previousLine: Int?
    while true {
      try Task.checkCancellation()
      let next = try reader != nil ? reader!.next() : small.next()
      guard let rawChunk = next else { break }
      let chunk = ContextSafety.labelContinuation(rawChunk, previous: &previousLine)
      part += 1
      progress("\(part)")
      let prompt = "Agent: \(transcript.agent). Compression: \(style). Select evidence references for part \(part). Preserve source line citations.\n<transcript>\n\(chunk)\n</transcript>"
      let proposal = try await generate(prompt, model: model)
      let note: String
      do {
        note = try ContextSafety.groundedExcerpt(proposal, source: chunk)
      } catch {
        // Retry only failed validation, never a transport error or cancelled request.
        try Task.checkCancellation()
        progress("\(part) · retry 1/1")
        let corrected = try await generate(
          "The previous selection had invalid citations. Return ONLY individual [Lnumber] references present at the START of lines in this part. Do not emit ranges.\n" + prompt, model: model)
        note = try ContextSafety.groundedExcerpt(corrected, source: chunk)
      }
      noteBytes += note.utf8.count
      guard noteBytes <= 8_000_000 else {
        throw CleanerError.message("Summary exceeds 8 MB. Process a smaller exported session; original and backup remain intact")
      }
      notes.append(note)
    }
    // Never silently truncate a long history to fit one prompt. Keep independently cited parts.
    // Preserve chronological source evidence, not unverified model paraphrases.
    let body = notes.enumerated().map { "## Часть \($0.offset+1)\n\n\($0.element)" }.joined(
      separator: "\n\n")
    return
      "# Продолжение — \(transcript.agent)\n\nИсточник: \(transcript.source.lastPathComponent)\nSHA-256: \(transcript.digest)\n\nПроверяемая выжимка исходных строк: модель выбирает ссылки, но не дописывает факты. Оригинал сохранён; это не замена истории текущего чата. Строки идут хронологически и могут содержать отменённые решения. Перед продолжением определите актуальные требования; более позднее явное решение пользователя заменяет прежнее.\n\n"
      + body
  }
  private func validate(_ response: URLResponse) throws {
    guard let r = response as? HTTPURLResponse, (200..<300).contains(r.statusCode) else {
      throw CleanerError.message("Local engine returned an error")
    }
  }
}
private final class LocalOnlyRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
