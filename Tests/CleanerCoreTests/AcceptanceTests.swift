import XCTest
@testable import CleanerCore

final class AcceptanceTests: XCTestCase {
  func testConfirmedRemovalUpdatesSnapshotAndPersistsWithoutResumingStaleCheckpoint() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let removed = root.appendingPathComponent("cache")
    try FileManager.default.createDirectory(at: removed, withIntermediateDirectories: true)
    for path in [removed.appendingPathComponent("a"), root.appendingPathComponent("cache-other")] { try Data("123".utf8).write(to: path) }
    let scan = Scanner.scan(roots: [root], excluded: [], cancellation: Cancellation())
    let date = Date(timeIntervalSince1970: 100)
    let saved = SavedScan(roots: [root], volumeID: "fixture", report: scan, progress: ScanProgress(), date: date)
    let result = ScanReconciliation.removing([removed.path, removed.appendingPathComponent("a").path], from: saved)
    XCTAssertEqual(result.report.files.map(\.name), ["cache-other"])
    XCTAssertEqual(result.report.total, 3); XCTAssertEqual(result.progress.bytes, 3)
    XCTAssertEqual(result.report.folders[root.path], 3)
    XCTAssertEqual(result.progress.categories.values.reduce(0,+), 3)
    XCTAssertNil(result.report.checkpoint); XCTAssertFalse(result.report.complete)
    let store = ScanStore(url: root.appendingPathComponent("scan")); try store.save(result)
    let loaded = try XCTUnwrap(store.load())
    XCTAssertEqual(loaded.date, date); XCTAssertEqual(loaded.report.files.count, 1)
    XCTAssertEqual(ScanReconciliation.removing([removed.path], from: loaded).report.total, 3)
    XCTAssertTrue(FileManager.default.fileExists(atPath: removed.appendingPathComponent("a").path), "Reconciliation only changes metadata")
  }
  func testQuarantineCleanupReconciliationAndRestoreOnDisposableFiles() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/OxyAcceptance-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = root.appendingPathComponent("files")
    try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    let a = files.appendingPathComponent("a"); let b = files.appendingPathComponent("b")
    for url in [a,b] { try Data("same payload".utf8).write(to: url) }
    let report = Scanner.scan(roots: [files], excluded: [], cancellation: Cancellation())
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    let entry = try store.move(FileRecord.read(a))
    let saved = SavedScan(roots: [files], volumeID: "test", report: report, progress: ScanProgress())
    let result = ScanReconciliation.removing([a.path], from: saved)
    XCTAssertEqual(result.report.files.map(\.path), [b.path])
    XCTAssertEqual(result.report.total, 12)
    XCTAssertTrue(store.inspect(entry).payloadValid)
    try store.restore(entry)
    XCTAssertEqual(try Data(contentsOf: a), try Data(contentsOf: b))
    XCTAssertEqual(Scanner.scan(roots: [files], excluded: [], cancellation: Cancellation()).files.count, 2)
  }
  func testActionableFailureMessagesInBothLanguages() {
    for raw in ["Update checksum mismatch", "Connection refused", "model qwen not found", "Insufficient space", "Original volume disconnected"] {
      for russian in [true, false] {
        let message = ErrorPresentation.message(raw, russian: russian)
        XCTAssertTrue(message.contains(raw))
        XCTAssertGreaterThan(message.count, raw.count)
      }
    }
  }
  func testReviewCategoriesPreserveSourceEvidence() throws {
    let text = "Пользователь: нужно оставить 7 архивов\nОтменяю разрешение, не удалять оригинал\nСледующий шаг: проверить экспорт, релиз не опубликован\ntestRestore FAILED\nОбычная строка"
    let reader = try TranscriptReview(Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: text, digest: "fixture"))
    let findings = try reader.reviewIndex()
    XCTAssertEqual(findings.matches, 4)
    XCTAssertEqual(findings.items[0].signals, [.requirement])
    XCTAssertEqual(findings.items[1].signals, [.changedDecision, .restriction])
    XCTAssertEqual(findings.items[2].signals, [.pending])
    XCTAssertEqual(findings.items[3].signals, [.testEvidence])
    XCTAssertTrue(try reader.page(at: findings.items[3].offset).text.hasPrefix("[L4] testRestore FAILED"))
  }
  func testInstallerLaunchHandshakeAndEarlyFailureRollback() throws {
    for healthy in [true, false] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("OxyInstallerQA-"+UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let app = root.appendingPathComponent("OxyMac Cleaner.app")
      let stage = root.appendingPathComponent(".OxyMacUpdate-fixture")
      let next = stage.appendingPathComponent("next.app")
      try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
      try Data("previous".utf8).write(to: app.appendingPathComponent("version"))
      let binary = next.appendingPathComponent("Contents/MacOS/OxyMacCleaner")
      try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
      try (healthy ? "#!/bin/sh\nprintf ready > \"$2\"\n" : "#!/bin/sh\nexit 1\n").write(to: binary, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
      let script = root.appendingPathComponent("install.sh")
      // Stub only GUI reopening; production move/handshake/rollback code is executed unchanged.
      try UpdateInstaller.script.replacingOccurrences(of: "/usr/bin/open", with: "/usr/bin/true").write(to: script, atomically: true, encoding: .utf8)
      let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
      process.arguments = [script.path, "99999999", app.path, next.path, stage.path]
      try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
      if healthy {
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.appendingPathComponent("healthy").path))
        XCTAssertEqual(try String(contentsOf: stage.appendingPathComponent("rollback/OxyMac Cleaner.app/version")), "previous")
      } else {
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version")), "previous")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.appendingPathComponent("failed-update/Contents/MacOS/OxyMacCleaner").path))
      }
    }
  }
}
