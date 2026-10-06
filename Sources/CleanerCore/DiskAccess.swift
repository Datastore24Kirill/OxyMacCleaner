import Darwin
import Foundation

/// A read-only capability probe, not an API for reading the macOS TCC permission database.
public enum DiskAccess {
  public enum State: Equatable, Sendable { case available, limited, unknown }
  public struct Check: Sendable {
    public let path: String
    public let error: Int32
    public init(path: String, error: Int32) {
      self.path = path
      self.error = error
    }
  }
  public struct Result: Sendable {
    public let state: State
    public let checks: [Check]
  }
  public static func evaluate(_ checks: [Check]) -> Result {
    let denied = checks.contains { $0.error == EACCES || $0.error == EPERM }
    // Missing locations cannot establish that access was granted.
    let present = checks.filter { $0.error != ENOENT && $0.error != ENOTDIR }
    let state: State =
      denied
      ? .limited : !present.isEmpty && present.allSatisfy { $0.error == 0 } ? .available : .unknown
    return Result(state: state, checks: checks)
  }
  public static func check(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Result {
    let checks = ["Library/Safari", "Library/Mail", "Library/Messages"].map { relative in
      let path = home.appendingPathComponent(relative).path
      // Open and close directory handles; do not read personal file contents or enumerate names.
      if let directory = opendir(path) {
        closedir(directory)
        return Check(path: path, error: 0)
      }
      return Check(path: path, error: errno)
    }
    return evaluate(checks)
  }
}
