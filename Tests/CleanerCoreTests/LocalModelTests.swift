import XCTest

@testable import CleanerCore

final class LocalProtocol: URLProtocol {
  static var mode = "normal"
  static var paths: [String] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    XCTAssertEqual(request.url?.host, "127.0.0.1")
    let path = request.url!.path
    Self.paths.append(path)
    var body: [String: Any]
    switch path {
    case "/api/tags":
      body = [
        "models": [
          ["name": "qwen2.5:3b"], ["name": "remote:cloud"],
          ["name": "secret", "remote_host": "example.com"],
        ]
      ]
    case "/api/pull":
      body = Self.mode == "interrupted" ? ["status": "pulling", "completed": 5, "total": 10] : ["status": "success"]
    case "/api/show":
      body =
        Self.mode == "remote" ? ["remote_host": "example.com"] : ["details": ["format": "gguf"]]
    default:
      body =
        Self.mode == "empty"
        ? ["response": ""]
        : ["response": "# Goal\nPreserve user files [L1].\nNext: quarantine [L3]."]
    }
    if path == "/api/generate", ["retry", "invalid"].contains(Self.mode) {
      let count = Self.paths.filter { $0 == "/api/generate" }.count
      body = ["response": Self.mode == "retry" && count > 1 ? "[L1]" : "[L99999]"]
    }
    if path == "/api/generate", Self.mode.hasPrefix("semantic") {
      let count = Self.paths.filter { $0 == "/api/generate" }.count
      let response: String
      if count == 1 { response = #"{"facts":[{"category":"constraint","text":"Keep originals","evidence":1}]}"# }
      else if Self.mode == "semantic-bad-audit" { response = #"{"checks":[{"id":99,"supported":true}],"missingEvidence":[]}"# }
      else { response = #"{"checks":[{"id":0,"supported":true}],"missingEvidence":[]}"# }
      body = ["response":response]
    }
    let data = try! JSONSerialization.data(withJSONObject: body)
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
final class LocalModelTests: XCTestCase {
  var engine: LocalModel!
  override func setUp() {
    LocalProtocol.mode = "normal"
    LocalProtocol.paths = []
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LocalProtocol.self]
    engine = LocalModel(configuration: config)
  }
  func testInvalidSelectionRetriesOnlyOnceAndValidatesAgain() async throws {
    let transcript = Transcript(source: URL(fileURLWithPath: "/fixture.md"), agent: "test", text: "User: never delete originals", digest: "fixture")
    LocalProtocol.mode = "retry"
    let result = try await engine.summarize(transcript, model: "qwen2.5:3b", style: "test") { _ in }
    XCTAssertTrue(result.contains("never delete originals"))
    XCTAssertFalse(result.contains("L99999"))
    XCTAssertEqual(LocalProtocol.paths.filter { $0 == "/api/generate" }.count, 2)
    LocalProtocol.mode = "invalid"; LocalProtocol.paths = []
    do {
      _ = try await engine.summarize(transcript, model: "qwen2.5:3b", style: "test") { _ in }
      XCTFail("Repeated invalid citations accepted")
    } catch {}
    XCTAssertEqual(LocalProtocol.paths.filter { $0 == "/api/generate" }.count, 2)
  }
  func testSemanticPipelineReviewsEveryPartAndRejectsBrokenAudit() async throws {
    let transcript = Transcript(source: URL(fileURLWithPath:"/synthetic.md"), agent:"test", text:"User: never delete originals", digest:"fixture")
    LocalProtocol.mode = "semantic"
    let result = try await engine.semanticContext(transcript, model:"qwen2.5:3b", style:"Бережный", russian:false) { _ in }
    XCTAssertEqual(result.facts.count,1)
    XCTAssertTrue(result.unrepresented.isEmpty)
    XCTAssertTrue(result.text.contains("User: never delete originals"))
    XCTAssertEqual(SemanticContext.claimReferences(in:result.text),[1])
    XCTAssertEqual(LocalProtocol.paths.filter { $0 == "/api/generate" }.count,2)
    LocalProtocol.mode = "semantic-bad-audit"; LocalProtocol.paths = []
    do {
      _ = try await engine.semanticContext(transcript, model:"qwen2.5:3b", style:"Бережный", russian:false) { _ in }
      XCTFail("Invalid review accepted")
    } catch {}
    XCTAssertEqual(LocalProtocol.paths.filter { $0 == "/api/generate" }.count,3)
    XCTAssertEqual(transcript.text,"User: never delete originals")
  }
  func testPullProgressAndMissingTotals() throws {
    let progress = try ModelPullProgress.parse(Data(#"{"status":"pulling","completed":5,"total":10}"#.utf8))
    XCTAssertEqual(progress.fraction, 0.5)
    XCTAssertNil(try ModelPullProgress.parse(Data(#"{"status":"verifying sha256 digest"}"#.utf8)).fraction)
    XCTAssertThrowsError(try ModelPullProgress.parse(Data(#"{"error":"disk full"}"#.utf8)))
  }
  func testPullRequiresSuccessEvent() async throws {
    try await engine.pull("qwen2.5:7b") { _ in }
    LocalProtocol.mode = "interrupted"
    do { try await engine.pull("qwen2.5:7b") { _ in }; XCTFail("Incomplete stream accepted") } catch {}
  }
  func testModelsExcludeRemote() async throws {
    let list = try await engine.models()
    XCTAssertEqual(list, ["qwen2.5:3b"])
  }
  func testGenerateChecksLocalMetadata() async throws {
    let result = try await engine.generate("test", model: "qwen2.5:3b")
    XCTAssertTrue(result.contains("[L1]"))
    XCTAssertEqual(LocalProtocol.paths, ["/api/tags", "/api/show", "/api/generate"])
  }
  func testRejectRemoteBeforeSendingHistory() async {
    LocalProtocol.mode = "remote"
    do {
      _ = try await engine.generate("private history", model: "qwen2.5:3b")
      XCTFail("Remote model accepted")
    } catch {}
    XCTAssertFalse(LocalProtocol.paths.contains("/api/generate"))
  }
  func testRejectEmptyModelOutput() async {
    LocalProtocol.mode = "empty"
    do {
      _ = try await engine.generate("test", model: "qwen2.5:3b")
      XCTFail("Empty output accepted")
    } catch {}
  }
}
