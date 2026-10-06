import Foundation

public struct XcodeArchive: Identifiable, Sendable, Equatable {
  public var id: String { path }
  public let path: String
  public let name: String
  public let bundleID: String?
  public let team: String?
  public let version: String?
  public let build: String?
  public let created: Date?
  public let bytes: Int64
  public let dsymCount: Int
  public let issues: [String]
  public var group: String? { bundleID.map { (team ?? "unknown-team") + ":" + $0 } }
  public var eligibleForRetention: Bool {
    group != nil && team != nil && created != nil && version != nil && build != nil
      && issues.isEmpty
  }
}
public struct ArchiveInventory: Sendable {
  public var archives: [XcodeArchive] = []
  public var issues: [String] = []
  public var complete = false
  public init() {}
}
public enum ArchiveRetention {
  public enum Decision: String, Sendable { case pinned, latest, review, unknown }
  public static func decisions(_ archives: [XcodeArchive], keep: Int, pinned: Set<String>)
    -> [String: Decision]
  {
    var result: [String: Decision] = [:]
    let groups = Dictionary(grouping: archives.filter(\.eligibleForRetention), by: { $0.group! })
    for values in groups.values {
      let sorted = values.sorted {
        $0.created == $1.created ? $0.path < $1.path : $0.created! > $1.created!
      }
      let latest = Set(sorted.prefix(max(1, keep)).map(\.path))
      for archive in sorted {
        result[archive.path] = latest.contains(archive.path) ? .latest : .review
      }
    }
    for archive in archives {
      if pinned.contains(archive.path) {
        result[archive.path] = .pinned
      } else if !archive.eligibleForRetention {
        result[archive.path] = .unknown
      }
    }
    return result
  }
}
public enum XcodeArchives {
  public static func scan(
    root: URL, cancellation: Cancellation, progress: @escaping (Int) -> Void = { _ in }
  ) -> ArchiveInventory {
    var result = ArchiveInventory()
    let fm = FileManager.default
    do {
      try cancellation.check()
      let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw CleanerError.message("Archive root must be a local directory")
      }
      guard
        let enumerator = fm.enumerator(
          at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isUbiquitousItemKey],
          errorHandler: { url, error in
            result.issues.append(url.path + ": " + error.localizedDescription)
            return true
          })
      else { throw CleanerError.message("Cannot enumerate archive root") }
      for case let url as URL in enumerator {
        try cancellation.check()
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isUbiquitousItemKey])
        if values.isSymbolicLink == true || values.isUbiquitousItem == true {
          enumerator.skipDescendants()
          result.issues.append("Skipped link/cloud object: " + url.path)
          continue
        }
        if url.pathExtension == "xcarchive" {
          enumerator.skipDescendants()
          result.archives.append(try read(url, cancellation: cancellation))
          progress(result.archives.count)
        }
      }
      result.complete = true
    } catch {
      if !(error is CancellationError) { result.issues.append(error.localizedDescription) }
    }
    result.archives.sort { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    return result
  }
  public static func read(_ root: URL, cancellation: Cancellation = Cancellation()) throws
    -> XcodeArchive
  {
    let fm = FileManager.default
    var issues: [String] = []
    var plist: [String: Any] = [:]
    let info = root.appendingPathComponent("Info.plist")
    do {
      let record = try FileRecord.read(info)
      guard record.bytes < 4_000_000 else {
        throw CleanerError.message("Archive metadata is too large")
      }
      plist =
        try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil)
        as? [String: Any] ?? [:]
      try record.validate()
      if (plist["ArchiveVersion"] as? NSNumber)?.intValue != 2 {
        issues.append("Unsupported or missing ArchiveVersion")
      }
    } catch { issues.append("Info.plist: " + error.localizedDescription) }
    let properties = plist["ApplicationProperties"] as? [String: Any] ?? [:]
    func field(_ key: String) -> String? {
      guard let text = properties[key] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return nil }
      return text
    }
    var bytes: Int64 = 0
    var dsymCount = 0
    var seen = Set<String>()
    if let enumerator = fm.enumerator(
      at: root, includingPropertiesForKeys: nil,
      errorHandler: { url, error in
        if issues.count < 20 { issues.append(url.path + ": " + error.localizedDescription) }
        return true
      })
    {
      for case let url as URL in enumerator {
        try cancellation.check()
        do {
          let values = try url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .isRegularFileKey,
          ])
          if values.isSymbolicLink == true || values.isUbiquitousItem == true {
            enumerator.skipDescendants()
            if issues.count < 20 { issues.append("Skipped link/cloud object: " + url.path) }
            continue
          }
          if values.isDirectory == true {
            if url.pathExtension == "dSYM",
              url.deletingLastPathComponent().lastPathComponent == "dSYMs"
            {
              dsymCount += 1
            }
          } else if values.isRegularFile == true {
            let file = try FileRecord.read(url)
            if seen.insert("\(file.device):\(file.inode)").inserted { bytes += file.bytes }
          }
        } catch { if issues.count < 20 { issues.append(error.localizedDescription) } }
      }
    } else {
      issues.append("Cannot read archive contents")
    }
    return XcodeArchive(
      path: root.standardizedFileURL.path,
      name: plist["Name"] as? String ?? root.deletingPathExtension().lastPathComponent,
      bundleID: field("CFBundleIdentifier"), team: field("Team"),
      version: field("CFBundleShortVersionString"), build: field("CFBundleVersion"),
      created: plist["CreationDate"] as? Date, bytes: bytes, dsymCount: dsymCount, issues: issues)
  }
}
