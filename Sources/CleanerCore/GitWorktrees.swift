import Foundation

public struct GitTree: Identifiable, Equatable, Sendable {
  public var id: String { path }
  public let path: String
  public let head: String
  public let branch: String
  public let primary: Bool
  public let locked: Bool
  public let prunable: Bool
}
public struct WorktreeReview: Identifiable, Sendable {
  public var id: String { tree.path }
  public let tree: GitTree
  public let repository: URL
  public let bytes: Int64?
  public let modified: Date?
  public let blockers: [String]
  public var eligible: Bool { blockers.isEmpty }
}
public struct WorktreePlan: Sendable {
  public let review: WorktreeReview
  let manifest: DirectoryManifest
}
public struct WorktreeCommandResult: Sendable {
  public let status: Int32
  public let output: Data
  public let error: Data
}
public enum GitWorktrees {
  public typealias Runner = (String, [String]) throws -> WorktreeCommandResult
  public static func run(_ executable: String, _ arguments: [String]) throws
    -> WorktreeCommandResult
  {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("oxy-git-" + UUID().uuidString)
    try fm.createDirectory(
      at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: folder) }
    let out = folder.appendingPathComponent("out")
    let err = folder.appendingPathComponent("err")
    fm.createFile(atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600])
    fm.createFile(atPath: err.path, contents: nil, attributes: [.posixPermissions: 0o600])
    let stdout = try FileHandle(forWritingTo: out)
    let stderr = try FileHandle(forWritingTo: err)
    defer {
      try? stdout.close()
      try? stderr.close()
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    // Do not inherit Git directory/index overrides from a launcher or development shell.
    process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let deadline = Date().addingTimeInterval(60)
    while process.isRunning {
      if Date() > deadline {
        process.terminate()
        throw CleanerError.message("Inspection timed out; removal blocked")
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    for file in [out, err] {
      guard
        (try fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0 < 16_000_000
      else { throw CleanerError.message("Inspection output too large; removal blocked") }
    }
    return WorktreeCommandResult(
      status: process.terminationStatus, output: try Data(contentsOf: out),
      error: try Data(contentsOf: err))
  }
  static func git(_ repo: URL, _ args: [String], run: Runner) throws -> Data {
    let result = try run(
      "/usr/bin/git",
      [
        "--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C",
        repo.path,
      ] + args)
    guard result.status == 0 else {
      throw CleanerError.message(
        "Git: " + String(decoding: result.error.prefix(1500), as: UTF8.self))
    }
    return result.output
  }
  public static func parse(_ data: Data) throws -> [GitTree] {
    guard let text = String(data: data, encoding: .utf8), text.hasSuffix("\0\0") else {
      throw CleanerError.message("Unsupported worktree list; removal blocked")
    }
    var result: [GitTree] = []
    for record in text.components(separatedBy: "\0\0") where !record.isEmpty {
      let fields = record.components(separatedBy: "\0")
      guard let first = fields.first, first.hasPrefix("worktree /"),
        let head = fields.first(where: { $0.hasPrefix("HEAD ") })
      else {
        throw CleanerError.message("Bare or unknown repository format is analysis-only")
      }
      let path = String(first.dropFirst(9))
      guard !result.contains(where: { $0.path == path }) else {
        throw CleanerError.message("Duplicate worktree path")
      }
      result.append(
        GitTree(
          path: path, head: String(head.dropFirst(5)),
          branch: fields.first(where: { $0.hasPrefix("branch ") }).map { String($0.dropFirst(7)) }
            ?? "HEAD (detached)",
          primary: result.isEmpty,
          locked: fields.contains(where: { $0 == "locked" || $0.hasPrefix("locked ") }),
          prunable: fields.contains(where: { $0 == "prunable" || $0.hasPrefix("prunable ") })))
    }
    return result
  }
  public static func list(_ repo: URL, run: Runner = run) throws -> [GitTree] {
    try parse(git(repo, ["worktree", "list", "--porcelain", "-z"], run: run))
  }
  static func locationAllowed(_ source: URL) -> Bool {
    let components = source.standardizedFileURL.pathComponents.map { $0.lowercased() }
    let blocked: Set<String> = [
      "library", ".git", ".ssh", ".gnupg", ".aws", ".azure", ".config", "keychains",
    ]
    guard blocked.isDisjoint(with: components),
      !components.contains(where: {
        ["app", "photoslibrary", "xcarchive", "sparsebundle"].contains(
          URL(fileURLWithPath: $0).pathExtension)
      })
    else { return false }
    let path =
      components.count >= 3 && components[1] == "volumes"
      ? "/" + components.dropFirst(3).joined(separator: "/") : source.path.lowercased()
    return ![
      "/system", "/library", "/applications", "/usr", "/bin", "/sbin", "/private", "/dev", "/etc",
      "/var", "/opt",
    ].contains { Scanner.inside(path, $0) }
  }
  static func assertInactive(_ source: URL, run: Runner) throws {
    let result = try run("/usr/sbin/lsof", ["-n", "-P", "+D", source.path])
    // lsof exit 1 with no output means no matching handles. Warnings mean incomplete visibility.
    guard result.status == 1, result.output.isEmpty, result.error.isEmpty else {
      throw CleanerError.message("Open files/processes detected, or activity could not be verified")
    }
  }
  public static func inspect(
    _ tree: GitTree, repository: URL, exclusions: [String],
    cancellation: Cancellation = Cancellation(), now: Date = Date(), run: Runner = run
  ) -> WorktreeReview {
    var blockers: [String] = []
    var bytes: Int64?
    var modified: Date?
    if tree.primary { blockers.append("Основное рабочее дерево / Main worktree") }
    if tree.locked { blockers.append("Заблокировано в Git / Locked in Git") }
    if tree.prunable { blockers.append("Путь недоступен или устарел / Missing or stale path") }
    let source = URL(fileURLWithPath: tree.path).standardizedFileURL
    if exclusions.contains(where: {
      Scanner.inside(source.path, $0) || Scanner.inside($0, source.path)
    }) {
      blockers.append("Пользовательское исключение / User exclusion")
    }
    do {
      try cancellation.check()
      guard locationAllowed(source), source.path == tree.path,
        source.resolvingSymlinksInPath() == source,
        source.path != "/", source.path != FileManager.default.homeDirectoryForCurrentUser.path
      else {
        throw CleanerError.message("Noncanonical or protected root")
      }
      guard blockers.isEmpty else {
        return WorktreeReview(
          tree: tree, repository: repository, bytes: nil, modified: nil, blockers: blockers)
      }
      func value(_ directory: URL, _ arguments: [String]) throws -> String {
        let data = try git(directory, arguments, run: run)
        guard var text = String(data: data, encoding: .utf8), text.hasSuffix("\n") else {
          throw CleanerError.message("Unknown Git response")
        }
        text.removeLast()
        return text
      }
      guard try value(source, ["rev-parse", "--show-toplevel"]) == source.path,
        try value(source, ["rev-parse", "HEAD"]) == tree.head,
        try value(source, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
          == value(repository, ["rev-parse", "--path-format=absolute", "--git-common-dir"]),
        repository.standardizedFileURL.path != source.path
      else {
        throw CleanerError.message("Repository identity mismatch; removal blocked")
      }
      let common = try value(
        repository, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
      let gitDirectory = try value(source, ["rev-parse", "--absolute-git-dir"])
      guard
        Scanner.inside(
          gitDirectory, URL(fileURLWithPath: common).appendingPathComponent("worktrees").path)
      else {
        throw CleanerError.message("Not a registered linked worktree directory")
      }
      let backlink = URL(fileURLWithPath: gitDirectory).appendingPathComponent("gitdir")
      let record = try FileRecord.read(backlink)
      guard record.bytes < 65536 else { throw CleanerError.message("Invalid worktree backlink") }
      var target = try String(contentsOf: backlink, encoding: .utf8)
      if target.hasSuffix("\n") { target.removeLast() }
      try record.validate()
      guard target == source.appendingPathComponent(".git").path else {
        throw CleanerError.message("Worktree backlink does not match directory")
      }
      let scan = Scanner.scan(roots: [source], excluded: [], cancellation: cancellation)
      guard scan.complete, scan.issues.isEmpty else {
        throw CleanerError.message("Incomplete file inspection")
      }
      bytes = scan.total
      let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
      modified = max(
        scan.files.map(\.modified).max() ?? .distantPast, attrs[.modificationDate] as? Date ?? now)
      let status = try git(
        source, ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored"], run: run)
      guard status.isEmpty else {
        throw CleanerError.message(
          "Есть изменения, неотслеживаемые или ignored-файлы / Modified, untracked or ignored files"
        )
      }
      let flags = try git(source, ["ls-files", "-v", "-z"], run: run)
      guard
        String(decoding: flags, as: UTF8.self).split(separator: "\0").allSatisfy({
          $0.hasPrefix("H ")
        })
      else {
        throw CleanerError.message(
          "Special index flags: sparse/assume-unchanged state is protected")
      }
      let stages = try git(source, ["ls-files", "--stage", "-z"], run: run)
      guard
        !String(decoding: stages, as: UTF8.self).split(separator: "\0").contains(where: {
          $0.hasPrefix("160000 ")
        })
      else {
        throw CleanerError.message("Submodules are analysis-only")
      }
      let count = String(
        decoding: try git(source, ["rev-list", "--count", "HEAD", "--not", "--remotes"], run: run),
        as: UTF8.self
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      guard count == "0" else {
        throw CleanerError.message(
          "Локальные коммиты без remote-tracking ref / Commits not reachable from remote-tracking refs"
        )
      }
      guard modified! < now.addingTimeInterval(-30 * 86400) else {
        throw CleanerError.message("Изменения за последние 30 дней / Modified within 30 days")
      }
      try assertInactive(source, run: run)
      try cancellation.check()
    } catch { blockers.append(error.localizedDescription) }
    return WorktreeReview(
      tree: tree, repository: repository, bytes: bytes, modified: modified, blockers: blockers)
  }
  public static func prepare(
    _ review: WorktreeReview, exclusions: [String], cancellation: Cancellation = Cancellation(),
    now: Date = Date(), run: Runner = run
  ) throws -> WorktreePlan {
    guard let tree = try list(review.repository, run: run).first(where: { $0.path == review.id }),
      tree == review.tree
    else {
      throw CleanerError.message("Worktree registration changed; inspect again")
    }
    let fresh = inspect(
      tree, repository: review.repository, exclusions: exclusions, cancellation: cancellation,
      now: now, run: run)
    guard fresh.eligible else { throw CleanerError.message(fresh.blockers.joined(separator: "\n")) }
    let manifest = try DirectoryManifest.capture(
      URL(fileURLWithPath: tree.path), cancellation: cancellation)
    return WorktreePlan(review: fresh, manifest: manifest)
  }
  public static func remove(
    _ plan: WorktreePlan, exclusions: [String], cancellation: Cancellation = Cancellation(),
    now: Date = Date(), run: Runner = run
  ) throws {
    let current = try prepare(
      plan.review, exclusions: exclusions, cancellation: cancellation, now: now, run: run)
    guard current.manifest == plan.manifest else {
      throw CleanerError.message("Files changed after confirmation")
    }
    try assertInactive(URL(fileURLWithPath: plan.review.id), run: run)
    try cancellation.check()
    _ = try git(plan.review.repository, ["worktree", "remove", "--", plan.review.id], run: run)
    guard
      !(try list(plan.review.repository, run: run)).contains(where: { $0.path == plan.review.id }),
      !FileManager.default.fileExists(atPath: plan.review.id)
    else {
      throw CleanerError.message("Removal not confirmed; refresh inventory")
    }
  }
}
