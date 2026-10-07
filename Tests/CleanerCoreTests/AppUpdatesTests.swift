import XCTest
@testable import CleanerCore
final class AppUpdatesTests: XCTestCase {
  func testVersionOrder() {
    XCTAssertTrue(AppRelease.newer("0.1.28", than: "0.1.9"))
    XCTAssertFalse(AppRelease.newer("0.1.9", than: "0.1.28"))
    XCTAssertFalse(AppRelease.newer("0.1.28", than: "0.1.28"))
    XCTAssertFalse(AppRelease.newer("garbage", than: "0.1.28"))
    for malformed in ["1.foo.2.3", "1..2.3", "-1.2.3", "1.2.3."] {
      XCTAssertFalse(AppRelease.newer(malformed, than: "0.1.28"))
    }
  }
  func testArchiveTraversalAndForeignRootsRejected() {
    XCTAssertNoThrow(try AppRelease.validateEntries("OxyMac Cleaner.app/Contents/Info.plist\n__MACOSX/._OxyMac Cleaner.app"))
    for path in ["../escape", "/tmp/escape", "OxyMac Cleaner.app/../../escape", "Other.app/file"] {
      XCTAssertThrowsError(try AppRelease.validateEntries(path))
    }
  }
  func testReleaseMustUseExactProjectAssetURLs() throws {
    func data(_ host: String) throws -> Data {
      try JSONSerialization.data(withJSONObject: [["draft": false, "tag_name": "v0.1.28", "assets": [
        ["name": "OxyMacCleaner-0.1.28-macOS-arm64.zip", "browser_download_url": "https://\(host)/Datastore24Kirill/OxyMacCleaner/releases/download/v0.1.28/OxyMacCleaner-0.1.28-macOS-arm64.zip"],
        ["name": "SHA256SUMS.txt", "browser_download_url": "https://\(host)/Datastore24Kirill/OxyMacCleaner/releases/download/v0.1.28/SHA256SUMS.txt"]]]])
    }
    let release = try XCTUnwrap(AppRelease.parse(data("github.com"), current: "0.1.27"))
    XCTAssertNil(try AppRelease.parse(data("example.com"), current: "0.1.27"))
    XCTAssertThrowsError(try release.expectedHash("bad  " + release.name))
    XCTAssertEqual(try release.expectedHash(String(repeating:"a",count:64) + "  " + release.name), String(repeating:"a",count:64))
  }
}
