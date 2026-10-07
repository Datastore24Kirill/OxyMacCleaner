import XCTest
@testable import CleanerCore

final class SimulatorActivityTests: XCTestCase {
  let first = "9086C055-6805-481C-9346-3DF51A0F4933"
  let second = "11111111-1111-1111-1111-111111111111"
  func testExplicitDestinationsAndMultipleDestinations() throws {
    XCTAssertEqual(try SimulatorActivity.destinations("xcodebuild -workspace A B -destination platform=iOS Simulator,id=\(first) -parallel-testing-enabled NO test"), [first])
    XCTAssertEqual(try SimulatorActivity.destinations("xcodebuild -destination id=\(first.lowercased()) -destination platform=iOS Simulator,id=\(second) test"), [first, second])
  }
  func testAmbiguousDestinationsFailClosed() {
    for args in ["xcodebuild test", "xcodebuild -destination platform=iOS Simulator,name=iPhone 17 test", "xcodebuild -destination id=all", "xcodebuild -destination id=\(first) -destination name=iPhone"] {
      XCTAssertThrowsError(try SimulatorActivity.destinations(args))
    }
  }
  func testAssociatedTestsProtectOnlyTheirDestination() throws {
    let processes = [
      SimulatorActivity.ProcessInfo(pid: 1, parent: 0, name: "xcodebuild", arguments: "xcodebuild -destination id=\(first) test"),
      SimulatorActivity.ProcessInfo(pid: 2, parent: 1, name: "helper"),
      SimulatorActivity.ProcessInfo(pid: 3, parent: 2, name: "xctest"),
      SimulatorActivity.ProcessInfo(pid: 4, parent: 0, name: "swift-frontend")
    ]
    let protected = try SimulatorActivity.protectedDevices(processes)
    XCTAssertTrue(protected.contains(first))
    XCTAssertFalse(protected.contains(second))
  }
  func testOrphanTestGUIAndAncestryLoopFailClosed() {
    XCTAssertThrowsError(try SimulatorActivity.protectedDevices([.init(pid: 1, parent: 0, name: "xctest")]))
    XCTAssertThrowsError(try SimulatorActivity.protectedDevices([.init(pid: 1, parent: 0, name: "Xcode")]))
    XCTAssertThrowsError(try SimulatorActivity.protectedDevices([.init(pid: 1, parent: 2, name: "xctest"), .init(pid: 2, parent: 1, name: "helper")]))
  }
  func testDeviceAndRuntimeAssociationProtects27ButAllows26() throws {
    let processes = [SimulatorActivity.ProcessInfo(pid: 1, parent: 0, name: "xcodebuild", arguments: "xcodebuild -destination id=\(first) test")]
    XCTAssertNoThrow(try SimulatorActivity.assertDeviceIdle(second, processes: processes))
    XCTAssertThrowsError(try SimulatorActivity.assertDeviceIdle(first, processes: processes))
    let data = try JSONSerialization.data(withJSONObject: ["devices": ["iOS-27": [["udid": first, "name": "QA", "state": "Shutdown", "isAvailable": true]]]])
    let devices = try Simulators.devices(data)
    XCTAssertNoThrow(try SimulatorActivity.assertRuntimeIdle("iOS-26", devices: devices, processes: processes))
    XCTAssertThrowsError(try SimulatorActivity.assertRuntimeIdle("iOS-27", devices: devices, processes: processes))
    XCTAssertThrowsError(try SimulatorActivity.assertRuntimeIdle("iOS-26", devices: [], processes: processes))
  }
  func testCompilerAloneDoesNotBlockSimulators() throws {
    XCTAssertTrue(try SimulatorActivity.protectedDevices([.init(pid: 1, parent: 0, name: "swift-build"), .init(pid: 2, parent: 1, name: "clang")]).isEmpty)
  }
}
