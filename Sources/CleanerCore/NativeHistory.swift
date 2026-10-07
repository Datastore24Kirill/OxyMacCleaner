import Foundation

public enum NativeHistory {
  public struct Result: Sendable {
    public let numbered: String
    public let messages: Int
    public let retainedRecords: Int
  }
  struct Validator {
    let agent: String
    var identities = Set<String>()
    var messages = 0
    var retained = 0
    var recognized = false
    mutating func consume(_ raw: String, index: Int) throws -> String? {
      guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
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
      } else if agent == "cursor" {
        guard let role = value["role"] as? String, ["user", "assistant"].contains(role),
          let body = value["message"] as? [String: Any], body["content"] is [Any] else {
          throw CleanerError.message("Unsupported Cursor transcript record at line \(index + 1)")
        }
        message = ["role": role]
        recognized = true
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
        return "[L\(index + 1)] MESSAGE (\(role)): \(raw)"
      } else {
        retained += 1
        return "[L\(index + 1)] RECORD (\(type)): \(raw)"
      }

    }
    func finish(numbered: String = "") throws -> Result {
      guard ["codex", "claude", "cursor"].contains(agent), recognized, (agent == "cursor" ? identities.isEmpty : identities.count == 1), messages > 0 else {
        throw CleanerError.message("Unrecognized or mixed session. Import one JSONL session for the selected agent")
      }
      return Result(numbered: numbered, messages: messages, retainedRecords: retained)
    }
  }
  public static func parse(_ text: String, agent: String) throws -> Result {
    var validator = Validator(agent: agent)
    var lines: [String] = []
    for (index, raw) in text.components(separatedBy: "\n").enumerated() {
      if let line = try validator.consume(raw, index: index) { lines.append(line) }
    }
    return try validator.finish(numbered: lines.joined(separator: "\n"))
  }
}
