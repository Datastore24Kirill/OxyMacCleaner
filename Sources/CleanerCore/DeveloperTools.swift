import Foundation

public enum DeveloperCommand {
  public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 120)
    throws -> Data
  {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent("oxy-tool-" + UUID().uuidString)
    try fm.createDirectory(
      at: temp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: temp) }
    let out = temp.appendingPathComponent("output")
    fm.createFile(atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600])
    let handle = try FileHandle(forWritingTo: out)
    defer { try? handle.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning {
      if Date() >= deadline {
        process.terminate()
        throw CleanerError.message("Tool timed out. Refresh the inventory to check the result.")
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    guard
      (try fm.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.intValue ?? 0 < 16_000_000
    else {
      throw CleanerError.message("Tool output is too large")
    }
    let data = try Data(contentsOf: out)
    guard process.terminationStatus == 0 else {
      throw CleanerError.message(String(decoding: data.prefix(4000), as: UTF8.self))
    }
    return data
  }
}
public enum DeveloperActivity {
  public static func blockers(_ processNames: String) -> [String] {
    let names: Set<String> = [
      "Xcode", "xcodebuild", "swift-frontend", "swiftc", "swift-build", "swift-driver", "clang",
      "clang++", "ld", "metal", "actool", "ibtool", "xctest", "ninja", "make", "bazel",
    ]
    return Array(
      Set(
        processNames.split(separator: "\n").map {
          URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).lastPathComponent
        }.filter { names.contains($0) })
    ).sorted()
  }
  /// An open IDE and background indexing do not make completed archives unsafe.
  /// Conservatively defer while a command-line build/export may use an archive.
  public static func archiveBlockers(_ processNames: String) -> [String] {
    blockers(processNames).filter { $0 == "xcodebuild" }
  }
  public static func assertArchivesIdle() throws {
    let names = String(
      decoding: try DeveloperCommand.run("/bin/ps", ["-axo", "comm="], timeout: 10), as: UTF8.self)
    guard archiveBlockers(names).isEmpty else {
      throw CleanerError.message("Wait for xcodebuild to finish before cleaning archives. Xcode may remain open.")
    }
  }
  public static func assertIdle() throws {
    let names = String(
      decoding: try DeveloperCommand.run("/bin/ps", ["-axo", "comm="], timeout: 10), as: UTF8.self)
    let active = blockers(names)
    guard active.isEmpty else {
      throw CleanerError.message("Close Xcode and stop builds: " + active.joined(separator: ", "))
    }
  }
}
public struct SimulatorDevice: Decodable, Identifiable, Sendable {
  public var id: String { udid }
  public let udid: String
  public let name: String
  public let state: String
  public let isAvailable: Bool
  public var runtime = ""
  enum CodingKeys: String, CodingKey { case udid, name, state, isAvailable }
  public var removable: Bool { UUID(uuidString: udid) != nil && state == "Shutdown" }
}
public struct SimulatorRuntime: Decodable, Identifiable, Sendable {
  public var id: String { identifier }
  public let identifier: String
  public let runtimeIdentifier: String
  public let version: String
  public let build: String
  public let state: String
  public let deletable: Bool
  public let sizeBytes: Int64?
  public let lastUsedAt: String?
  public var removable: Bool {
    UUID(uuidString: identifier) != nil && deletable && state == "Ready"
  }
  public func unused(days: Int, now: Date = Date()) -> Bool {
    guard let value = lastUsedAt, let date = ISO8601DateFormatter().date(from: value) else {
      return false
    }
    return now.timeIntervalSince(date) >= Double(days) * 86400
  }
}
public struct SimulatorInventory: Sendable {
  public var devices: [SimulatorDevice] = []
  public var runtimes: [SimulatorRuntime] = []
  public var runtimeIssue: String? = nil
  public init() {}
}
public enum Simulators {
  public typealias Runner = ([String]) throws -> Data
  public static func run(_ args: [String]) throws -> Data {
    try DeveloperCommand.run("/usr/bin/xcrun", ["simctl"] + args)
  }
  public static func devices(_ data: Data) throws -> [SimulatorDevice] {
    struct Response: Decodable { let devices: [String: [SimulatorDevice]] }
    let groups = try JSONDecoder().decode(Response.self, from: data).devices
    return groups.flatMap { key, value in
      value.map { item in
        var item = item
        item.runtime = key
        return item
      }
    }.sorted { $0.name < $1.name }
  }
  public static func runtimeImages(_ data: Data) throws -> [SimulatorRuntime] {
    try Array(JSONDecoder().decode([String: SimulatorRuntime].self, from: data).values).sorted {
      $0.version.compare($1.version, options: .numeric) == .orderedDescending
    }
  }
  public static func inventory(run: Runner = run) throws -> SimulatorInventory {
    var result = SimulatorInventory()
    result.devices = try devices(run(["list", "devices", "--json"]))
    do { result.runtimes = try runtimeImages(run(["runtime", "list", "--json"])) } catch {
      result.runtimeIssue = error.localizedDescription
    }
    return result
  }
  public static func canRemove(_ runtime: SimulatorRuntime, devices: [SimulatorDevice]) -> Bool {
    runtime.removable
      && devices.filter { $0.runtime == runtime.runtimeIdentifier }.allSatisfy {
        $0.state == "Shutdown"
      }
  }
  /// Always re-read state and only pass a validated UUID, never `all`/`unavailable` aliases.
  public static func removeDevice(
    _ id: String, run: Runner = run, idle: (() throws -> Void)? = nil
  ) throws -> Bool {
    if let idle { try idle() }
    guard UUID(uuidString: id) != nil,
      let current = try devices(run(["list", "devices", "--json"])).first(where: { $0.id == id }),
      current.removable
    else {
      throw CleanerError.message("Device missing or not shut down; refresh the list")
    }
    if let idle { try idle() } else { try SimulatorActivity.assertDeviceIdle(id) }
    _ = try run(["delete", id])
    return try !devices(run(["list", "devices", "--json"])).contains { $0.id == id }
  }
  public static func removeRuntime(
    _ id: String, run: Runner = run, idle: (() throws -> Void)? = nil
  ) throws -> Bool {
    if let idle { try idle() }
    let current = try inventory(run: run)
    guard UUID(uuidString: id) != nil, let runtime = current.runtimes.first(where: { $0.id == id }),
      canRemove(runtime, devices: current.devices)
    else {
      throw CleanerError.message("Runtime unavailable, protected or in use; refresh the list")
    }
    if let idle { try idle() } else {
      let testDevices = try TestSimulators.devices()
      try SimulatorActivity.assertRuntimeIdle(runtime.runtimeIdentifier, devices: current.devices + testDevices)
      guard testDevices.filter({ $0.runtime == runtime.runtimeIdentifier }).allSatisfy({ $0.state == "Shutdown" }) else {
        throw CleanerError.message("Runtime is in use by a test simulator")
      }
    }
    _ = try run(["runtime", "delete", id])
    return try !runtimeImages(run(["runtime", "list", "--json"])).contains { $0.id == id }
  }
}
