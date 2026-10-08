import Foundation

public struct CleanupSummary: Sendable {
  public let selected: Int
  public let completed: Int
  public let attempted: Int
  public init(selected: Int, completed: Int, attempted: Int) {
    self.selected = max(0, selected)
    self.attempted = min(max(0, attempted), self.selected)
    self.completed = min(max(0, completed), self.attempted)
  }
  public func text(russian: Bool) -> String {
    let skipped = attempted - completed
    let pending = selected - attempted
    return russian
      ? "Выполнено: \(completed)/\(selected) · не выполнено/пропущено: \(skipped) · не начато: \(pending)"
      : "Completed: \(completed)/\(selected) · not completed/skipped: \(skipped) · not started: \(pending)"
  }
}
