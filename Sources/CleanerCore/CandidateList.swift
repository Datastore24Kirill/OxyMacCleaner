import Foundation

/// Presentation-only ordering. It never changes eligibility or authorizes cleanup.
public enum CandidateSort: String, CaseIterable, Sendable {
  case suggested, size, oldest, type
}
public enum CandidateList {
  public static func matching(_ candidates: [CleanupCandidate], rule: String = "all",
    query: String = "", sort: CandidateSort = .suggested) -> [CleanupCandidate] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = candidates.filter {
      (rule == "all" || $0.rule.rawValue == rule)
        && (query.isEmpty || $0.file.path.localizedCaseInsensitiveContains(query))
    }
    guard sort != .suggested else { return matches }
    return matches.sorted { (a: CleanupCandidate, b: CleanupCandidate) -> Bool in
      switch sort {
      case .oldest:
        if a.file.modified != b.file.modified { return a.file.modified < b.file.modified }
      case .type:
        if a.file.category != b.file.category { return a.file.category < b.file.category }
      case .size, .suggested: break
      }
      if a.file.bytes != b.file.bytes { return a.file.bytes > b.file.bytes }
      return a.id < b.id
    }
  }
}
