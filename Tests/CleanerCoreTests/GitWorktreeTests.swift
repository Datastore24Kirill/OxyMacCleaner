import XCTest

@testable import CleanerCore

final class GitWorktreeTests: XCTestCase {
  var root: URL!, repo: URL!, linked: URL!
  let future = Date().addingTimeInterval(40 * 86400)
  override func setUpWithError() throws {
    root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
      .appendingPathComponent(
        "OxyWorktreeTests-" + UUID().uuidString
      ).resolvingSymlinksInPath()
    repo = root.appendingPathComponent("repo")
    linked = root.appendingPathComponent("linked tree")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    _ = try command(repo, ["init"])
    _ = try command(repo, ["config", "user.name", "Fixture"])
    _ = try command(repo, ["config", "user.email", "fixture@example.invalid"])
    try Data("tracked\n".utf8).write(to: repo.appendingPathComponent("file.txt"))
    try Data("local.db\n".utf8).write(to: repo.appendingPathComponent(".gitignore"))
    _ = try command(repo, ["add", "."])
    _ = try command(repo, ["commit", "-m", "Fixture"])
    _ = try command(repo, ["update-ref", "refs/remotes/origin/main", "HEAD"])
    _ = try command(repo, ["worktree", "add", "-b", "fixture-branch", linked.path])
  }
  override func tearDownWithError() throws {
    if let root { try FileManager.default.removeItem(at: root) }
  }
  func command(_ directory: URL, _ arguments: [String]) throws -> Data {
    let result = try GitWorktrees.run(
      "/usr/bin/git",
      ["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-C", directory.path]
        + arguments)
    guard result.status == 0 else {
      throw CleanerError.message(String(decoding: result.error, as: UTF8.self))
    }
    return result.output
  }
  func runner(_ executable: String, _ args: [String]) throws -> WorktreeCommandResult {
    if executable == "/usr/sbin/lsof" {
      return WorktreeCommandResult(status: 1, output: Data(), error: Data())
    }
    return try GitWorktrees.run(executable, args)
  }
  func review() throws -> WorktreeReview {
    let tree = try XCTUnwrap(GitWorktrees.list(repo).first { $0.path == linked.path })
    return GitWorktrees.inspect(tree, repository: repo, exclusions: [], now: future, run: runner)
  }
  func testCleanTreeRemovalRetainsBranchAndMainRepository() throws {
    let value = try review()
    XCTAssertTrue(value.eligible, value.blockers.joined(separator: ";"))
    let plan = try GitWorktrees.prepare(value, exclusions: [], now: future, run: runner)
    try GitWorktrees.remove(plan, exclusions: [], now: future, run: runner)
    XCTAssertFalse(FileManager.default.fileExists(atPath: linked.path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: repo.appendingPathComponent("file.txt").path))
    _ = try command(repo, ["show-ref", "--verify", "refs/heads/fixture-branch"])
  }
  func testMainLockedRecentAndExcludedTreesBlocked() throws {
    let trees = try GitWorktrees.list(repo)
    XCTAssertFalse(
      GitWorktrees.inspect(trees[0], repository: repo, exclusions: [], now: future, run: runner)
        .eligible)
    XCTAssertFalse(
      GitWorktrees.inspect(trees[1], repository: repo, exclusions: [], run: runner).eligible)
    XCTAssertFalse(
      GitWorktrees.inspect(
        trees[1], repository: repo, exclusions: [linked.path], now: future, run: runner
      ).eligible)
    _ = try command(repo, ["worktree", "lock", linked.path])
    XCTAssertFalse(try review().eligible)
  }
  func testIgnoredAndUntrackedDataAreProtected() throws {
    for name in ["local.db", "new.txt"] {
      let path = linked.appendingPathComponent(name)
      try Data("unique".utf8).write(to: path)
      XCTAssertFalse(try review().eligible)
      try FileManager.default.removeItem(at: path)
    }
    try Data("modified".utf8).write(to: linked.appendingPathComponent("file.txt"))
    XCTAssertFalse(try review().eligible)
  }
  func testLocalCommitAndIndexFlagsBlocked() throws {
    _ = try command(linked, ["update-index", "--assume-unchanged", "file.txt"])
    XCTAssertFalse(try review().eligible)
    _ = try command(linked, ["update-index", "--no-assume-unchanged", "file.txt"])
    _ = try command(linked, ["commit", "--allow-empty", "-m", "Local only"])
    XCTAssertFalse(try review().eligible)
  }
  func testActivityUnknownAndChangedPlanBlockRemoval() throws {
    let value = try review()
    let active: GitWorktrees.Runner = { exe, args in
      if exe == "/usr/sbin/lsof" {
        return WorktreeCommandResult(status: 0, output: Data("process".utf8), error: Data())
      }
      return try self.runner(exe, args)
    }
    XCTAssertThrowsError(try GitWorktrees.prepare(value, exclusions: [], now: future, run: active))
    let warning: GitWorktrees.Runner = { exe, args in
      if exe == "/usr/sbin/lsof" {
        return WorktreeCommandResult(status: 1, output: Data(), error: Data("denied".utf8))
      }
      return try self.runner(exe, args)
    }
    XCTAssertThrowsError(try GitWorktrees.prepare(value, exclusions: [], now: future, run: warning))
    let plan = try GitWorktrees.prepare(value, exclusions: [], now: future, run: runner)
    try Data("new data".utf8).write(to: linked.appendingPathComponent("unique.txt"))
    XCTAssertThrowsError(try GitWorktrees.remove(plan, exclusions: [], now: future, run: runner))
    XCTAssertTrue(FileManager.default.fileExists(atPath: linked.path))
  }
  func testCancellationExclusionAndNewLockRevalidateBeforeRemoval() throws {
    let plan = try GitWorktrees.prepare(review(), exclusions: [], now: future, run: runner)
    let token = Cancellation()
    token.cancel()
    XCTAssertThrowsError(
      try GitWorktrees.remove(plan, exclusions: [], cancellation: token, now: future, run: runner))
    XCTAssertThrowsError(
      try GitWorktrees.remove(plan, exclusions: [linked.path], now: future, run: runner))
    _ = try command(repo, ["worktree", "lock", linked.path])
    XCTAssertThrowsError(try GitWorktrees.remove(plan, exclusions: [], now: future, run: runner))
    XCTAssertTrue(FileManager.default.fileExists(atPath: linked.path))
  }
  func testChangedGitPointerIsProtected() throws {
    try Data(("gitdir: " + repo.appendingPathComponent(".git").path + "\n").utf8)
      .write(to: linked.appendingPathComponent(".git"))
    XCTAssertFalse(try review().eligible)
  }
  func testSystemAndSensitiveLocationsAreNeverEligible() {
    for path in [
      "/System/tree", "/Users/test/Library/tree", "/Users/test/.ssh/tree",
      "/Volumes/Old Mac/usr/tree", "/Applications/Tool.app/tree",
    ] {
      XCTAssertFalse(GitWorktrees.locationAllowed(URL(fileURLWithPath: path)))
    }
    XCTAssertTrue(
      GitWorktrees.locationAllowed(URL(fileURLWithPath: "/Users/test/.codex/worktrees/task")))
  }
  func testNulParserKeepsNewlinePathsAndRejectsUnknownFormats() throws {
    let text =
      "worktree /a\nfolder\0HEAD abc\0branch refs/heads/main\0\0worktree /b\0HEAD def\0detached\0locked busy\0\0"
    let parsed = try GitWorktrees.parse(Data(text.utf8))
    XCTAssertEqual(parsed[0].path, "/a\nfolder")
    XCTAssertTrue(parsed[1].locked)
    XCTAssertThrowsError(try GitWorktrees.parse(Data("worktree /bare\0bare\0\0".utf8)))
    XCTAssertThrowsError(try GitWorktrees.parse(Data("worktree /a\0HEAD abc".utf8)))
  }
}
