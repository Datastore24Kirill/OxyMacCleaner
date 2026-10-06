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
    case "/api/show":
      body =
        Self.mode == "remote" ? ["remote_host": "example.com"] : ["details": ["format": "gguf"]]
    default:
      body =
        Self.mode == "empty"
        ? ["response": ""]
        : ["response": "# Goal\nPreserve user files [L1].\nNext: quarantine [L3]."]
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
