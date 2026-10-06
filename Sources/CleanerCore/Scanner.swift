import CryptoKit
import Foundation

public enum CleanerError: LocalizedError {
  case message(String)
  public var errorDescription: String? {
    if case .message(let s) = self { return s }
    return nil
  }
}
public final class Cancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  public init() {}
  public func cancel() {
    lock.lock()
    value = true
    lock.unlock()
  }
  public var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  public func check() throws { if cancelled { throw CancellationError() } }
}
public struct FileRecord: Identifiable, Codable, Hashable, Sendable {
  public var id: String { path }
  public let path: String
  public let bytes: Int64
  public let allocated: Int64
  public let modified: Date
  public let inode: UInt64
  public let device: UInt64
  public let links: UInt64
  public var name: String { URL(fileURLWithPath: path).lastPathComponent }
  public var category: String { FileCategory.classify(path).rawValue }
  public static func read(_ url: URL) throws -> FileRecord {
    let v = try url.resourceValues(forKeys: [
      .isSymbolicLinkKey, .isRegularFileKey, .isUbiquitousItemKey,
      .ubiquitousItemDownloadingStatusKey, .fileAllocatedSizeKey,
    ])
    guard v.isSymbolicLink != true, v.isRegularFile == true else {
      throw CleanerError.message("Not a regular local file")
    }
    if v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus != .current {
      throw CleanerError.message("Cloud-only file skipped")
    }
    let a = try FileManager.default.attributesOfItem(atPath: url.path)
    return FileRecord(
      path: url.standardizedFileURL.path, bytes: (a[.size] as? NSNumber)?.int64Value ?? 0,
      allocated: Int64(v.fileAllocatedSize ?? 0),
      modified: a[.modificationDate] as? Date ?? .distantPast,
      inode: (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
      device: (a[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
      links: (a[.referenceCount] as? NSNumber)?.uint64Value ?? 1)
  }
  public func validate() throws {
    let now = try Self.read(URL(fileURLWithPath: path))
    guard
      now.bytes == bytes && now.modified == modified && now.inode == inode && now.device == device
    else { throw CleanerError.message("File changed since scanning: \(name). Scan again.") }
  }
}
public struct ScanReport: Sendable {
  public var files: [FileRecord] = []
  public var issues: [String] = []
  public var folders: [String: Int64] = [:]
  public var complete = false
  public init() {}
  public var total: Int64 { files.reduce(0) { $0 + $1.bytes } }
}
public struct ScanProgress: Sendable {
  public enum Phase: Sendable { case enumerating, sorting, finished, cancelled }
  public var phase: Phase = .enumerating
  public var files = 0
  public var directories = 0
  public var bytes: Int64 = 0
  public var issues = 0
  public var currentPath = ""
  public var categories: [String: Int64] = [:]
  public var elapsed: TimeInterval = 0
  public init() {}
}
public enum Scanner {
  public static func inside(_ path: String, _ root: String) -> Bool {
    path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }
  public static func scan(
    roots: [URL], excluded: [String], cancellation: Cancellation,
    progress: @escaping (ScanProgress) -> Void = { _ in }
  ) -> ScanReport {
    var result = ScanReport()
    var snapshot = ScanProgress()
    let started = ProcessInfo.processInfo.systemUptime
    var lastEmission = started
    func emit(_ force: Bool = false) {
      let now = ProcessInfo.processInfo.systemUptime
      guard force || now - lastEmission >= 0.15 else { return }
      snapshot.elapsed = now - started
      snapshot.issues = result.issues.count
      progress(snapshot)
      lastEmission = now
    }
    emit(true)
    var seen = Set<String>()
    let fm = FileManager.default
    let normalized = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    let unique = normalized.filter { root in
      !normalized.contains { $0 != root && inside(root.path, $0.path) }
    }
    for root in Set(unique) {
      guard !cancellation.cancelled else { break }
      guard
        let e = fm.enumerator(
          at: root,
          includingPropertiesForKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
          ], options: [],
          errorHandler: { u, error in
            result.issues.append("\(u.path): \(error.localizedDescription)")
            return true
          })
      else {
        result.issues.append(root.path)
        continue
      }
      for case let url as URL in e {
        if cancellation.cancelled { break }
        snapshot.currentPath = url.deletingLastPathComponent().path
        emit()
        if excluded.contains(where: { inside(url.path, $0) })
          || [".git", ".ssh", ".Trash"].contains(url.lastPathComponent)
        {
          e.skipDescendants()
          continue
        }
        do {
          let v = try url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
          ])
          if v.isSymbolicLink == true {
            e.skipDescendants()
            continue
          }
          if v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus != .current {
            e.skipDescendants()
            result.issues.append("Cloud-only: \(url.path)")
            continue
          }
          if v.isDirectory == true {
            snapshot.directories += 1
            continue
          }
          let f = try FileRecord.read(url)
          let identity = "\(f.device):\(f.inode)"
          guard seen.insert(identity).inserted else { continue }
          result.files.append(f)
          snapshot.files += 1
          snapshot.bytes += f.bytes
          snapshot.categories[f.category, default: 0] += f.bytes
          var parent = url.deletingLastPathComponent()
          while inside(parent.path, root.path) {
            result.folders[parent.path, default: 0] += f.bytes
            if parent.path == root.path { break }
            parent.deleteLastPathComponent()
          }

        } catch { result.issues.append("\(url.path): \(error.localizedDescription)") }
      }
    }
    result.complete = !cancellation.cancelled
    snapshot.phase = .sorting
    emit(true)
    result.files.sort { $0.bytes > $1.bytes }
    snapshot.phase = result.complete ? .finished : .cancelled
    emit(true)
    return result
  }
  public static func hash(_ url: URL, cancellation: Cancellation = Cancellation()) throws -> String
  {
    let h = try FileHandle(forReadingFrom: url)
    defer { try? h.close() }
    var sha = SHA256()
    while true {
      try cancellation.check()
      let d = try h.read(upToCount: 1024 * 1024) ?? Data()
      if d.isEmpty { break }
      sha.update(data: d)
    }
    return sha.finalize().map { String(format: "%02x", $0) }.joined()
  }
  public static func duplicates(
    _ files: [FileRecord], cancellation: Cancellation, progress: @escaping (Int) -> Void = { _ in }
  ) throws -> [[FileRecord]] {
    let sizes = Dictionary(
      grouping: files.filter { $0.bytes > 0 && $0.links == 1 }, by: { $0.bytes })
    var output: [[FileRecord]] = []
    var count = 0
    for group in sizes.values where group.count > 1 {
      var hashes: [String: [FileRecord]] = [:]
      for f in group {
        try cancellation.check()
        try f.validate()
        let digest = try hash(URL(fileURLWithPath: f.path), cancellation: cancellation)
        try f.validate()
        hashes[digest, default: []].append(f)
        count += 1
        progress(count)
      }
      for matches in hashes.values where matches.count > 1 {
        // Confirm bytes rather than relying solely on a digest.
        var partitions: [[FileRecord]] = []
        for f in matches {
          if let i = partitions.firstIndex(where: { fmEqual($0[0].path, f.path) }) {
            partitions[i].append(f)
          } else {
            partitions.append([f])
          }
        }
        output += partitions.filter { $0.count > 1 }
      }
    }
    return output.sorted { $0[0].bytes > $1[0].bytes }
  }
  private static func fmEqual(_ a: String, _ b: String) -> Bool {
    FileManager.default.contentsEqual(atPath: a, andPath: b)
  }
}
