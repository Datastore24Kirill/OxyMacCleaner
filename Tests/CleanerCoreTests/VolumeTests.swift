import XCTest

@testable import CleanerCore

final class VolumeTests: XCTestCase {
  func testVolumeVisibility() {
    XCTAssertTrue(Volumes.visiblePath("/"))
    XCTAssertTrue(Volumes.visiblePath("/Volumes/External"))
    XCTAssertFalse(Volumes.visiblePath("/System/Volumes/Data"))
    XCTAssertFalse(Volumes.visiblePath("/dev"))
  }
  func testStartupExcludesDuplicateNamespacesAndExternalMounts() {
    let e = Volumes.exclusions(
      for: URL(fileURLWithPath: "/"),
      mounted: [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Volumes/Test")])
    XCTAssertTrue(e.contains("/System/Volumes"))
    XCTAssertTrue(e.contains("/Volumes"))
    XCTAssertFalse(e.contains("/"))
  }
  func testExternalVolumeDoesNotExcludeItselfOrSiblings() {
    let root = URL(fileURLWithPath: "/Volumes/Test")
    let e = Volumes.exclusions(
      for: root,
      mounted: [
        root, URL(fileURLWithPath: "/Volumes/Test/Nested"), URL(fileURLWithPath: "/Volumes/Other"),
      ])
    XCTAssertEqual(e, ["/Volumes/Test/Nested"])
  }
}
