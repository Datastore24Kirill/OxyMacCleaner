import XCTest

@testable import CleanerCore

final class DeveloperCleanupTests: XCTestCase {
  let id = "11111111-1111-1111-1111-111111111111"
  let runtimeID = "22222222-2222-2222-2222-222222222222"
  func deviceJSON(state: String = "Shutdown", present: Bool = true, available: Bool = false) throws
    -> Data
  {
    try JSONSerialization.data(withJSONObject: [
      "devices": [
        "runtime": present
          ? [["udid": id, "name": "iPhone", "state": state, "isAvailable": available]] : []
      ]
    ])
  }
  func runtimeJSON(present: Bool = true, deletable: Bool = true) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: present
        ? [
          runtimeID: [
            "identifier": runtimeID, "runtimeIdentifier": "runtime", "version": "17.0",
            "build": "A1", "state": "Ready", "deletable": deletable, "sizeBytes": 500,
            "lastUsedAt": "2020-01-01T00:00:00Z",
          ]
        ] : [:])
  }
  func testMissingTestSetIsEmptyButFileAndSymlinkAreErrors() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    XCTAssertFalse(try TestSimulators.exists(root))
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    XCTAssertTrue(try TestSimulators.exists(root))
    let file = root.appendingPathComponent("file")
    try Data().write(to: file)
    XCTAssertThrowsError(try TestSimulators.exists(file))
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    XCTAssertThrowsError(try TestSimulators.exists(link))
  }
  func testTestDeviceDeletionNeverTargetsDefaultSet() throws {
    var calls: [[String]] = []
    var removed = false
    XCTAssertTrue(try TestSimulators.remove(id, run: { args in
      calls.append(args)
      XCTAssertEqual(Array(args.prefix(2)), ["--set", TestSimulators.root.path])
      if args.contains("delete") { removed = true; XCTAssertEqual(args.last, self.id); return Data() }
      return try self.deviceJSON(present: !removed)
    }, idle: {}))
    XCTAssertEqual(calls.count, 3)
  }
  func testTestDevicesBlockActiveStateAndInvalidIDs() throws {
    for state in ["Booted", "Booting", "Unknown"] {
      XCTAssertThrowsError(try TestSimulators.remove(id, run: { args in
        XCTAssertFalse(args.contains("delete"))
        return try self.deviceJSON(state: state)
      }, idle: {}))
    }
    XCTAssertThrowsError(try TestSimulators.remove("all", run: { _ in
      XCTFail("Invalid ID must not run simctl"); return Data()
    }, idle: {}))
    XCTAssertThrowsError(try TestSimulators.remove(id, run: { _ in
      XCTFail("Active test must not run simctl"); return Data()
    }, idle: { throw CleanerError.message("Active tests") }))
  }
  func testDeviceDeleteUsesExactIDAndRefreshes() throws {
    var calls: [[String]] = []
    var removed = false
    let result = try Simulators.removeDevice(
      id,
      run: { args in
        calls.append(args)
        if args == ["delete", self.id] {
          removed = true
          return Data()
        }
        return try self.deviceJSON(present: !removed)
      }, idle: {})
    XCTAssertTrue(result)
    XCTAssertEqual(
      calls, [["list", "devices", "--json"], ["delete", id], ["list", "devices", "--json"]])
  }
  func testBootedUnknownAndAliasDeletionBlocked() throws {
    for state in ["Booted", "Booting", "Unknown"] {
      var deleted = false
      XCTAssertThrowsError(
        try Simulators.removeDevice(
          id,
          run: { args in
            if args.first == "delete" { deleted = true }
            return try self.deviceJSON(state: state)
          }, idle: {}))
      XCTAssertFalse(deleted)
    }
    XCTAssertThrowsError(
      try Simulators.removeDevice(
        "all",
        run: { _ in
          XCTFail("No tool should run for invalid ID")
          return Data()
        }, idle: {}))
  }
  func testRuntimeDeleteBlockedWhenAssociatedDeviceBooted() throws {
    var deleted = false
    XCTAssertThrowsError(
      try Simulators.removeRuntime(
        runtimeID,
        run: { args in
          if args.contains("delete") { deleted = true }
          return args.first == "list"
            ? try self.deviceJSON(state: "Booted") : try self.runtimeJSON()
        }, idle: {}))
    XCTAssertFalse(deleted)
  }
  func testRuntimeDeletionCanRemainPending() throws {
    var calls: [[String]] = []
    let done = try Simulators.removeRuntime(
      runtimeID,
      run: { args in
        calls.append(args)
        if args.contains("delete") { return Data() }
        return args.first == "list" ? try self.deviceJSON() : try self.runtimeJSON()
      }, idle: {})
    XCTAssertFalse(done)
    XCTAssertTrue(calls.contains(["runtime", "delete", runtimeID]))
  }
  func testMalformedOrUnsupportedInventoryFailsClosed() throws {
    XCTAssertThrowsError(try Simulators.devices(Data("{}".utf8)))
    let inventory = try Simulators.inventory { args in
      if args.first == "list" { return try self.deviceJSON() }
      throw CleanerError.message("unsupported")
    }
    XCTAssertEqual(inventory.devices.count, 1)
    XCTAssertTrue(inventory.runtimes.isEmpty)
    XCTAssertNotNil(inventory.runtimeIssue)
  }
  func testIdleGuardPreventsAllSimulatorCommands() throws {
    XCTAssertThrowsError(
      try Simulators.removeDevice(
        id,
        run: { _ in
          XCTFail("Must not run")
          return Data()
        }, idle: { throw CleanerError.message("Build active") }))
    XCTAssertEqual(
      DeveloperActivity.blockers(
        "/Applications/Xcode.app/Contents/MacOS/Xcode\n/usr/bin/clang\n/usr/bin/ps\n/usr/bin/clang"),
      ["Xcode", "clang"])
  }
  func testRuntimeAgeAndProtection() throws {
    let runtime = try XCTUnwrap(Simulators.runtimeImages(runtimeJSON()).first)
    XCTAssertTrue(runtime.unused(days: 90))
    XCTAssertTrue(Simulators.canRemove(runtime, devices: []))
    let protected = try XCTUnwrap(Simulators.runtimeImages(runtimeJSON(deletable: false)).first)
    XCTAssertFalse(Simulators.canRemove(protected, devices: []))
  }
  func testDerivedPathAllowlistAndSensitiveContents() {
    let base = DerivedData.root.appendingPathComponent("Project-hash")
    XCTAssertTrue(DerivedData.allowed(base.appendingPathComponent("Index.noindex")))
    for path in ["SourcePackages", "Build/Products", "Build", "Sources", "Index.noindex/nested"] {
      XCTAssertFalse(DerivedData.allowed(base.appendingPathComponent(path)))
    }
    XCTAssertTrue(DerivedData.protectedContent(base.appendingPathComponent("Logs/.env").path))
    XCTAssertTrue(
      DerivedData.protectedContent(base.appendingPathComponent("Logs/.git/config").path))
  }
  func testDerivedAssociationAndQuarantineRoundTrip() throws {
    let project = DerivedData.root.appendingPathComponent("OxyTests-" + UUID().uuidString)
    let cache = project.appendingPathComponent("Logs")
    let backup = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OxyDerivedStore-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: project)
      try? FileManager.default.removeItem(at: backup)
    }
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["WorkspacePath": "/example/App.xcworkspace"], format: .binary, options: 0)
    try data.write(to: project.appendingPathComponent("info.plist"))
    let file = cache.appendingPathComponent("build.log")
    try Data("fixture".utf8).write(to: file)
    for url in [file, cache] {
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: url.path)
    }
    let values = try DerivedData.inventory(
      base: project.deletingLastPathComponent(), cancellation: Cancellation(),
      projectName: project.lastPathComponent
    ).filter { $0.path == cache.path }
    let value = try XCTUnwrap(values.first)
    XCTAssertEqual(value.project, "App")
    let plan = try DerivedData.prepare(value, idle: {})
    let store = try QuarantineStore(root: backup.resolvingSymlinksInPath())
    XCTAssertThrowsError(
      try store.moveDerivedData(plan, idle: { throw CleanerError.message("Build started") }))
    let entry = try store.moveDerivedData(plan, idle: {})
    try store.restore(entry)
    XCTAssertEqual(try Data(contentsOf: file), Data("fixture".utf8))
    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    XCTAssertThrowsError(try DerivedData.prepare(value, idle: {}))
  }
  func testDirectCacheDeletionGuardsAndPreservesProject() throws {
    let project = DerivedData.root.appendingPathComponent("OxyTests-" + UUID().uuidString)
    let cache = project.appendingPathComponent("Index.noindex")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: project) }
    let metadata = project.appendingPathComponent("info.plist")
    try Data("keep metadata".utf8).write(to: metadata)
    let file = cache.appendingPathComponent("index")
    try Data("fixture".utf8).write(to: file)
    for path in [file, cache] {
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: path.path)
    }
    let plan = DerivedDataPlan(source: cache, manifest: try DirectoryManifest.capture(cache))
    XCTAssertThrowsError(try DerivedData.delete(plan, protectedPaths: [file.path], idle: {}))
    XCTAssertThrowsError(
      try DerivedData.delete(plan, idle: { throw CleanerError.message("Build active") }))
    let token = Cancellation()
    token.cancel()
    XCTAssertThrowsError(try DerivedData.delete(plan, cancellation: token, idle: {}))
    let unknown = DerivedDataPlan(source: project, manifest: try DirectoryManifest.capture(project))
    XCTAssertThrowsError(try DerivedData.delete(unknown, idle: {}))
    try DerivedData.delete(plan, idle: {})
    XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    XCTAssertEqual(try Data(contentsOf: metadata), Data("keep metadata".utf8))
  }
  func testDirectCacheDeletionRejectsChangedContents() throws {
    let project = DerivedData.root.appendingPathComponent("OxyTests-" + UUID().uuidString)
    let cache = project.appendingPathComponent("Logs")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: project) }
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: cache.path)
    let plan = DerivedDataPlan(source: cache, manifest: try DirectoryManifest.capture(cache))
    try Data("new log".utf8).write(to: cache.appendingPathComponent("new.log"))
    XCTAssertThrowsError(try DerivedData.delete(plan, idle: {}))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: cache.appendingPathComponent("new.log").path))
  }

}
