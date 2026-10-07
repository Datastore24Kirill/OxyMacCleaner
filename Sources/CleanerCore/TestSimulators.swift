import Foundation

/// The XCTest device set is separate from the user's regular simulators.
public enum TestSimulators {
  public static var root: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/XCTestDevices")
  }
  public static func run(_ args: [String]) throws -> Data {
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue,
      root.resolvingSymlinksInPath() == root.standardizedFileURL else {
      throw CleanerError.message("XCTestDevices is missing or is a symbolic link")
    }
    return try Simulators.run(args)
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
