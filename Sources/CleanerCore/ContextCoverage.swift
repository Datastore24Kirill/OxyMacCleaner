import Foundation

/// Compares the current edited output with accepted draft wording, not with semantic truth.
public enum ContextCoverage {
  public struct Row: Sendable, Identifiable {
    public var id: String { category.rawValue }
    public let category: ContextCategory
    public var total = 0
    public var referenced = 0
    public var verbatim = 0
  }
  public static func compare(facts: [ContextFact], output: String, cancellation: Cancellation = Cancellation()) throws -> [Row] {
    try cancellation.check()
    let references = SemanticContext.claimReferences(in: output)
    // Rendering adds Markdown quote prefixes to multiline user/source statements.
    func normalize(_ text: String) -> String {
      text.components(separatedBy: "\n").map { line in
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("> ") { value = String(value.dropFirst(2)) }
        return value
      }.joined(separator: "\n")
    }
    let normalized = normalize(output)
    var counts: [ContextCategory: Row] = [:]
    for fact in facts {
      try cancellation.check()
      var row = counts[fact.category] ?? Row(category: fact.category)
      row.total += 1
      if references.contains(fact.line) { row.referenced += 1 }
      let expected = normalize(ContextSafety.redact(fact.text))
      if !expected.isEmpty && normalized.contains(expected) { row.verbatim += 1 }
      counts[fact.category] = row
    }
    try cancellation.check()
    return ContextCategory.allCases.compactMap { counts[$0] }
  }
}
