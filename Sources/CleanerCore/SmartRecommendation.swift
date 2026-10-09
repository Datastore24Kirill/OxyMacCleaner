import Foundation

/// Read-only advice. Never an authorization or an executable cleanup plan.
public struct SmartRecommendation: Identifiable, Sendable {
  public enum Group: Int, CaseIterable, Sendable { case regenerable, review, blocked }
  public enum Risk: Int, Sendable { case rebuild, personalData, irreplaceable }
  public let id: String
  public let rule: String
  public let version: Int
  public let section: String
  public let path: String?
  public let identity: String?
  public let retainedPaths: [String]
  public let title: String
  public let owner: String
  public let bytes: Int64?
  public let checkedAt: Date?
  public let group: Group
  public let risk: Risk
  public let evidence: [String]
  public let blockers: [String]
  public let conditions: [String]
  public let recovery: String
  /// Number of known required facts; not a probabilistic confidence score.
  public let evidenceComplete: Bool
  public let recoveryCost: Int
  public var selectable: Bool { group != .blocked && blockers.isEmpty && checkedAt != nil }

  public static func ranked(_ values: [Self]) -> [Self] {
    values.sorted {
      if $0.group == .blocked && $1.group != .blocked { return false }
      if $1.group == .blocked && $0.group != .blocked { return true }
      if $0.risk != $1.risk { return $0.risk.rawValue < $1.risk.rawValue }
      if $0.evidenceComplete != $1.evidenceComplete { return $0.evidenceComplete }
      if $0.bytes != $1.bytes { return ($0.bytes ?? -1) > ($1.bytes ?? -1) }
      if $0.recoveryCost != $1.recoveryCost { return $0.recoveryCost < $1.recoveryCost }
      return $0.id < $1.id
    }
  }
}

public struct RecommendationPreview: Sendable {
  public let objects: [SmartRecommendation]
  public let knownLogicalBytes: Int64
  public let unknownSizeCount: Int
  public let omittedOverlapCount: Int
  public let rejectedCount: Int
  public let hasUnverifiedDirectoryOverlap: Bool
  public init(_ selected: [SmartRecommendation]) {
    var ids = Set<String>()
    let unique = selected.filter { ids.insert($0.id).inserted }
    let reserved = unique.filter(\.selectable).flatMap(\.retainedPaths)
    let allowed = unique.filter { item in
      item.selectable && !reserved.contains { keeper in
        item.path.map { Scanner.inside(keeper, $0) } ?? false
      }
    }
    let roots = Set(SpaceEstimate.disjointPaths(allowed.compactMap(\.path)))
    var paths = Set<String>(); var identities = Set<String>()
    var retained: [SmartRecommendation] = []
    for item in SmartRecommendation.ranked(allowed) {
      if let path = item.path {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard roots.contains(normalized), paths.insert(normalized).inserted else { continue }
      }
      if let identity = item.identity, !identities.insert(identity).inserted { continue }
      retained.append(item)
    }
    objects = retained
    rejectedCount = unique.count - allowed.count
    omittedOverlapCount = allowed.count - retained.count
    // Folder aggregates lack constituent inode lists. Do not claim exact cross-folder accounting.
    hasUnverifiedDirectoryOverlap = retained.contains { $0.path != nil && $0.identity == nil }
    knownLogicalBytes = retained.reduce(0) { $0 + max(0, $1.bytes ?? 0) }
    unknownSizeCount = retained.filter { $0.bytes == nil }.count
  }
}

