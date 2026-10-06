import Darwin
import Foundation

/// A read-only preview tied to both the source and an optional independently selected backup.
public struct ArchiveTransferPlan: Sendable {
  public let source: URL
  public let backup: URL?
  public let manifest: DirectoryManifest
  let backupManifest: DirectoryManifest?
}
public enum ArchiveTransfer {
  public static func createBackup(
    source: URL, destination: URL, cancellation: Cancellation = Cancellation()
  ) throws {
    let fm = FileManager.default
    guard source.pathExtension == "xcarchive", destination.pathExtension == "xcarchive",
      destination.deletingLastPathComponent().resolvingSymlinksInPath()
        == destination.deletingLastPathComponent().standardizedFileURL,
      !Scanner.inside(destination.path, source.path), !fm.fileExists(atPath: destination.path)
    else {
      throw CleanerError.message("Choose a new backup path outside the source archive")
    }
    let expected = try DirectoryManifest.capture(source, cancellation: cancellation)
    let stage = destination.deletingLastPathComponent().appendingPathComponent(
      ".oxy-backup-" + UUID().uuidString + ".xcarchive")
    defer { try? fm.removeItem(at: stage) }
    try cancellation.check()
    try fm.copyItem(at: source, to: stage)
    let copy = try DirectoryManifest.capture(stage, cancellation: cancellation)
    guard sameContents(expected, copy),
      try DirectoryManifest.capture(source, cancellation: cancellation) == expected
    else {
      throw CleanerError.message("Source changed or backup integrity check failed")
    }
    try cancellation.check()
    guard renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, destination.path, UInt32(RENAME_EXCL)) == 0
    else {
      throw CleanerError.message("Cannot finish backup; destination may already exist")
    }
  }

  static func sameContents(_ a: DirectoryManifest, _ b: DirectoryManifest) -> Bool {
    a.items.count == b.items.count
      && zip(a.items, b.items).allSatisfy {
        $0.relative == $1.relative && $0.directory == $1.directory && $0.bytes == $1.bytes
          && $0.digest == $1.digest
      }
  }
  public static func prepare(
    archive expectedArchive: XcodeArchive, backup: URL? = nil,
    cancellation: Cancellation = Cancellation()
  )
    throws -> ArchiveTransferPlan
  {
    let source = URL(fileURLWithPath: expectedArchive.path)
    guard source.pathExtension == "xcarchive" else {
      throw CleanerError.message("Not an Xcode archive")
    }
    if let backup {
      guard backup.pathExtension == "xcarchive",
        !Scanner.inside(source.path, backup.path), !Scanner.inside(backup.path, source.path)
      else { throw CleanerError.message("Choose a separate complete .xcarchive backup") }
    }
    let archive = try XcodeArchives.read(source, cancellation: cancellation)
    guard archive == expectedArchive, archive.eligibleForRetention else {
      throw CleanerError.message("Archive metadata is incomplete")
    }
    let expected = try DirectoryManifest.capture(source, cancellation: cancellation)
    // Protect files still settling after a build, without a day-long retention gate.
    guard expected.items.allSatisfy({ $0.modified < Date().addingTimeInterval(-600) }) else {
      throw CleanerError.message("Archive changed within the last 10 minutes; try later")
    }
    var copy: DirectoryManifest?
    if let backup {
      copy = try DirectoryManifest.capture(backup, cancellation: cancellation)
      guard let copy, sameContents(expected, copy) else {
        throw CleanerError.message("Backup contents differ from the archive")
      }
    }
    guard try XcodeArchives.read(source, cancellation: cancellation) == expectedArchive,
      try DirectoryManifest.capture(source, cancellation: cancellation) == expected
    else {
      throw CleanerError.message("Archive changed during verification")
    }
    return ArchiveTransferPlan(
      source: source, backup: backup, manifest: expected, backupManifest: copy)
  }
  static func validate(_ plan: ArchiveTransferPlan, cancellation: Cancellation) throws {
    guard let backup = plan.backup else { return }
    let copy = try DirectoryManifest.capture(backup, cancellation: cancellation)
    guard copy == plan.backupManifest, sameContents(plan.manifest, copy) else {
      throw CleanerError.message("Backup changed after preview")
    }
  }
}
