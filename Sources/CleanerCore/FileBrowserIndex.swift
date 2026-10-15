import Foundation

/// Shares scan metadata and computes a bounded page off the UI thread.
public struct FileBrowserIndex: Sendable {
  public struct Query: Hashable, Sendable {
    public var text = ""
    public var category = "all"
    public var minimumMB = 0
    public var olderThanDays = 0
    public var archivesAndDownloads = false
    public var showProtected = false
    public var limit = 200
    public init() {}
    /// Pagination preserves selection only when the filter itself is unchanged.
    public func isPageExpansion(of previous: Self) -> Bool {
      guard limit > previous.limit else { return false }
      var samePage = self
      samePage.limit = previous.limit
      return samePage == previous
    }
  }
  public struct Row: Sendable {
    public let file: FileRecord
    public let category: String
    public let selectable: Bool
    let search: String
    let download: Bool
  }
  public struct Result: Sendable {
    public var rows: [Row] = []
    public var matches = 0
    public var bytes: Int64 = 0
    public var allocatedBytes: Int64 = 0
    public var hiddenProtected = 0
    public init() {}
  }
  // Keep the scan's copy-on-write array, rather than duplicating and sorting millions of rows.
  private let results = BoundedCache<Query, Result>(capacity: 4, budget: 1600)
  private let files: [FileRecord]
  private let excluded: [String]
  private let quarantine: String
  private let downloads: String
  public init(files: [FileRecord], excluded: [String], quarantine: String, downloads: String,
              cancellation: Cancellation = Cancellation()) throws {
    try cancellation.check()
    self.files = files; self.excluded = excluded; self.quarantine = quarantine; self.downloads = downloads
  }
  public func filter(_ query: Query, now: Date = Date(), cancellation: Cancellation = Cancellation(),
                     progress: @Sendable (Double) -> Void = { _ in }) throws -> Result {
    try cancellation.check()
    // Age-based queries depend on the caller's clock, so never reuse those results.
    if query.olderThanDays == 0, let cached = results.value(for: query) { progress(1); return cached }
    let search = query.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let cutoff = now.addingTimeInterval(-Double(query.olderThanDays) * 86400)
    var result = Result()
    var classifications: [String: (String, Bool)] = [:]
    let named: Set<String> = ["package.swift", "package.resolved", "podfile.lock", "cartfile.resolved", "docker.raw", "docker.qcow2"]
    let requestedLimit = max(1, query.limit)
    // The first page also prepares the next 200 rows during the same scan.
    let prefetch = query.limit == 200 && query.olderThanDays == 0
    let limit = prefetch ? 400 : requestedLimit
    // A bounded heap: the worst visible row is at the root. Memory is O(page size).
    func better(_ a: Row, _ b: Row) -> Bool {
      a.file.bytes == b.file.bytes ? a.file.path < b.file.path : a.file.bytes > b.file.bytes
    }
    func insert(_ row: Row) {
      if result.rows.count < limit {
        result.rows.append(row)
        var i = result.rows.count - 1
        while i > 0 {
          let parent = (i - 1) / 2
          guard better(result.rows[parent], result.rows[i]) else { break }
          result.rows.swapAt(i, parent); i = parent
        }
      } else if better(row, result.rows[0]) {
        result.rows[0] = row
        var i = 0
        while i * 2 + 1 < result.rows.count {
          var child = i * 2 + 1
          if child + 1 < result.rows.count && better(result.rows[child], result.rows[child + 1]) { child += 1 }
          guard better(result.rows[i], result.rows[child]) else { break }
          result.rows.swapAt(i, child); i = child
        }
      }
    }
    for (index, file) in files.enumerated() {
      if index % 256 == 0 { try cancellation.check() }
      if index % 8192 == 0 { progress(Double(index) / Double(max(1, files.count))) }
      guard file.bytes >= Int64(query.minimumMB) * 1_000_000,
        query.olderThanDays == 0 || file.modified < cutoff,
        search.isEmpty || (file.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) as NSString).range(of: search, options: .literal).location != NSNotFound else { continue }
      let path = file.path as NSString, leaf = (file.path as NSString).lastPathComponent.lowercased()
      let ext = path.pathExtension.lowercased()
      let key = path.deletingLastPathComponent + "/" + (leaf.hasPrefix(".") || ext.isEmpty || named.contains(leaf) ? leaf : "*." + ext)
      let classification: (String, Bool)
      if let cached = classifications[key] { classification = cached }
      else {
        classification = (file.category, QuarantineStore.protected(file.path))
        if classifications.count >= 4096 { classifications.removeAll(keepingCapacity: true) }
        classifications[key] = classification
      }
      let category = classification.0
      let download = Scanner.inside(file.path, downloads)
      guard !query.archivesAndDownloads || category == "Archive" || download,
        query.archivesAndDownloads || query.category == "all" || category == query.category else { continue }
      let selectable = file.links == 1 && !classification.1
        && !Scanner.inside(file.path, quarantine) && !excluded.contains { Scanner.inside(file.path, $0) }
      if !selectable && !query.showProtected && query.category != FileCategory.docker.rawValue { result.hiddenProtected += 1; continue }
      result.matches += 1
      result.bytes += max(0, file.bytes)
      result.allocatedBytes += max(0, file.allocated)
      insert(Row(file: file, category: category, selectable: selectable, search: "", download: download))
    }
    try cancellation.check()
    result.rows.sort(by: better)
    progress(1)
    try cancellation.check()
    if prefetch {
      var next = query; next.limit = 400
      results.insert(result, for: next, cost: result.rows.count)
      result.rows = Array(result.rows.prefix(requestedLimit))
    }
    if query.olderThanDays == 0 { results.insert(result, for: query, cost: result.rows.count) }
    return result
  }
}
