import Foundation

public enum AiderHistory {
  /// Conservative file recognition, not reconstruction of Markdown roles or active branches.
  public static func parse(_ text: String) throws -> NativeHistory.Result {
    let lines = text.components(separatedBy: "\n")
    guard lines.filter({ $0.hasPrefix("# aider chat started at ") }).count == 1,
      lines.contains(where: { $0.hasPrefix("#### ") }) else {
      throw CleanerError.message("Select one Aider chat section with its start header; multiple sessions are not merged")
    }
    return NativeHistory.Result(numbered: lines.enumerated().map { "[L\($0.offset + 1)] " + $0.element }.joined(separator: "\n"), messages: 0, retainedRecords: lines.count)
  }
}
