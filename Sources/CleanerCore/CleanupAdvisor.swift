import Foundation

public struct CleanupCandidate: Identifiable, Sendable {
  public enum Rule: String, CaseIterable, Sendable { case oldInstaller, largeOldFile }
  public var id: String { file.path }
  public let file: FileRecord
  public let rule: Rule
  public let ageDays: Int
}
public enum CleanupAdvisor {
  /// Review-only rules: neither size nor age proves that a file is disposable.
  public static func candidates(
    files: [FileRecord], home: URL, exclusions: [String], now: Date = Date()
  ) -> [CleanupCandidate] {
    let locations = ["Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music"].map {
      home.appendingPathComponent($0).path
    }
    let downloads = home.appendingPathComponent("Downloads").path
    let blocked: Set<String> = [
      ".git", "node_modules", "vendor", "build", ".build", "pods", ".gradle", ".venv", "venv",
    ]
    var seen = Set<String>()
    var output: [CleanupCandidate] = []
    for file in files {
      guard file.bytes > 0, file.links == 1, file.modified <= now,
        locations.contains(where: { Scanner.inside(file.path, $0) }),
        !QuarantineStore.protected(file.path),
        !exclusions.contains(where: { Scanner.inside(file.path, $0) })
      else { continue }
      let url = URL(fileURLWithPath: file.path)
      let parts = url.pathComponents.map { $0.lowercased() }
      guard blocked.isDisjoint(with: parts),
        !parts.contains(where: {
          $0.hasSuffix(".photoslibrary") || $0.hasSuffix(".bundle") || $0.hasSuffix(".app")
            || $0.hasSuffix(".xcarchive")
        })
      else { continue }
      let category = FileCategory.classify(file.path)
      guard [.images, .video, .audio, .documents, .archive, .other].contains(category) else {
        continue
      }
      let age = Int(now.timeIntervalSince(file.modified) / 86400)
      let rule: CleanupCandidate.Rule
      if Scanner.inside(file.path, downloads),
        ["dmg", "pkg", "xip", "ipa"].contains(url.pathExtension.lowercased()), age >= 90
      {
        rule = .oldInstaller
      } else if file.bytes >= 500_000_000, age >= 180 {
        rule = .largeOldFile
      } else {
        continue
      }
      let identity = "\(file.device):\(file.inode)"
      guard seen.insert(identity).inserted else { continue }
      output.append(CleanupCandidate(file: file, rule: rule, ageDays: age))
    }
    return output.sorted {
      if $0.rule != $1.rule { return $0.rule == .oldInstaller }
      return $0.file.bytes == $1.file.bytes ? $0.id < $1.id : $0.file.bytes > $1.file.bytes
    }
  }
}
