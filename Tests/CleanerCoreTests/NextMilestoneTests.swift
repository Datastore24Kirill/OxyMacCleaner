import XCTest
@testable import CleanerCore

final class NextMilestoneTests: XCTestCase {
  func testInterruptedScanJournalIgnoresOnlyTornTail() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("a.txt"); try Data("a".utf8).write(to: file)
    let url = root.appendingPathComponent("journal")
    let journal = try ScanJournal(url: url, roots: [root], volumeID: "test")
    try journal.append(FileRecord.read(file)); try journal.flush()
    let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: Data("[{broken".utf8)); try h.close()
    let recovered = try XCTUnwrap(ScanJournal.recover(url))
    XCTAssertFalse(recovered.report.complete); XCTAssertEqual(recovered.report.files.count, 1)
    XCTAssertEqual(recovered.report.total, 1)
    let corrupt = try FileHandle(forWritingTo: url); try corrupt.seekToEnd(); try corrupt.write(contentsOf: Data("\n".utf8)); try corrupt.close()
    XCTAssertThrowsError(try ScanJournal.recover(url))
  }
  func testNativeJSONAdaptersPreserveUnknownEvidence() throws {
    let gemini = #"{"sessionId":"one","messages":[{"type":"user","content":"never delete","extra":"keep"},{"type":"gemini","content":[{"text":"not done"}]}]}"#
    let result = try JSONHistory.parse(gemini, agent: "gemini", filename: "session.json")
    XCTAssertEqual(result.messages, 2); XCTAssertTrue(result.numbered.contains("extra"))
    let continueJSON = #"{"sessionId":"one","history":[{"message":{"role":"user","content":"keep"},"contextItems":[]}]}"#
    XCTAssertEqual(try JSONHistory.parse(continueJSON, agent: "continue", filename: "a.json").messages, 1)
    let messages = #"[{"role":"user","content":[{"type":"text","text":"keep"}]}]"#
    for agent in ["cline", "roo"] {
      XCTAssertEqual(try JSONHistory.parse(messages, agent: agent, filename: "api_conversation_history.json").messages, 1)
      XCTAssertThrowsError(try JSONHistory.parse(messages, agent: agent, filename: "settings.json"))
    }
    XCTAssertThrowsError(try JSONHistory.parse(gemini, agent: "continue", filename: "a.json"))
    XCTAssertThrowsError(try JSONHistory.parse(#"{"sessionId":"one","messages":[{"type":"user","content":42}]}"#, agent: "gemini", filename: "a.json"))
  }
  func testGeminiJSONLRetainsPatchesWithoutApplyingThem() throws {
    let text = "{\"sessionId\":\"one\"}\n{\"type\":\"user\",\"content\":\"never delete\"}\n{\"$set\":{\"summary\":\"unknown\"}}"
    let result = try NativeHistory.parse(text, agent: "gemini")
    XCTAssertEqual(result.messages, 1); XCTAssertTrue(result.numbered.contains("summary"))
    XCTAssertThrowsError(try NativeHistory.parse(text + "\n{\"sessionId\":\"two\"}", agent: "gemini"))
  }
  func testQuarantineRelocationAndCorruptSourceRefusal() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/OxyRelocationQA-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    let source = root.appendingPathComponent("file.txt"); try Data("payload".utf8).write(to: source)
    let entry = try store.move(FileRecord.read(source))
    let target = root.appendingPathComponent("other"); try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try store.relocate(entry, to: target)
    let relocated = try XCTUnwrap(store.entries().first)
    XCTAssertNotNil(relocated.externalPayload)
    try store.restore(relocated)
    XCTAssertEqual(try String(contentsOf: source), "payload")
    let again = try store.move(FileRecord.read(source))
    let payload = store.root.appendingPathComponent(again.id.uuidString + "/payload")
    try Data("changed".utf8).write(to: payload)
    XCTAssertThrowsError(try store.relocate(again, to: target))
    XCTAssertTrue(FileManager.default.fileExists(atPath: payload.path))
  }
  func testUpdateBackupLatestProtectedAndUnknownFoldersExcluded() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<3 {
      let folder = root.appendingPathComponent(".OxyMacUpdate-" + UUID().uuidString)
      let contents = folder.appendingPathComponent("previous.app/Contents")
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
      let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"com.oxyfire.OxyMacCleaner", "CFBundleShortVersionString":"0.2.\(index)"], format: .xml, options: 0)
      try data.write(to: contents.appendingPathComponent("Info.plist"))
      let healthy = folder.appendingPathComponent("healthy"); try Data("ready".utf8).write(to: healthy)
      try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970: Double(index))], ofItemAtPath: healthy.path)
      if index == 2 { try Data("user data".utf8).write(to: folder.appendingPathComponent("unrecognized.txt")) }
    }
    let app = root.appendingPathComponent("OxyMac Cleaner.app")
    let list = try UpdateBackups.list(beside: app)
    XCTAssertEqual(list.count, 2); XCTAssertEqual(list[0].version, "0.2.1"); XCTAssertTrue(list[0].protected)
    XCTAssertFalse(list[1].protected)
    XCTAssertThrowsError(try UpdateBackups.trash(list[0], beside: app))
  }

}