public enum SmartRecommendations {
  public static func catalog(
    personal: [CleanupCandidate], snapshotDate: Date?, archives: ArchiveInventory,
    archiveDate: Date?, keep: Int, pinned: Set<String>, derived: [DerivedCache],
    derivedDate: Date?, derivedIssue: String?, duplicates: [[FileRecord]], duplicateDate: Date?,
    projects: [ProjectDataItem], projectDate: Date?, projectIssue: String?,
    worktrees: [WorktreeReview], worktreeDate: Date?, worktreeIssue: String?,
    simulators: SimulatorInventory, simulatorDate: Date?, simulatorIssue: String?,
    testDevices: [SimulatorDevice], testDate: Date?, testIssue: String?,
    exclusions: [String], russian: Bool, now: Date = Date()
  ) -> [SmartRecommendation] {
    func t(_ ru: String, _ en: String) -> String { russian ? ru : en }
    var result: [SmartRecommendation] = []
    func add(_ key: String, section: String, path: String?, title: String, owner: String,
             bytes: Int64?, date: Date?, group: SmartRecommendation.Group = .review,
             risk: SmartRecommendation.Risk = .personalData, evidence: [String],
             blockers: [String] = [], identity: String? = nil, cost: Int = 2, retainedPaths: [String] = []) {
      var reasons = blockers
      if date == nil { reasons.append(t("Источник ещё не проверен", "Source not inspected")) }
      if let path, exclusions.contains(where: { Scanner.inside(path, $0) || Scanner.inside($0, path) }) {
        reasons.append(t("Защищено исключением", "Protected by exclusion"))
      }
      result.append(.init(id: section + ":" + key, rule: section + "." + key.components(separatedBy: ":").first!,
        version: 1, section: section, path: path, identity: identity, retainedPaths: retainedPaths, title: title, owner: owner,
        bytes: bytes, checkedAt: date, group: reasons.isEmpty ? group : .blocked, risk: risk,
        evidence: evidence, blockers: reasons,
        conditions: [t("Повторная проверка объекта, исключений и активности в профильном разделе перед действием", "Revalidate object, exclusions and activity in its section before acting")],
        recovery: CleanupExplanation.forSection(section, russian: russian).recovery,
        evidenceComplete: reasons.isEmpty && bytes != nil, recoveryCost: cost))
    }
    for c in personal {
      add(c.rule.rawValue + ":" + c.id, section: "personal", path: c.file.path,
          title: c.file.name, owner: t("Личный файл; владелец неизвестен", "Personal file; owner unknown"),
          bytes: c.file.bytes, date: snapshotDate,
          evidence: [t("Не изменялся \(c.ageDays) дней; правило \(c.rule.rawValue)", "Unmodified for \(c.ageDays) days; rule \(c.rule.rawValue)")],
          blockers: c.file.links != 1 || QuarantineStore.protected(c.file.path) ? [t("Защищённый файл или жёсткая ссылка", "Protected file or hard link")] : [],
          identity: "\(c.file.device):\(c.file.inode)")
    }
    let decisions = ArchiveRetention.decisions(archives.archives, keep: keep, pinned: pinned)
    for a in archives.archives {
      let decision = decisions[a.path] ?? .unknown
      var blockers: [String] = []
      if !archives.complete { blockers.append(t("Неполная проверка архивов", "Archive inspection incomplete")) }
      if decision != .review {
        switch decision {
        case .pinned: blockers.append(t("Отмечен «Не удалять»", "Marked as protected"))
        case .latest: blockers.append(t("Входит в число последних сохраняемых архивов", "Among the latest retained archives"))
        default: blockers.append(t("Недостаточно метаданных архива", "Archive metadata incomplete"))
        }
      }
      add("retention:" + a.path, section: "archives", path: a.path, title: a.name,
          owner: a.bundleID ?? "Xcode", bytes: a.bytes, date: archiveDate, risk: .irreplaceable,
          evidence: [t("Лимит последних архивов: \(keep)", "Latest archives retained: \(keep)")], blockers: blockers, cost: 3)
    }
    for c in derived {
      var blockers: [String] = []
      if let derivedIssue { blockers.append(derivedIssue) }
      if c.issues != 0 || c.bytes <= 0 || !DerivedData.allowed(URL(fileURLWithPath: c.path)) {
        blockers.append(t("Непроверенная категория или ошибка обхода", "Unverified category or traversal error"))
      }
      if c.modified >= now.addingTimeInterval(-600) { blockers.append(t("Недавно изменялся: возможна активная сборка", "Recently modified: build may be active")) }
      let logs = c.category == "Logs"
      add("cache:" + c.path, section: "derived", path: c.path, title: c.displayCategory(russian: russian),
          owner: c.project, bytes: c.bytes, date: derivedDate, group: logs ? .review : .regenerable,
          risk: logs ? .personalData : .rebuild, evidence: [c.workspace, c.category], blockers: blockers, cost: 1)
    }
    var duplicatePaths = Set<String>()
    for group in duplicates {
      // Deterministically retain one eligible copy, independently of input ordering.
      let eligible = group.filter { $0.links == 1 && !QuarantineStore.protected($0.path) }
        .sorted { $0.path < $1.path }
      guard let keeper = eligible.first, eligible.count > 1 else { continue }
      for f in eligible.dropFirst() where duplicatePaths.insert(f.path).inserted {
        add("exact-copy:" + f.path, section: "duplicates", path: f.path, title: f.name,
            owner: t("Личный файл", "Personal file"), bytes: f.bytes, date: duplicateDate,
            evidence: [t("Точное сравнение; сохраняем: ", "Exact comparison; keep: ") + keeper.path],
            identity: "\(f.device):\(f.inode)", retainedPaths: [keeper.path])
      }
    }
    for p in projects {
      var blockers = projectIssue.map { [$0] } ?? []
      if !p.cleanable || p.issues != 0 { blockers.append(t("Только просмотр: зависимости или неполный обход", "Review only: dependencies or incomplete traversal")) }
      add("project-cache:" + p.id, section: "projectData", path: p.path.path,
          title: p.rule, owner: p.project.path, bytes: p.bytes, date: projectDate,
          group: .regenerable, risk: .rebuild, evidence: [p.rule, p.recovery], blockers: blockers, cost: 1)
    }
    for w in worktrees {
      add("linked-checkout:" + w.id, section: "worktrees", path: w.tree.path,
          title: w.tree.branch, owner: w.repository.path, bytes: w.bytes, date: worktreeDate,
          evidence: [w.tree.head], blockers: w.blockers + (worktreeIssue.map { [$0] } ?? []))
    }
    func devices(_ devices: [SimulatorDevice], section: String, date: Date?, issue: String?) {
      for d in devices where section == "testSimulators" || !d.isAvailable {
        var blockers = issue.map { [$0] } ?? []
        if !d.removable { blockers.append(t("Устройство занято или не проверено", "Device busy or unverified")) }
        add("device:" + d.udid, section: section, path: nil, title: d.name, owner: d.runtime,
            bytes: nil, date: date, evidence: [d.udid, d.state], blockers: blockers)
      }
    }
    devices(simulators.devices, section: "simulators", date: simulatorDate, issue: simulatorIssue)
    devices(testDevices, section: "testSimulators", date: testDate, issue: testIssue)
    for r in simulators.runtimes where r.unused(days: 90, now: now) {
      var blockers = (simulatorIssue ?? simulators.runtimeIssue).map { [$0] } ?? []
      if !Simulators.canRemove(r, devices: simulators.devices) { blockers.append(t("Runtime используется или защищён", "Runtime in use or protected")) }
      add("runtime:" + r.identifier, section: "simulators", path: nil, title: r.version,
          owner: "Xcode / CoreSimulator", bytes: r.sizeBytes, date: simulatorDate,
          evidence: [r.identifier, r.lastUsedAt ?? "?"], blockers: blockers, cost: 3)
    }
    return SmartRecommendation.ranked(result)
  }
}
