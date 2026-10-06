import Foundation

/// Review summaries only. Mutations always use their dedicated validation workflows.
public struct OpportunitySummary: Equatable, Sendable {
  public let count: Int
  public let bytes: Int64?
}
public enum CleanupOpportunities {
  private static func excluded(_ path: String, _ exclusions: [String]) -> Bool {
    exclusions.contains { Scanner.inside(path, $0) || Scanner.inside($0, path) }
  }
  public static func archives(
    _ inventory: ArchiveInventory, keep: Int, pinned: Set<String>,
    exclusions: [String]
  ) -> OpportunitySummary {
    guard inventory.complete else { return OpportunitySummary(count: 0, bytes: nil) }
    let decisions = ArchiveRetention.decisions(inventory.archives, keep: keep, pinned: pinned)
    let candidates = inventory.archives.filter {
      decisions[$0.path] == .review && !excluded($0.path, exclusions)
    }
    return OpportunitySummary(
      count: candidates.count, bytes: candidates.reduce(0) { $0 + $1.bytes })
  }
  public static func derived(_ caches: [DerivedCache], exclusions: [String], now: Date = Date())
    -> OpportunitySummary
  {
    let candidates = caches.filter {
      $0.issues == 0 && $0.bytes > 0 && $0.modified < now.addingTimeInterval(-600)
        && DerivedData.allowed(URL(fileURLWithPath: $0.path)) && !excluded($0.path, exclusions)
    }
    return OpportunitySummary(
      count: candidates.count, bytes: candidates.reduce(0) { $0 + $1.bytes })
  }
  public static func duplicates(_ groups: [[FileRecord]], exclusions: [String])
    -> OpportunitySummary
  {
    var count = 0
    var bytes: Int64 = 0
    var seen = Set<String>()
    for group in groups {
      let eligible = group.filter {
        $0.links == 1 && !QuarantineStore.protected($0.path) && !excluded($0.path, exclusions)
          && seen.insert("\($0.device):\($0.inode)").inserted
      }
      guard eligible.count > 1 else { continue }
      count += 1
      // Preserve a copy even when another copy lives in a protected location.
      bytes += eligible.dropFirst().reduce(0) { $0 + $1.bytes }
    }
    return OpportunitySummary(count: count, bytes: bytes)
  }
  public static func simulators(_ inventory: SimulatorInventory, now: Date = Date())
    -> OpportunitySummary
  {
    let devices = inventory.devices.filter { !$0.isAvailable && $0.removable }
    let runtimes = inventory.runtimes.filter {
      $0.unused(days: 90, now: now) && Simulators.canRemove($0, devices: inventory.devices)
    }
    let knownSize = devices.isEmpty && runtimes.allSatisfy { $0.sizeBytes != nil }
    return OpportunitySummary(
      count: devices.count + runtimes.count,
      bytes: knownSize ? runtimes.reduce(0) { $0 + ($1.sizeBytes ?? 0) } : nil)
  }
}
