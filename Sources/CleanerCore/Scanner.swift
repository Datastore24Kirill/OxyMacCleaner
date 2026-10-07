import Darwin
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
    return try metadata(url)
  }

  /// Scanner has already excluded cloud placeholders and symlinks.
  static func metadata(_ url: URL) throws -> FileRecord {
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
      throw CleanerError.message("File unavailable or not regular: " + url.path)
    }
    return FileRecord(path: url.standardizedFileURL.path, bytes: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512,
      modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000),
      inode: UInt64(info.st_ino), device: UInt64(UInt32(bitPattern: info.st_dev)), links: UInt64(info.st_nlink))
  }
  public func validate() throws {
    let now = try Self.read(URL(fileURLWithPath: path))
    guard
      now.bytes == bytes && now.modified == modified && now.inode == inode && now.device == device
    else { throw CleanerError.message("File changed since scanning: \(name). Scan again.") }
  }
}
public struct ScanReport: Codable, Sendable {
  public var files: [FileRecord] = []
  public var issues: [String] = []
  public var folders: [String: Int64] = [:]
  public var complete = false
  public init() {}
  public var total: Int64 { files.reduce(0) { $0 + $1.bytes } }
}
public struct ScanProgress: Codable, Sendable {
  public enum Phase: String, Codable, Sendable { case enumerating, sorting, finished, cancelled }
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
    record: ((FileRecord) throws -> Void)? = nil,
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
    struct Identity: Hashable { let device: UInt64; let inode: UInt64 }
    var seen = Set<Identity>()
    var journalFailed = false
    let normalized = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    let unique = normalized.filter { root in
      !normalized.contains { $0 != root && inside(root.path, $0.path) }
    }
    for root in Set(unique) {
      guard !cancellation.cancelled else { break }
      guard let name = strdup(root.path) else { result.issues.append(root.path); continue }
      var paths: [UnsafeMutablePointer<CChar>?] = [name, nil]
      let tree = paths.withUnsafeMutableBufferPointer { fts_open($0.baseAddress, FTS_PHYSICAL | FTS_NOCHDIR, nil) }
      guard let tree else { free(name); result.issues.append(root.path); continue }
      errno = 0
      while let entry = fts_read(tree) {
        if cancellation.cancelled { break }
        autoreleasepool {
          let item = entry.pointee
          let path = String(cString: item.fts_path)
          let kind = Int32(item.fts_info)
          if excluded.contains(where: { inside(path, $0) }) || [".git", ".ssh", ".Trash"].contains(String(path.split(separator: "/").last ?? "")) {
            if kind == FTS_D { fts_set(tree, entry, FTS_SKIP) }; return
          }
          if kind == FTS_ERR || kind == FTS_DNR || kind == FTS_NS {
            result.issues.append(path + ": " + String(cString: strerror(item.fts_errno))); return
          }
          guard let stat = item.fts_statp else { return }
          // Dataless file-provider placeholders must not be hydrated by a cleanup scan.
          if stat.pointee.st_flags & UInt32(SF_DATALESS) != 0 {
            if kind == FTS_D { fts_set(tree, entry, FTS_SKIP) }
            result.issues.append("Cloud-only: " + path); return
          }
          if kind == FTS_D { snapshot.directories += 1; return }
          guard kind == FTS_F else { return }
          snapshot.currentPath = (path as NSString).deletingLastPathComponent
          emit()
          let info = stat.pointee
          let f = FileRecord(path: path, bytes: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512,
            modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000),
            inode: UInt64(info.st_ino), device: UInt64(UInt32(bitPattern: info.st_dev)), links: UInt64(info.st_nlink))
          if f.links > 1, !seen.insert(Identity(device: f.device, inode: f.inode)).inserted { return }
          if !journalFailed, let record {
            do { try record(f) } catch { journalFailed = true; result.issues.append("Recovery journal unavailable: " + error.localizedDescription) }
          }
          result.files.append(f); snapshot.files += 1; snapshot.bytes += f.bytes
          snapshot.categories[f.category, default: 0] += f.bytes
          var parent = (path as NSString).deletingLastPathComponent
          while inside(parent, root.path) {
            result.folders[parent, default: 0] += f.bytes
            if parent == root.path { break }; parent = (parent as NSString).deletingLastPathComponent
          }
        }
        errno = 0
      }
      if !cancellation.cancelled, errno != 0 { result.issues.append(root.path + ": " + String(cString: strerror(errno))) }
      fts_close(tree); free(name)
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
