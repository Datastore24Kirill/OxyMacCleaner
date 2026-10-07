import XCTest

@testable import CleanerCore

final class ProjectDataTests: XCTestCase {
  var root: URL!
  let later = Date().addingTimeInterval(1000)
  override func setUpWithError() throws {
    root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Downloads/OxyProjectDataTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    _ = try GitWorktrees.git(root, ["init"], run: GitWorktrees.run)
    try Data("{\"dependencies\":{\"next\":\"15.0.0\"}}".utf8).write(
      to: root.appendingPathComponent("package.json"))
    try Data(".next/\nnode_modules/\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
    let cache = root.appendingPathComponent(".next/cache/webpack/default")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data("generated cache".utf8).write(to: cache.appendingPathComponent("0.pack"))
  }
  override func tearDownWithError() throws {
    if let root { try FileManager.default.removeItem(at: root) }
  }
  func run(_ exe: String, _ args: [String]) throws -> WorktreeCommandResult {
    if exe == "/usr/sbin/lsof" {
      return WorktreeCommandResult(status: 1, output: Data(), error: Data())
    }
    return try GitWorktrees.run(exe, args)
  }
  func item() throws -> ProjectDataItem {
    try XCTUnwrap(ProjectData.inventory(root).first { $0.cleanable })
  }
  func plan() throws -> ProjectDataPlan {
    try ProjectData.prepare(item(), exclusions: [], now: later, run: run, idle: {})
  }
  func testCleanupOnlyRemovesNarrowCacheAndKeepsProjectDependenciesAndServerCache() throws {
    let dependencies = root.appendingPathComponent("node_modules/custom")
    try FileManager.default.createDirectory(at: dependencies, withIntermediateDirectories: true)
    try Data("local edit".utf8).write(to: dependencies.appendingPathComponent("local.js"))
    let server = root.appendingPathComponent(".next/cache/fetch-cache")
    try FileManager.default.createDirectory(at: server, withIntermediateDirectories: true)
    try Data("server data".utf8).write(to: server.appendingPathComponent("data"))
    let items = try ProjectData.inventory(root)
    XCTAssertFalse(try XCTUnwrap(items.first { $0.rule == "Node dependencies" }).cleanable)
    try ProjectData.remove(plan(), exclusions: [], now: later, run: run, idle: {})
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent(".next/cache/webpack").path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: dependencies.appendingPathComponent("local.js").path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: server.appendingPathComponent("data").path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("package.json").path))
  }
  func testTrackedOrNotIgnoredDataCannotBeCleaned() throws {
    _ = try GitWorktrees.git(root, ["add", "-f", ".next/cache/webpack/default/0.pack"], run: run)
    XCTAssertThrowsError(try plan())
    _ = try GitWorktrees.git(
      root, ["rm", "--cached", ".next/cache/webpack/default/0.pack"], run: run)
    try Data().write(to: root.appendingPathComponent(".gitignore"))
    XCTAssertThrowsError(try plan())
  }
  func testChangedCacheOrProjectMetadataBlocksRemoval() throws {
    let prepared = try plan()
    try Data("{\"dependencies\":{\"next\":\"16.0.0\"}}".utf8).write(
      to: root.appendingPathComponent("package.json"))
    XCTAssertThrowsError(
      try ProjectData.remove(prepared, exclusions: [], now: later, run: run, idle: {}))
    let next = try plan()
    try Data("changed".utf8).write(
      to: root.appendingPathComponent(".next/cache/webpack/default/0.pack"))
    XCTAssertThrowsError(
      try ProjectData.remove(next, exclusions: [], now: later, run: run, idle: {}))
  }
  func testSecretsSymlinksAndRecentChangesBlock() throws {
    XCTAssertThrowsError(try ProjectData.prepare(item(), exclusions: [], run: run, idle: {}))
    let secret = root.appendingPathComponent(".next/cache/webpack/secret.p12")
    try Data("secret".utf8).write(to: secret)
    XCTAssertThrowsError(try plan())
    try FileManager.default.removeItem(at: secret)
    try FileManager.default.createSymbolicLink(
      at: secret, withDestinationURL: root.appendingPathComponent("package.json"))
    XCTAssertThrowsError(try plan())
  }
  func testActivityCancellationAndExclusionsBlock() throws {
    let value = try item()
    XCTAssertThrowsError(
      try ProjectData.prepare(value, exclusions: [value.id], now: later, run: run, idle: {}))
    XCTAssertThrowsError(
      try ProjectData.prepare(
        value, exclusions: [], now: later, run: run,
        idle: { throw CleanerError.message("Build active") }))
    let active: GitWorktrees.Runner = { exe, args in
      if exe == "/usr/sbin/lsof" {
        return WorktreeCommandResult(status: 0, output: Data("process".utf8), error: Data())
      }
      return try self.run(exe, args)
    }
    XCTAssertThrowsError(
      try ProjectData.prepare(value, exclusions: [], now: later, run: active, idle: {}))
    let prepared = try plan()
    let token = Cancellation()
    token.cancel()
    XCTAssertThrowsError(
      try ProjectData.remove(
        prepared, exclusions: [], cancellation: token, now: later, run: run, idle: {}))
  }
  func testUnknownProjectAndDependencyCleanupRejected() throws {
    try Data("{}".utf8).write(to: root.appendingPathComponent("package.json"))
    XCTAssertFalse(try ProjectData.inventory(root).first!.cleanable)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
    let dependency = try XCTUnwrap(
      ProjectData.inventory(root).first { $0.rule == "Node dependencies" })
    XCTAssertThrowsError(
      try ProjectData.prepare(dependency, exclusions: [], now: later, run: run, idle: {}))
  }
  func testRustKeepsBuildProducts() throws {
    try Data("[package]\nname = \"fixture\"".utf8).write(to: root.appendingPathComponent("Cargo.toml"))
    try Data("target/\n.next/\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
    let cache = root.appendingPathComponent("target/debug/incremental")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: root.appendingPathComponent("target/.rustc_info.json"))
    try Data("cache".utf8).write(to: cache.appendingPathComponent("x.bin"))
    let product = root.appendingPathComponent("target/debug/program")
    try Data("product".utf8).write(to: product)
    let value = try XCTUnwrap(ProjectData.inventory(root).first { $0.rule.hasPrefix("Rust") })
    let prepared = try ProjectData.prepare(value, exclusions: [], now: later, run: run, idle: {})
    try ProjectData.remove(prepared, exclusions: [], now: later, run: run, idle: {})
    XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: product.path))
  }

}
