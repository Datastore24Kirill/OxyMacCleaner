import XCTest
@testable import CleanerCore

final class PlanCompletionTests: XCTestCase {
  func testDecisionPairsAcrossReadChunksKeepBothOffsetsWithoutDecidingWinner() throws {
    let source = "User: delete buildcache\n" + String(repeating: "ordinary text\n", count: 12000) + "Cancel my request: never delete buildcache\n"
    let reader = try TranscriptReview(Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: source, digest: "test"))
    let findings = try reader.reviewIndex()
    let pairs = TranscriptReview.decisionPairs(in: findings.items)
    XCTAssertEqual(pairs.count, 1)
    let pair = try XCTUnwrap(pairs.first)
    XCTAssertGreaterThan(pair.later.offset, 128000)
    XCTAssertEqual(pair.sharedTerms, ["buildcache"])
    XCTAssertTrue(try reader.page(at: pair.earlier.offset).text.hasPrefix("[L1] User:"))
    XCTAssertTrue(try reader.page(at: pair.later.offset).text.contains("Cancel my request"))
  }
  func testUnrelatedDecisionsDoNotPairAndCancelledReviewThrows() throws {
    let reader = try TranscriptReview(Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: "User: delete buildcache\nNever delete photographs", digest: "test"))
    XCTAssertTrue(TranscriptReview.decisionPairs(in: try reader.reviewIndex().items).isEmpty)
    let token = Cancellation(); token.cancel()
    XCTAssertThrowsError(try reader.reviewIndex(cancellation: token))
  }
  func testNewDependencyCatalogIsReadOnlyAndDoesNotDescendIntoVendor() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/OxyCatalogQA-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for marker in ["composer.json", "Gemfile", "settings.gradle", "settings.gradle.kts", "pom.xml", "requirements.txt", "pyproject.toml"] {
      try Data("{}".utf8).write(to: root.appendingPathComponent(marker))
    }
    for folder in ["vendor/bundle", ".gradle", "target", ".venv"] {
      let url = root.appendingPathComponent(folder)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try Data("local modifications".utf8).write(to: url.appendingPathComponent("keep"))
    }
    try Data("{}".utf8).write(to: root.appendingPathComponent("vendor/package.json"))
    let items = try ProjectData.inventory(root)
    XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    XCTAssertEqual(items.count, 4)
    for item in items {
      XCTAssertFalse(item.cleanable)
      XCTAssertThrowsError(try ProjectData.prepare(item, exclusions: [], idle: {}))
      XCTAssertTrue(FileManager.default.fileExists(atPath: item.id))
      XCTAssertTrue(ProjectData.evidence(for: item, russian: false).contains("Marker:"))
    }
    let projects = ProjectDiscovery.discover(root)
    XCTAssertEqual(projects.projects.count, 1)
    XCTAssertTrue(projects.projects[0].markers.contains("composer.json"))
  }
  func testDeviceRuntimeIdentifiersAndUnknownActiveAssociationStayProtected() throws {
    let uuid = "9086C055-6805-481C-9346-3DF51A0F4933"
    for runtime in ["com.apple.CoreSimulator.SimRuntime.iOS-18-5", "com.apple.CoreSimulator.SimRuntime.iOS-26-0", "com.apple.CoreSimulator.SimRuntime.watchOS-26-0"] {
      let data = try JSONSerialization.data(withJSONObject: ["devices": [runtime: [["udid": uuid, "name": "Fixture", "state": "Shutdown", "isAvailable": true]]]])
      let devices = try Simulators.devices(data)
      let active = [SimulatorActivity.ProcessInfo(pid: 10, parent: 0, name: "xcodebuild", arguments: "xcodebuild -destination id=\(uuid) test")]
      XCTAssertThrowsError(try SimulatorActivity.assertRuntimeIdle(runtime, devices: devices, processes: active))
      XCTAssertThrowsError(try SimulatorActivity.assertRuntimeIdle(runtime, devices: [], processes: active))
      XCTAssertNoThrow(try SimulatorActivity.assertRuntimeIdle(runtime, devices: devices, processes: []))
    }
  }
  func testFailureGuidanceExistsInBothLanguages() {
    for message in ["Permission denied", "Project changed after confirmation", "Protected data", "xcodebuild active"] {
      for ru in [true, false] {
        let presented = ErrorPresentation.message(message, russian: ru)
        XCTAssertTrue(presented.contains(message))
        XCTAssertGreaterThan(presented.count, message.count)
      }
    }
  }
}
