import CryptoKit
import Foundation

public struct DirectoryManifest: Codable, Equatable, Sendable {
  public struct Item: Codable, Equatable, Sendable {
    public let relative: String
    public let directory: Bool
    public let bytes: Int64
    public let modified: Date
    public let inode: UInt64
    public let device: UInt64
    public let digest: String
  }
  public let items: [Item]
  public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
  public var digest: String {
    get throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return SHA256.hash(data: try encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
    }
  }
  public static func capture(
    _ root: URL, cancellation: Cancellation = Cancellation(),
    validate: (String) throws -> Void = { _ in }
  ) throws -> Self {
    let fm = FileManager.default
    guard root.resolvingSymlinksInPath() == root.standardizedFileURL else {
      throw CleanerError.message("Directory path contains symbolic links")
    }
    let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
      throw CleanerError.message("Not a regular directory")
    }
    var traversalError: Error?
    guard
      let enumerator = fm.enumerator(
        at: root, includingPropertiesForKeys: nil,
        errorHandler: { _, error in
          traversalError = error
          return false
        })
    else { throw CleanerError.message("Directory cannot be read") }
    var urls = [root]
    for case let url as URL in enumerator {
      try cancellation.check()
      urls.append(url)
    }
    if let traversalError { throw traversalError }
    var items: [Item] = []
    for url in urls {
      try cancellation.check()
      try validate(url.path)
      let values = try url.resourceValues(forKeys: [
        .isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
      ])
      guard values.isSymbolicLink != true,
        values.isDirectory == true || values.isRegularFile == true
      else {
        throw CleanerError.message("Links and special files are not supported inside folders")
      }
      guard values.isUbiquitousItem != true else {
        throw CleanerError.message("Cloud-managed folders are analysis-only")
      }
      let attrs = try fm.attributesOfItem(atPath: url.path)
      let directory = values.isDirectory == true
      var digest = ""
      if !directory {
        let file = try FileRecord.read(url)
        guard file.links == 1 else {
          throw CleanerError.message("Folder contains hard-linked files")
        }
        digest = try Scanner.hash(url, cancellation: cancellation)
        try file.validate()
      }
      let relative = url == root ? "" : String(url.path.dropFirst(root.path.count + 1))
      items.append(
        Item(
          relative: relative, directory: directory,
          bytes: directory ? 0 : (attrs[.size] as? NSNumber)?.int64Value ?? 0,
          modified: attrs[.modificationDate] as? Date ?? .distantPast,
          inode: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
          device: (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0, digest: digest))
    }
    return Self(items: items.sorted { $0.relative < $1.relative })
  }
}
