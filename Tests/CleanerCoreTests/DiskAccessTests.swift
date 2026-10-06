import Darwin
import XCTest

@testable import CleanerCore

final class DiskAccessTests: XCTestCase {
  func testMissingDirectoriesDoNotImplyAccess() {
    XCTAssertEqual(DiskAccess.evaluate([.init(path: "missing", error: ENOENT)]).state, .unknown)
    XCTAssertEqual(DiskAccess.evaluate([]).state, .unknown)
  }
  func testOneDeniedDirectoryWinsOverSuccessfulProbe() {
    XCTAssertEqual(
      DiskAccess.evaluate([.init(path: "ok", error: 0), .init(path: "denied", error: EPERM)]).state,
      .limited)
    XCTAssertEqual(DiskAccess.evaluate([.init(path: "denied", error: EACCES)]).state, .limited)
  }
  func testUnexpectedFailureIsNotPermissionDenial() {
    XCTAssertEqual(DiskAccess.evaluate([.init(path: "disk", error: EIO)]).state, .unknown)
  }
  func testAvailableOnlyWhenExistingProbesSucceed() {
    XCTAssertEqual(
      DiskAccess.evaluate([.init(path: "ok", error: 0), .init(path: "absent", error: ENOENT)])
        .state, .available)
  }
}
