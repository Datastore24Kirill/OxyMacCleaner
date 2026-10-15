/// Keeps a page while navigating the same ordered inventory, and returns to the
/// first page when filtering or retention changes which archives are displayed.
public struct ArchivePagination {
  public var page = 0
  private var paths: [String] = []

  public init() {}

  public mutating func update(paths next: [String]) {
    guard paths != next else { return }
    paths = next
    page = 0
  }
}
