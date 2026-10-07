import Foundation

/// Read-only JSONL adapters. Unknown records are retained verbatim, never discarded.
public enum NativeHistory {
  public struct Result: Sendable {
    public let numbered: String
    public let messages: Int
    public let retainedRecords: Int
  }
  public static func parse(_ text: String, agent: String) throws -> Result {
    guard ["codex", "claude"].contains(agent) else {
      throw CleanerError.message("Native history adapter unavailable for this agent")
    }
    var lines: [String] = []
    var identities = Set<String>()
    var messages = 0
    var retained = 0
    var recognized = false
    for (index, raw) in text.components(separatedBy: "\n").enumerated() {
      guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
      guard let data = raw.data(using: .utf8),
        let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { throw CleanerError.message("Invalid JSONL at line \(index + 1)") }
      let type = value["type"] as? String ?? ""
      var message: [String: Any]?
      if agent == "codex" {
        let payload = value["payload"] as? [String: Any]
        if type == "session_meta", let id = payload?["id"] as? String, !id.isEmpty {
          identities.insert(id)
          recognized = true
        }
        if type == "response_item", payload?["type"] as? String == "message" {
          message = payload
        }
      } else {
        if let id = value["sessionId"] as? String, !id.isEmpty { identities.insert(id) }
        if ["user", "assistant"].contains(type), let body = value["message"] as? [String: Any],
          let role = body["role"] as? String, ["user", "assistant"].contains(role) {
          message = body
          recognized = true
        }
      }
      // Keep the complete record alongside the role label: tool results, branch metadata,
      // compaction events and unknown fields can all carry important context.
      if let message, let role = message["role"] as? String {
        messages += 1
        lines.append("[L\(index + 1)] MESSAGE (\(role)): \(raw)")
      } else {
        retained += 1
        lines.append("[L\(index + 1)] RECORD (\(type)): \(raw)")
      }
    }
    guard recognized, identities.count == 1, messages > 0 else {
      throw CleanerError.message("Unrecognized or mixed session. Import one JSONL session for the selected agent")
    }
    return Result(numbered: lines.joined(separator: "\n"), messages: messages, retainedRecords: retained)
  }
}
