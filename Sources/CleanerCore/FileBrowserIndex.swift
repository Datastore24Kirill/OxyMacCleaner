import Foundation

/// Precomputes expensive URL/category work once per scan, off the UI thread.
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
    public var hiddenProtected = 0
    public init() {}
  }
  private let rows: [Row]
  public init(files: [FileRecord], excluded: [String], quarantine: String, downloads: String,
              cancellation: Cancellation = Cancellation()) throws {
    var values: [Row] = []
    values.reserveCapacity(files.count)
    // Current classification rules depend on parent components, extension and these exact leaf names.
    // Hidden/extensionless leaves retain their whole name in the key.
    let namedLeaves: Set<String> = ["package.swift", "package.resolved", "podfile.lock", "cartfile.resolved"]
    var classifications: [String: (Bool, String)] = [:]
    for (index, file) in files.enumerated() {
      if index % 256 == 0 { try cancellation.check() }
      let path = file.path as NSString
      let leaf = path.lastPathComponent.lowercased(), ext = path.pathExtension.lowercased()
      let leafKey = leaf.hasPrefix(".") || ext.isEmpty || namedLeaves.contains(leaf) ? leaf : "*." + ext
      let key = path.deletingLastPathComponent + "/" + leafKey
      let classification: (Bool, String)
      if let cached = classifications[key] { classification = cached }
      else {
        classification = (QuarantineStore.protected(file.path), file.category)
        classifications[key] = classification
      }
      let selectable = !classification.0 && file.links == 1
        && !Scanner.inside(file.path, quarantine)
        && !excluded.contains { Scanner.inside(file.path, $0) }
      values.append(Row(file: file, category: classification.1, selectable: selectable,
        search: file.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
        download: Scanner.inside(file.path, downloads)))
    }
    rows = values.sorted { $0.file.bytes == $1.file.bytes ? $0.file.path < $1.file.path : $0.file.bytes > $1.file.bytes }
  }
  public func filter(_ query: Query, now: Date = Date(), cancellation: Cancellation = Cancellation()) throws -> Result {
    let search = query.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let cutoff = now.addingTimeInterval(-Double(query.olderThanDays) * 86400)
    var result = Result()
    for (index, row) in rows.enumerated() {
      if index % 256 == 0 { try cancellation.check() }
      guard (!query.archivesAndDownloads || row.category == "Archive" || row.download),
        (query.archivesAndDownloads || query.category == "all" || row.category == query.category),
        row.file.bytes >= Int64(query.minimumMB) * 1_000_000,
        (query.olderThanDays == 0 || row.file.modified < cutoff),
        search.isEmpty || row.search.contains(search) else { continue }
      if !row.selectable && !query.showProtected { result.hiddenProtected += 1; continue }
      result.matches += 1; result.bytes += row.file.bytes
      if result.rows.count < max(1, query.limit) { result.rows.append(row) }
    }
    return result
  }
}
