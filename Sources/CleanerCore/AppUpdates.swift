import Foundation

public struct AppRelease: Sendable {
  public let version: String
  public let archive: URL
  public let checksums: URL
  public let name: String
  public static func newer(_ lhs: String, than rhs: String) -> Bool {
    func components(_ value: String) -> [Int]? {
      let parts = value.split(separator: ".", omittingEmptySubsequences: false)
      guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
      let numbers = parts.compactMap { Int($0) }
      return numbers.count == 3 ? numbers : nil
    }
    guard let a = components(lhs), let b = components(rhs) else { return false }
    return b.lexicographicallyPrecedes(a)
  }
  public static func parse(_ data: Data, current: String) throws -> AppRelease? {
    guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw CleanerError.message("Invalid release response") }
    for row in rows where row["draft"] as? Bool == false {
      guard let tag = row["tag_name"] as? String, tag.hasPrefix("v") else { continue }
      let version = String(tag.dropFirst())
      guard newer(version, than: current) else { continue }
      let name = "OxyMacCleaner-\(version)-macOS-arm64.zip"
      let assets = row["assets"] as? [[String: Any]] ?? []
      func asset(_ filename: String) -> URL? {
        guard let value = assets.first(where: { $0["name"] as? String == filename })?["browser_download_url"] as? String,
          let url = URL(string: value), url.scheme == "https", url.host == "github.com",
          url.path == "/Datastore24Kirill/OxyMacCleaner/releases/download/\(tag)/\(filename)" else { return nil }
        return url
      }
      if let archive = asset(name), let checksums = asset("SHA256SUMS.txt") {
        return AppRelease(version: version, archive: archive, checksums: checksums, name: name)
      }
    }
    return nil
  }
  public func expectedHash(_ text: String) throws -> String {
    for line in text.split(separator: "\n") {
      let columns = line.split(whereSeparator: \.isWhitespace)
      if columns.count == 2, columns[1] == name, columns[0].count == 64,
        columns[0].allSatisfy({ $0.isHexDigit }) { return columns[0].lowercased() }
    }
    throw CleanerError.message("Release checksum is missing or invalid")
  }
  public static func validateEntries(_ text: String) throws {
    let entries = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard !entries.isEmpty, entries.count < 10_000 else { throw CleanerError.message("Invalid update archive") }
    for entry in entries {
      let components = entry.split(separator: "/")
      guard !entry.hasPrefix("/"), !entry.contains("\\"), !components.contains(".."),
        components.first == "OxyMac Cleaner.app" || components.first == "__MACOSX" else {
        throw CleanerError.message("Unsafe update archive path")
      }
    }
  }
}
