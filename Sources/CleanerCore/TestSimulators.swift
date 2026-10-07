import Foundation

/// The XCTest device set is separate from the user's regular simulators.
public enum TestSimulators {
  public static var root: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/XCTestDevices")
  }
  public static func run(_ args: [String]) throws -> Data {
    if try !exists(root) {
      if args == ["--set", root.path, "list", "devices", "--json"] {
        return Data("{\"devices\":{}}".utf8)
      }
      throw CleanerError.message("Test device set no longer exists; refresh the list")
    }
    return try Simulators.run(args)
  }
  /// Only a definite missing path is empty; access errors and links remain errors.
  public static func exists(_ path: URL) throws -> Bool {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
      guard attributes[.type] as? FileAttributeType == .typeDirectory,
        path.resolvingSymlinksInPath() == path.standardizedFileURL else {
        throw CleanerError.message("Test device set must be a real directory, not a symbolic link")
      }
      return true
    } catch let error as NSError {
      if error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return false }
      throw error
    }
  }
  public static func devices(run: Simulators.Runner = run) throws -> [SimulatorDevice] {
    try Simulators.devices(run(["--set", root.path, "list", "devices", "--json"]))
  }
  public static func remove(_ id: String, run: Simulators.Runner = run,
    idle: () throws -> Void = DeveloperActivity.assertIdle) throws -> Bool {
    try idle()
    guard UUID(uuidString: id) != nil else { throw CleanerError.message("Invalid device ID") }
    let current = try devices(run: run)
    guard current.allSatisfy({ $0.state == "Shutdown" }),
      current.contains(where: { $0.id == id && $0.removable }) else {
      throw CleanerError.message("Test devices are active or changed; stop tests and refresh")
    }
    try idle()
    _ = try run(["--set", root.path, "delete", id])
    return try !devices(run: run).contains(where: { $0.id == id })
  }
  public static func size(_ id: String) throws -> Int64 {
    guard UUID(uuidString: id) != nil else { throw CleanerError.message("Invalid device ID") }
    let path = root.appendingPathComponent(id)
    guard path.resolvingSymlinksInPath() == path.standardizedFileURL else {
      throw CleanerError.message("Symbolic link is not supported")
    }
    let result = try DeveloperCommand.run("/usr/bin/du", ["-sk", path.path])
    guard let first = String(decoding: result, as: UTF8.self).split(whereSeparator: \.isWhitespace).first,
      let kb = Int64(first), kb >= 0, kb <= Int64.max / 1024 else {
      throw CleanerError.message("Cannot measure test device")
    }
    return kb * 1024
  }
}
