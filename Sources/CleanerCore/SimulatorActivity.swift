import Foundation

/// Conservative association: only explicit destination UUIDs are trusted.
public enum SimulatorActivity {
  public struct ProcessInfo: Sendable {
    public let pid: Int
    public let parent: Int
    public let name: String
    public let arguments: String
    public init(pid: Int, parent: Int, name: String, arguments: String = "") {
      self.pid = pid; self.parent = parent; self.name = name; self.arguments = arguments
    }
  }
  public static func destinations(_ arguments: String) throws -> Set<String> {
    let expression = try NSRegularExpression(pattern: #"(?:^|\s)-destination\s+(.+?)(?=\s+-|$)"#)
    let source = arguments as NSString
    let matches = expression.matches(in: arguments, range: NSRange(location: 0, length: source.length))
    guard !matches.isEmpty else { throw CleanerError.message("Cannot identify active xcodebuild destination; finish that task first") }
    var ids = Set<String>()
    let idPattern = try NSRegularExpression(pattern: #"(?:^|,)\s*id=([0-9A-Fa-f-]{36})(?=,|\s|$)"#)
    for match in matches {
      let value = source.substring(with: match.range(at: 1))
      let text = value as NSString
      guard let id = idPattern.firstMatch(in: value, range: NSRange(location: 0, length: text.length)),
        let uuid = UUID(uuidString: text.substring(with: id.range(at: 1))) else {
        throw CleanerError.message("Active build uses a destination without a device UUID; finish that task first")
      }
      ids.insert(uuid.uuidString)
    }
    return ids
  }
  public static func protectedDevices(_ processes: [ProcessInfo]) throws -> Set<String> {
    var result = Set<String>()
    let builds = processes.filter { $0.name == "xcodebuild" }
    for build in builds { result.formUnion(try destinations(build.arguments)) }
    if processes.contains(where: { $0.name == "Xcode" }) {
      throw CleanerError.message("Close Xcode: GUI build destinations cannot be verified")
    }
    let byID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    for test in processes.filter({ $0.name == "xctest" }) {
      var parent = test.parent
      var visited = Set<Int>()
      var associated = false
      while visited.insert(parent).inserted, let process = byID[parent] {
        if process.name == "xcodebuild" { associated = true; break }
        parent = process.parent
      }
      guard associated else { throw CleanerError.message("An active test process has an unknown destination; finish tests first") }
    }
    return result
  }
  public static func snapshot() throws -> [ProcessInfo] {
    let data = try DeveloperCommand.run("/bin/ps", ["-axo", "pid=,ppid=,comm="], timeout: 10)
    var result: [ProcessInfo] = []
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
      let columns = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
      guard columns.count == 3, let pid = Int(columns[0]), let parent = Int(columns[1]) else {
        throw CleanerError.message("Cannot read process inventory")
      }
      let name = URL(fileURLWithPath: String(columns[2])).lastPathComponent
      let args = name == "xcodebuild"
        ? String(decoding: try DeveloperCommand.run("/bin/ps", ["-ww", "-p", String(pid), "-o", "args="], timeout: 10), as: UTF8.self)
        : ""
      result.append(ProcessInfo(pid: pid, parent: parent, name: name, arguments: args))
    }
    return result
  }
  public static func assertDeviceIdle(_ id: String, processes: [ProcessInfo]? = nil) throws {
    let protected = try protectedDevices(processes ?? snapshot())
    guard !protected.contains(id.uppercased()) else {
      throw CleanerError.message("This simulator is the destination of an active build/test: " + id)
    }
  }
  public static func assertRuntimeIdle(_ runtime: String, devices: [SimulatorDevice], processes: [ProcessInfo]? = nil) throws {
    let protected = try protectedDevices(processes ?? snapshot())
    for id in protected {
      guard let device = devices.first(where: { $0.id.uppercased() == id }) else {
        throw CleanerError.message("Cannot identify the runtime of an active build destination")
      }
      guard device.runtime != runtime else {
        throw CleanerError.message("This runtime is required by an active build/test")
      }
    }
  }
}
