import Foundation

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
    let (data, response) = try await session.data(for: request("tags"))
    try validate(response)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    // Remote/cloud models are not eligible for local context processing.
    return (json?["models"] as? [[String: Any]] ?? []).filter {
      $0["remote_host"] == nil && $0["remote_model"] == nil
    }.compactMap { $0["name"] as? String }.filter { !$0.lowercased().contains("cloud") }
  }
  public func pull(_ name: String, progress: @escaping @Sendable (String) -> Void) async throws {
    guard ["qwen2.5:3b", "qwen2.5:7b"].contains(name) else {
      throw CleanerError.message("Choose an approved local model")
    }
    let (stream, response) = try await session.bytes(
      for: request("pull", ["model": name, "stream": true]))
    try validate(response)
    for try await line in stream.lines {
      try Task.checkCancellation()
      guard let d = line.data(using: .utf8),
        let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
      else { continue }
      if let error = j["error"] as? String { throw CleanerError.message(error) }
      let done = (j["completed"] as? NSNumber)?.doubleValue ?? 0
      let total = (j["total"] as? NSNumber)?.doubleValue ?? 0
      progress(
        (j["status"] as? String ?? "")
          + (total > 0
            ? String(
              format: " · %.0f%% · %.0f / %.0f MB", done / total * 100, done / 1e6, total / 1e6)
            : ""))
    }
  }
  public func generate(_ prompt: String, model: String) async throws -> String {
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
    let r = try request(
      "generate",
      [
        "model": model, "system": ContextPlan.system, "prompt": prompt, "stream": false,
        "options": ["temperature": 0.1, "num_ctx": 16384, "num_predict": 4096], "keep_alive": "5m",
      ])
    let (data, response) = try await session.data(for: r)
    try validate(response)
    try Task.checkCancellation()
    let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    if let error = j?["error"] as? String { throw CleanerError.message(error) }
    guard let result = j?["response"] as? String,
      !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw CleanerError.message("Empty model response") }
    return result
  }
  public func summarize(
    _ transcript: Transcript, model: String, style: String,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> String {
    let chunks = ContextPlan.chunks(transcript.numbered)
    var notes: [String] = []
    for (i, chunk) in chunks.enumerated() {
      try Task.checkCancellation()
      progress("\(i+1) / \(chunks.count)")
      notes.append(
        try await generate(
          "Agent: \(transcript.agent). Compression: \(style). Extract handoff notes for part \(i+1)/\(chunks.count). Preserve source line citations.\n<transcript>\n\(chunk)\n</transcript>",
          model: model))
    }
    // Never silently truncate a long history to fit one prompt. Keep independently cited parts.
    let body = notes.enumerated().map { "## Часть \($0.offset+1)\n\n\($0.element)" }.joined(
      separator: "\n\n")
    return
      "# Продолжение — \(transcript.agent)\n\nИсточник: \(transcript.source.lastPathComponent)\nSHA-256: \(transcript.digest)\n\nПроверьте факты перед использованием. Оригинал сохранён; это не замена истории текущего чата. Части могут содержать устаревшие решения — сверяйте ссылки на строки.\n\n"
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
