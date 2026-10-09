import XCTest
@testable import CleanerCore

final class SemanticContextTests: XCTestCase {
  private func fact(_ text: String = "Keep originals", line: Int = 1, quote: String = "never delete originals") -> ContextFact {
    ContextFact(category: .constraint, text: text, line: line, quote: quote)
  }
  func testModelSelectsEvidenceButCannotRewriteItsQuotation() throws {
    let source = [ContextEvidence(line:42,text:"User: never delete originals")]
    let selected = try SemanticContext.resolve([.init(category:.constraint,text:"Keep originals",evidence:1)],source:source)
    XCTAssertEqual(selected.first?.line,42)
    XCTAssertEqual(selected.first?.quote,source[0].text)
    XCTAssertThrowsError(try SemanticContext.resolve([.init(category:.constraint,text:"Keep originals",evidence:2)],source:source))
    XCTAssertThrowsError(try SemanticContext.resolve([.init(category:.constraint,text:"Keep originals",evidence:0)],source:source))
  }
  func testSourceNavigationIgnoresQuotedReferenceInsideEarlierRecord() throws {
    let transcript = Transcript(source:URL(fileURLWithPath:"/test.md"),agent:"test",text:"Earlier log mentions [L3] as data\nsecond\nactual third line",digest:"fixture")
    let reader = try TranscriptReview(transcript)
    let offset = try XCTUnwrap(reader.findSourceLine(3))
    XCTAssertTrue(try reader.page(at:offset).text.hasPrefix("[L3] actual third line"))
    XCTAssertNil(try reader.findSourceLine(99))
  }
  func testReviewerPlaceholdersAndWrongOutputLanguageAreNotAccepted() throws {
    XCTAssertThrowsError(try SemanticContext.validateLanguage("short uncertainty",russian:false))
    XCTAssertThrowsError(try SemanticContext.validateLanguage("具体的解决方案",russian:true))
    XCTAssertThrowsError(try SemanticContext.validateLanguage("Pipeline status",russian:true))
    XCTAssertNoThrow(try SemanticContext.validateLanguage("Проверить статус pipeline",russian:true))
    XCTAssertNoThrow(try SemanticContext.validateLanguage("src/main.swift",russian:true,reference:true))
  }
  func testWarningReferencesDoNotPretendToCoverMissingClaims() {
    let output = SemanticContext.render(facts:[fact()],missing:[],concerns:["Review [L8]"],unrepresented:[9],agent:"test",digest:"fixture",russian:true)
    XCTAssertEqual(SemanticContext.claimReferences(in:output),[1])
    XCTAssertEqual(SemanticContext.claimReferences(in:output.replacingOccurrences(of:"- Keep originals [L1]",with:"")),[])
  }
  func testQuoteAndReferenceMustMatchSameSourceRecord() throws {
    let source = [ContextEvidence(line: 1, text: "User: never delete originals"), ContextEvidence(line: 2, text: "test FAILED")]
    XCTAssertNoThrow(try SemanticContext.validate([fact()], source: source))
    XCTAssertThrowsError(try SemanticContext.validate([fact(line: 2)], source: source))
    XCTAssertThrowsError(try SemanticContext.validate([fact(quote: "test PASSED")], source: source))
    XCTAssertThrowsError(try SemanticContext.validate([fact("Invented [L99]")], source: source))
  }
  func testReviewerCanRejectSupportedQuoteWithUnsupportedParaphrase() throws {
    let source = [ContextEvidence(line: 1, text: "test FAILED; next step fix test")]
    let invented = ContextFact(category: .test, text: "All tests passed", line: 1, quote: "test FAILED")
    let audit = SemanticContext.Verification(unsupported: [0], missing: [], concerns: [])
    XCTAssertTrue(try SemanticContext.apply(audit, to: [invented], source: source).isEmpty)
    XCTAssertThrowsError(try SemanticContext.apply(.init(unsupported: [1], missing: [], concerns: []), to: [invented], source: source))
    XCTAssertThrowsError(try SemanticContext.apply(.init(unsupported: [], missing: [fact(line: 99)], concerns: []), to: [invented], source: source))
  }
  func testPreparationKeepsLateTextAndRolesBeyondChunkBoundary() throws {
    let payload: [String: Any] = ["role":"user", "message":["content":[["type":"text", "text":String(repeating:"earlier details ", count:2500) + "instead keep Aurora forever password=Synthetic4821"]]]]
    let raw = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
    var transcript = Transcript(source: URL(fileURLWithPath:"/test.jsonl"), agent:"cursor", text:raw, digest:"fixture")
    transcript.nativeHistory = try NativeHistory.parse(raw, agent:"cursor")
    let result = try SemanticContext.prepare(transcript)
    XCTAssertGreaterThan(result.parts.count, 1)
    XCTAssertEqual(result.normalizedRecords, 1)
    XCTAssertTrue(result.parts.flatMap { $0 }.allSatisfy { $0.line == 1 && $0.text.contains("MESSAGE (user)") })
    let all = result.parts.flatMap { $0 }.map(\.text).joined()
    XCTAssertTrue(all.contains("instead keep Aurora forever"))
    XCTAssertFalse(all.contains("Synthetic4821"))
    XCTAssertEqual(transcript.text, raw)
  }
  func testCancelledPreparationAndMalformedJSONFail() throws {
    let token = Cancellation(); token.cancel()
    let transcript = Transcript(source: URL(fileURLWithPath:"/test.md"), agent:"test", text:"User: goal", digest:"fixture")
    XCTAssertThrowsError(try SemanticContext.prepare(transcript, cancellation: token))
    XCTAssertThrowsError(try SemanticContext.decode("{bad", as: SemanticContext.Selection.self))
    XCTAssertThrowsError(try SemanticContext.decode("{\"facts\":[{\"category\":\"invented\"}]}", as: SemanticContext.Selection.self))
  }
  func testRepeatedClaimsCollapseButConflictingClaimsRemain() {
    let facts = [fact(),fact(line: 2),fact("Delete originals",line:3)]
    let result = SemanticContext.render(facts:facts,missing:[],concerns:[],unrepresented:[4],agent:"test",digest:"abc",russian:false)
    XCTAssertEqual(result.components(separatedBy:"- Keep originals").count - 1,1)
    XCTAssertTrue(result.contains("[L1] [L2]")); XCTAssertTrue(result.contains("Delete originals [L3]"))
    XCTAssertTrue(result.contains("[L4]")); XCTAssertTrue(result.contains("semantic accuracy is not guaranteed"))
  }
  func testRelatedDecisionsAcrossPartsAreOnlyReviewHints() {
    let first = ContextFact(category:.decision,text:"Delete Aurora",line:1,quote:"User: requirement delete Aurora archive")
    let later = ContextFact(category:.constraint,text:"Keep Aurora",line:500,quote:"User: instead never delete Aurora archive")
    let result = SemanticContext.relatedDecisions([first,later],russian:false)
    XCTAssertTrue(result.contains { $0.contains("[L1] / [L500]") && $0.contains("not a proven conflict") })
  }
  func testStageCountsCompletedWorkInsteadOfElapsedTime() {
    XCTAssertNil(ContextStage(.preparing).fraction)
    XCTAssertEqual(ContextStage(.extracting,part:1,total:2).fraction,0)
    XCTAssertEqual(ContextStage(.verifying,part:1,total:2).fraction,0.25)
    XCTAssertEqual(ContextStage(.extracting,part:2,total:2,retry:true).fraction,0.5)
    XCTAssertEqual(ContextStage(.finished,part:2,total:2).fraction,1)
  }
}
