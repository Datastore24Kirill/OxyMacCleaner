import Foundation

public enum JSONHistory {
  public static let agents: Set<String> = ["gemini", "continue", "cline", "roo"]
  /// L references identify normalized records, not physical lines of pretty-printed JSON.
  public static func parse(_ text: String, agent: String, filename: String) throws -> NativeHistory.Result {
    let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
    var metadata: [String: Any] = [:]
    let records: [[String: Any]]
    switch agent {
    case "gemini", "continue":
      guard var root = object as? [String: Any], let id = root["sessionId"] as? String, !id.isEmpty,
        let rows = root[agent == "gemini" ? "messages" : "history"] as? [[String: Any]] else {
        throw CleanerError.message("Unrecognized JSON session structure")
      }
      records = rows; root.removeValue(forKey: agent == "gemini" ? "messages" : "history"); metadata = root
    case "cline", "roo":
      guard filename == "api_conversation_history.json", let rows = object as? [[String: Any]] else {
        throw CleanerError.message("Choose api_conversation_history.json for one task")
      }
      records = rows
    default: throw CleanerError.message("Unsupported JSON adapter")
    }
    func json(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self) }
    var lines = ["[L1] META: " + (try json(metadata))]; var count = 0
    for (index, row) in records.enumerated() {
      let body = agent == "continue" ? row["message"] as? [String: Any] : row
      guard let body else { throw CleanerError.message("Unsupported message structure") }
      let type = body[agent == "gemini" ? "type" : "role"] as? String ?? ""
      let role = type == "gemini" ? "assistant" : type
      guard ["user", "assistant", "system", "tool", "info", "error", "warning"].contains(role),
        body["content"] is String || body["content"] is [Any] else { throw CleanerError.message("Unsupported message content") }
      if ["user", "assistant"].contains(role) { count += 1 }
      lines.append("[L\(index+2)] MESSAGE (\(role)): " + (try json(row)))
    }
    guard count > 0 else { throw CleanerError.message("No recognized conversation messages") }
    return NativeHistory.Result(numbered: lines.joined(separator: "\n"), messages: count, retainedRecords: records.count - count + 1)
  }
}
