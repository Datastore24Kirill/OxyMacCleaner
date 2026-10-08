import XCTest
@testable import CleanerCore

final class AttributionAcceptanceTests: XCTestCase {
  func pairs(_ text: String) throws -> [TranscriptReview.DecisionPair] {
    let reader = try TranscriptReview(Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: text, digest: "test"))
    return TranscriptReview.decisionPairs(in: try reader.reviewIndex().items)
  }
  func testExplicitRolesAndProjectsDoNotPromoteAssistantOrCrossProjectChanges() throws {
    XCTAssertTrue(try pairs("User: [project=YooGo] delete buildcache\nUser: [project=JCat] never delete buildcache").isEmpty)
    XCTAssertTrue(try pairs("User: delete buildcache\nAssistant: never delete buildcache").isEmpty)
    XCTAssertTrue(try pairs("Tool: requirement delete buildcache\nUser: never delete buildcache").isEmpty)
    let matching = try pairs("User: [project=YooGo] delete buildcache\nUser: [project=YooGo] never delete buildcache")
    XCTAssertEqual(matching.count, 1); XCTAssertTrue(matching[0].attributionKnown)
    XCTAssertEqual(matching[0].sharedTerms, ["buildcache"])
  }
  func testUnknownAttributionIsVisibleAndQuotedRoleIsNotAnAuthor() throws {
    let matching = try pairs("User: delete buildcache\nNever delete buildcache")
    XCTAssertEqual(matching.count, 1); XCTAssertFalse(matching[0].attributionKnown)
    XCTAssertNil(TranscriptReview.attribution("[L12] quoted User: delete buildcache").author)
    XCTAssertEqual(TranscriptReview.attribution("[L12] MESSAGE (assistant): {\"cwd\":\"/project\"}").author, "assistant")
    XCTAssertEqual(TranscriptReview.attribution("[L12] MESSAGE (user): {\"cwd\":\"/project\"}").project, "/project")
    XCTAssertNil(TranscriptReview.attribution("[L12] User: inspect /project/subdir").project)
  }
  func testEveryRecommendationExplainsOwnerConsequencesAndRecoveryInBothLanguages() {
    for key in ["archives", "derived", "simulators", "testSimulators", "worktrees", "projectData", "duplicates", "personal", "unknown"] {
      for ru in [true, false] {
        let value = CleanupExplanation.forSection(key, russian: ru)
        XCTAssertFalse(value.owner.isEmpty); XCTAssertFalse(value.consequence.isEmpty); XCTAssertFalse(value.recovery.isEmpty)
      }
    }
    XCTAssertTrue(CleanupExplanation.forSection("archives", russian: false).recovery.contains("irreversible"))
    XCTAssertTrue(CleanupExplanation.forSection("simulators", russian: false).recovery.contains("separate backup"))
  }
  func testRestoreCollisionThenRetryPreservesBothCopiesAndRefreshesScan() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/OxyRestoreRetry-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("document.txt")
    try Data("original".utf8).write(to: source)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    let entry = try store.move(FileRecord.read(source))
    try Data("replacement".utf8).write(to: source)
    XCTAssertThrowsError(try store.restore(entry))
    XCTAssertEqual(try String(contentsOf: source), "replacement")
    XCTAssertTrue(store.inspect(entry).payloadValid)
    let restored = root.appendingPathComponent("restored.txt")
    try store.restore(entry, destination: restored)
    XCTAssertEqual(try String(contentsOf: restored), "original")
    let report = Scanner.scan(roots: [root], excluded: [root.appendingPathComponent("quarantine").path], cancellation: Cancellation())
    XCTAssertEqual(Set(report.files.map(\.name)), ["document.txt", "restored.txt"])
    XCTAssertEqual(report.total, 19)
  }
}
