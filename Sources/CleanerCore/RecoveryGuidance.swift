import Foundation

/// Suggestions only: none of these destinations retries an operation or changes permissions.
public struct RecoveryGuidance: Sendable {
  public enum Destination: String, Sendable { case settings, engine, history, agents }
  public let summary: String
  public let details: String
  public let destination: Destination?

  public init(_ raw: String, russian: Bool) {
    details = raw
    let text = raw.lowercased()
    let formatted = ErrorPresentation.message(raw, russian: russian)
    if formatted != raw, let separator = formatted.range(of: "\n\n") {
      summary = String(formatted[..<separator.lowerBound])
    } else if raw.count <= 320 && raw.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) && russian {
      summary = raw
    } else {
      summary = russian
        ? "Не удалось завершить операцию. Откройте подробности и проверьте результат в истории. Автоматического повтора не будет."
        : "The operation could not be completed. Review the details and operation history. It will not be retried automatically."
    }
    // Batch messages can contain several causes; avoid proposing a single misleading fix.
    if raw.contains("\n") { destination = .history }
    else if text.contains("permission") || text.contains("not permitted") || text.contains("access denied") {
      destination = .settings
    } else if text.contains("connection refused") || text.contains("could not connect") || text.contains("cannot connect") || (text.contains("model") && text.contains("not found")) {
      destination = .engine
    } else if text.contains("history format") || text.contains("jsonl") || text.contains("session format") {
      destination = .agents
    } else { destination = .history }
  }
}
