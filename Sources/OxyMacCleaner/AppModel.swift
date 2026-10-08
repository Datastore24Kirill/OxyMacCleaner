import CleanerCore
import SwiftUI
import UserNotifications

@MainActor final class AppModel: ObservableObject {
  @Published var showDiskAccess = false
  @Published var diskAccess: DiskAccess.Result?
  @Published var diskAccessCheckedAt: Date?
  var diskAccessAcknowledged = false
  var pendingDiskScan = false
  var permissionBuild: String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") + ":"
      + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev")
  }
  func checkDiskAccess() {
    diskAccess = DiskAccess.check()
    diskAccessCheckedAt = Date()
  }
  func prepareDiskAccess() {
    checkDiskAccess()
    if diskAccess?.state == .available {
      diskAccessAcknowledged = true
      UserDefaults.standard.set(permissionBuild, forKey: "permissionReviewedBuild")
    } else if UserDefaults.standard.string(forKey: "permissionReviewedBuild") != permissionBuild {
      showDiskAccess = true
    }
  }
  func openDiskSettings() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
  }
  @Published var archiveSymbols: [String: ArchiveSymbolReport] = [:]
  func checkArchiveSymbols(_ archive: XcodeArchive) {
    guard !busy else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    status = t("Сравниваем UUID приложения и dSYM…", "Comparing binary and dSYM UUIDs…")
    task = Task {
      do {
        let result = try await Task.detached {
          try ArchiveSymbols.inspect(URL(fileURLWithPath: archive.path), cancellation: token)
        }.value
        archiveSymbols[archive.path] = result
        status = t("Проверка UUID завершена", "UUID verification complete")
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
  func backupArchive(_ archive: XcodeArchive) {
    guard !busy else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.message = t(
      "Выберите папку резервных копий, желательно на другом диске. Будет создана полная копия архива.",
      "Choose a backup folder, preferably on another disk. A full archive copy will be created.")
    guard panel.runModal() == .OK, let folder = panel.url else { return }
    let destination = folder.appendingPathComponent(
      URL(fileURLWithPath: archive.path).lastPathComponent)
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    status = t(
      "Копируем архив и проверяем SHA-256. Копирование нельзя прервать мгновенно…",
      "Copying archive and verifying SHA-256. Copy cancellation may be delayed…")
    task = Task {
      do {
        try await Task.detached {
          try ArchiveTransfer.createBackup(
            source: URL(fileURLWithPath: archive.path), destination: destination,
            cancellation: token)
        }.value
        status = t("Резервная копия проверена: ", "Backup verified: ") + destination.path
      } catch {
        self.error = error.localizedDescription
        status = t("Копия не создана", "Backup not created")
      }
      busy = false
    }
  }
  func quarantineArchive(_ archive: XcodeArchive) {
    guard !busy else { return }
    let decisions = ArchiveRetention.decisions(
      archiveInventory.archives, keep: archiveKeep, pinned: pinnedArchives)
    guard decisions[archive.path] == .review else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let store = quarantine
    status = t("Проверяем архив…", "Checking archive…")
    task = Task {
      do {
        let root = archiveRoot
        let fresh = await Task.detached { XcodeArchives.scan(root: root, cancellation: token) }
          .value
        guard fresh.complete, fresh.issues.isEmpty,
          ArchiveRetention.decisions(fresh.archives, keep: archiveKeep, pinned: pinnedArchives)[
            archive.path] == .review
        else {
          throw CleanerError.message(
            "Archive inventory changed or is incomplete; refresh before moving")
        }
        archiveInventory = fresh
        let plan = try await Task.detached {
          try ArchiveTransfer.prepare(archive: archive, cancellation: token)
        }.value
        try token.check()
        guard
          confirm(
            t("Переместить архив в карантин?", "Move archive to quarantine?"),
            archive.path + "\n"
              + t(
                "Закройте Xcode и сборки. Архив исчезнет из Organizer. Его можно восстановить из карантина. Карантин ещё занимает место. Отдельная резервная копия для переноса не нужна.",
                "Close Xcode and builds. The archive will disappear from Organizer and can be restored from quarantine. Quarantine still takes space. No separate backup is required for transfer."
              ))
        else {
          busy = false
          status = t("Отменено", "Cancelled")
          return
        }
        let current = ArchiveRetention.decisions(
          archiveInventory.archives, keep: archiveKeep, pinned: pinnedArchives)
        guard current[archive.path] == .review else {
          throw CleanerError.message("Archive is now retained")
        }
        let pins = pinnedArchives
        let retained = Set(current.filter { $0.value != .review }.map(\.key))
        let protected = exclusions
        status = t(
          "Переносим архив и проверяем целостность…", "Moving archive and verifying integrity…")
        _ = try await Task.detached {
          try DeveloperActivity.assertIdle()
          return try store.moveArchive(
            plan, pinned: pins, retained: retained, protectedPaths: protected, cancellation: token)
        }.value
        archiveInventory.archives.removeAll { $0.path == archive.path }
        archiveSymbols.removeValue(forKey: archive.path)
        page = "quarantine"
        log("Quarantined Xcode archive: " + archive.path)
        status = t(
          "Архив в карантине. Его можно восстановить.", "Archive quarantined. You can restore it.")
      } catch {
        self.error = error.localizedDescription
        status = t(
          "Операция остановлена. Проверьте журнал карантина.",
          "Operation stopped. Check quarantine journal.")
      }
      entries = store.entries()
      busy = false
      scheduleReminder()
    }
  }
  @Published var archiveInventory = ArchiveInventory()
  @Published var archiveRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Developer/Xcode/Archives")
  @Published var archiveScanDate: Date?
  @Published var archivesLoading = false
  @Published var pinnedArchives = Set(
    UserDefaults.standard.stringArray(forKey: "pinnedArchives") ?? [])
  @AppStorage("archiveKeep") var archiveKeep = 3
  @Published var archiveBackupBeforeDelete = false
  func pinArchive(_ path: String, _ pin: Bool) {
    if pin { pinnedArchives.insert(path) } else { pinnedArchives.remove(path) }
    UserDefaults.standard.set(Array(pinnedArchives).sorted(), forKey: "pinnedArchives")
  }
  func chooseArchiveRoot() {
    guard !busy else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    if panel.runModal() == .OK, let url = panel.url {
      archiveRoot = url
      scanArchives()
    }
  }
  func scanArchives() {
    guard !busy else { return }
    busy = true
    archivesLoading = true
    archiveInventory = ArchiveInventory()
    archiveSymbols = [:]
    archiveScanDate = nil
    cancellation = Cancellation()
    let token = cancellation
    let root = archiveRoot
    status = t("Читаем архивы Xcode…", "Reading Xcode archives…")
    task = Task {
      let result = await Task.detached {
        XcodeArchives.scan(root: root, cancellation: token) { count in
          Task { @MainActor in
            guard self.cancellation === token, self.archivesLoading else { return }
            self.status = self.t("Проверено архивов: \(count)", "Archives checked: \(count)")
          }
        }
      }.value
      archiveInventory = result
      archiveScanDate = Date()
      archivesLoading = false
      busy = false
      status =
        result.complete
        ? t("Архивы прочитаны", "Archive inventory complete")
        : t("Обход архивов неполный. См. ошибки.", "Archive inventory incomplete. See issues.")
    }
  }
  @Published var page = "overview"
  @Published var developerSection = "archives"
  @Published var worktreeRepository: URL? = UserDefaults.standard.string(forKey: "worktreeRepository").map { URL(fileURLWithPath: $0) }
  @Published var worktreeReviews: [WorktreeReview] = []
  @Published var dataProject: URL? = UserDefaults.standard.string(forKey: "dataProject").map { URL(fileURLWithPath: $0) }
  @Published var projectData: [ProjectDataItem] = []
  @Published var projectDataDate: Date?
  @Published var projectDataIssue: String?
  @Published var worktreeReadAt: Date?
  @Published var worktreeIssue: String?
  @Published var duplicatesReadAt: Date?
  @Published var testDevices: [SimulatorDevice] = []
  @Published var testDeviceSizes: [String: Int64] = [:]
  @Published var testDeviceReadAt: Date?
  @Published var testDeviceIssue: String?
  @Published var simulatorReadAt: Date?
  @Published var simulatorReadIssue: String?
  @Published var derivedReadIssue: String?
  @Published var roots: [URL] = [URL(fileURLWithPath: "/")]
  @Published var volumes: [ScanVolume] = Volumes.discover()
  @Published var volumeID = "/"
  @Published var report = ScanReport()
  @Published var recommendations: [CleanupCandidate] = []
  @Published var recommendationsLoading = false
  private var recommendationGeneration = UUID()
  func refreshRecommendations() {
    guard !isScanning else { return }
    let generation = UUID()
    recommendationGeneration = generation
    let files = report.files
    let excluded = exclusions
    let userHome = home
    recommendationsLoading = true
    Task {
      let result = await Task.detached {
        CleanupAdvisor.candidates(files: files, home: userHome, exclusions: excluded)
      }.value
      guard recommendationGeneration == generation else { return }
      recommendations = result
      recommendationsLoading = false
    }
  }
  func reviewCandidate(_ candidate: CleanupCandidate) {
    do {
      try candidate.file.validate()
      reveal(candidate.file.path)
    } catch {
      self.error = t(
        "Файл изменился или недоступен. Повторите сканирование.",
        "File changed or is unavailable. Scan again.")
    }
  }
  @Published var diskIndex = DiskIndex(report: ScanReport())
  @Published var mapPath = "/"
  @Published var snapshotDate: Date?
  @Published var restoredSnapshot = false
  @Published var recoveredInterruptedScan = false
  @Published var minimumMB = 0
  @Published var olderThanDays = 0
  var scanStore: ScanStore { ScanStore(url: support.appendingPathComponent("Scans/latest.plist")) }
  var scanJournalURL: URL { support.appendingPathComponent("Scans/interrupted.jsonl") }
  func restoreScan() {
    guard !busy, snapshotDate == nil else { return }
    busy = true
    status = t("Загружаем прошлый результат…", "Loading previous scan…")
    let store = scanStore
    let journalURL = scanJournalURL
    task = Task {
      do {
        let recovery = try await Task.detached { () throws -> (SavedScan?, Bool) in
          if let partial = try ScanJournal.recover(journalURL) { return (partial, true) }
          return (try store.load(), false)
        }.value
        recoveredInterruptedScan = recovery.1
        if let saved = recovery.0 {
          let index = await Task.detached { DiskIndex(report: saved.report) }.value
          report = saved.report
          scanProgress = saved.progress
          roots = saved.roots
          volumeID = saved.volumeID
          mapPath = saved.roots.first?.path ?? "/"
          diskIndex = index
          snapshotDate = saved.date
          restoredSnapshot = true
          status = t(
            "Загружен прошлый результат. Перед очисткой файлы проверяются заново.",
            "Previous results loaded. Files are checked again before cleanup.")
        } else {
          status = ""
        }
      } catch {
        self.error =
          t("Не удалось открыть сохранённый результат: ", "Could not load saved scan: ")
          + error.localizedDescription
      }
      busy = false
      refreshRecommendations()
    }
  }
  @Published var scanProgress: ScanProgress?
  @Published var isScanning = false
  @Published var selected = Set<String>()
  @Published var duplicates: [[FileRecord]] = []
  @Published var entries: [QuarantineEntry] = []
  @Published var busy = false
  @Published var status = ""
  @Published var error: String?
  @Published var search = ""
  @Published var categoryFilter = "all"
  @Published var agent = "codex"
  @Published var sessionCatalog: SessionCatalogResult?
  @Published var transcript: Transcript?
  @Published var output = ""
  @Published var models: [String] = []
  @Published var engineChecking = false
  @Published var engineReady = false
  @Published var engineMessage = ""
  @Published var pullingModel: String?
  @Published var modelProgress: ModelPullProgress?
  var installedOllama: URL? {
    [URL(fileURLWithPath: "/Applications/Ollama.app"), home.appendingPathComponent("Applications/Ollama.app")].first { FileManager.default.fileExists(atPath: $0.path) }
  }
  @Published var model = ""
  @Published var style = "Бережный"
  @Published var simulatorInventory = SimulatorInventory()
  @Published var selectedDevices = Set<String>()
  @Published var selectedRuntimes = Set<String>()
  @Published var developerResult = ""
  @Published var derivedCaches: [DerivedCache] = []
  @Published var derivedReadAt: Date?
  @Published var selectedDerived = Set<String>()
  @Published var exclusions: [String] =
    UserDefaults.standard.stringArray(forKey: "exclusions") ?? []
  @Published var logs: [String] = []
  @AppStorage("language") var language = "ru"
  @AppStorage("theme") var theme = "system"
  let home = FileManager.default.homeDirectoryForCurrentUser
  let support: URL
  let quarantine: QuarantineStore
  let engine = LocalModel()
  var cancellation = Cancellation()
  var task: Task<Void, Never>?
  var reminderTimer: Timer?
  init() {
    support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("OxyMacCleaner")
    do {
      quarantine = try QuarantineStore(root: support.appendingPathComponent("Quarantine"))
    } catch { fatalError("Unable to create local application storage: \(error)") }
    entries = quarantine.entries()
    logs =
      (try? String(contentsOf: support.appendingPathComponent("operations.log"), encoding: .utf8)
        .components(separatedBy: "\n")) ?? []
    reminderTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.remind() }
    }
  }
  func t(_ ru: String, _ en: String) -> String { language == "en" ? en : ru }
  func log(_ text: String) {
    logs.append("\(Date().formatted()) · \(text)")
    if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    try? logs.joined(separator: "\n").write(
      to: support.appendingPathComponent("operations.log"), atomically: true, encoding: .utf8)
  }
  func refreshVolumes() { volumes = Volumes.discover() }
  func selectVolume(_ id: String) {
    guard !busy else { return }
    volumeID = id
    if let volume = volumes.first(where: { $0.id == id }) {
      roots = [volume.url]
      selected = []
    }
  }
  func chooseRoots() {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.allowsMultipleSelection = true
    if p.runModal() == .OK {
      roots = p.urls
      volumeID = "custom"
      selected = []
    }
  }
  func reveal(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }
  func scan(_ explicit: [URL]? = nil, resume: Bool = false) {
    let prior = resume ? report : nil
    guard !busy else { return }
    if explicit == nil && volumeID != "custom" {
      checkDiskAccess()
      if diskAccess?.state != .available && !diskAccessAcknowledged {
        pendingDiskScan = true
        showDiskAccess = true
        return
      }
      refreshVolumes()
      guard volumes.contains(where: { $0.id == volumeID }) else {
        error = t(
          "Диск отключён. Подключите его или выберите другой.",
          "The disk is disconnected. Reconnect it or choose another.")
        return
      }
    }
    if explicit != nil { volumeID = "custom" }
    let chosen = (explicit ?? roots).map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    guard !chosen.isEmpty else {
      chooseRoots()
      return
    }
    let mounted =
      FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
    let excluded =
      exclusions + [support.path] + chosen.flatMap { Volumes.exclusions(for: $0, mounted: mounted) }
    if let prior, !Scanner.canResume(prior, roots: chosen, excluded: excluded) {
      error = t("Диск, папка или исключения изменились. Запустите новый скан; прежний результат сохранён.", "Disk, folder or exclusions changed. Start a new scan; previous results are retained.")
      return
    }
    roots = chosen
    busy = true
    isScanning = true
    recommendationGeneration = UUID()
    recommendations = []
    recommendationsLoading = false
    scanProgress = ScanProgress()
    selected = []
    duplicates = []
    duplicatesReadAt = nil
    report = ScanReport()
    diskIndex = DiskIndex(report: ScanReport())
    snapshotDate = nil
    restoredSnapshot = false
    recoveredInterruptedScan = false
    mapPath = chosen.first?.path ?? "/"
    cancellation = Cancellation()
    let token = cancellation
    status = t("Сканирование…", "Scanning…")
    let journalURL = scanJournalURL
    let selectedVolume = volumeID
    task = Task {
      let (result, finalSnapshot) = await Task.detached {
        var latest = ScanProgress()
        let journal = try? ScanJournal(url: journalURL, roots: chosen, volumeID: selectedVolume, excluded: excluded)
        var report = Scanner.scan(roots: chosen, excluded: excluded, cancellation: token, record: { file in try journal?.append(file) }, resuming: prior, completedDirectory: { path in try journal?.completeDirectory(path) }, issue: { try journal?.appendIssue($0) }) {
          snapshot in
          latest = snapshot
          Task { @MainActor in
            guard self.cancellation === token, self.isScanning else { return }
            self.scanProgress = snapshot
          }
        }
        do { try journal?.flush() } catch { report.issues.append("Recovery journal: " + error.localizedDescription) }
        if journal == nil { report.issues.append("Recovery journal could not be created") }
        return (report, latest)
      }.value
      report = result
      isScanning = false
      // Commit authoritative totals; queued progress events cannot overwrite completion.
      var final = finalSnapshot
      final.files = result.files.count
      final.bytes = result.total
      final.issues = result.issues.count
      final.phase = result.complete ? .finished : .cancelled
      scanProgress = final
      status = t("Сохраняем результат и строим карту…", "Saving results and building map…")
      let saved = SavedScan(roots: chosen, volumeID: volumeID, report: result, progress: final)
      let store = scanStore
      let prepared = await Task.detached {
        let index = DiskIndex(report: result)
        do {
          try store.save(saved)
          try? FileManager.default.removeItem(at: journalURL)
          return (index, Optional<String>.none)
        } catch { return (index, Optional(error.localizedDescription)) }
      }.value
      diskIndex = prepared.0
      snapshotDate = saved.date
      if let failure = prepared.1 {
        self.error =
          t(
            "Результат доступен в окне, но не сохранён: ",
            "Results are available but could not be saved: ") + failure
      }
      busy = false
      status =
        result.complete
        ? (result.issues.isEmpty
          ? t("Сканирование завершено", "Scan complete")
          : t(
            "Сканирование завершено с пропусками. См. отчёт.",
            "Scan finished with skipped items. See report."))
        : t("Остановлено. Результат неполный", "Stopped. Partial results")
      refreshRecommendations()
      log(
        "Scan: \(result.files.count) files, \(result.issues.count) issues, complete=\(result.complete)"
      )
    }
  }
  func findDuplicates() {
    guard !busy else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let files = report.files
    task = Task {
      do {
        let groups = try await Task.detached {
          try Scanner.duplicates(files, cancellation: token) { n in
            Task { @MainActor in
              self.status = self.t("Сравнено файлов: \(n)", "Files compared: \(n)")
            }
          }
        }.value
        duplicates = groups
        duplicatesReadAt = Date()
        status = t("Групп дубликатов: \(groups.count)", "Duplicate groups: \(groups.count)")
      } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
      busy = false
    }
  }
  func cancel() {
    cancellation.cancel()
    task?.cancel()
    status = t("Останавливаю…", "Stopping…")
  }
  func protect(_ path: String) {
    exclusions.append(path)
    UserDefaults.standard.set(exclusions, forKey: "exclusions")
    selected.remove(path)
    refreshRecommendations()
  }
  func confirm(_ title: String, _ text: String, destructive: Bool = false, action: String? = nil)
    -> Bool
  {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.alertStyle = destructive ? .critical : .warning
    a.addButton(
      withTitle: action ?? (destructive ? t("Удалить", "Delete") : t("Продолжить", "Continue")))
    a.addButton(withTitle: t("Отмена", "Cancel"))
    return a.runModal() == .alertFirstButtonReturn
  }
  func recoverQuarantine() {
    guard !busy else { return }
    busy = true
    status = t("Проверяем журнал карантина…", "Checking quarantine journal…")
    let store = quarantine
    task = Task {
      do { try await Task.detached { try store.recover() }.value } catch {
        self.error = error.localizedDescription
      }
      entries = store.entries()
      busy = false
      status = t("Проверка журнала завершена", "Journal check complete")
    }
  }
  func quarantineDirectory(_ path: String) {
    guard !busy else { return }
    busy = true
    status = t("Проверяем состав папки…", "Inspecting folder contents…")
    cancellation = Cancellation()
    let token = cancellation
    let store = quarantine
    let protected = exclusions
    task = Task {
      do {
        let source = URL(fileURLWithPath: path)
        let manifest = try await Task.detached {
          try DirectoryManifest.capture(source, cancellation: token) { candidate in
            guard !QuarantineStore.protected(candidate),
              !protected.contains(where: {
                Scanner.inside(candidate, $0) || Scanner.inside($0, candidate)
              })
            else { throw CleanerError.message("Folder contains protected data") }
          }
        }.value
        try token.check()
        guard
          confirm(
            t("Переместить папку целиком?", "Move entire folder?"),
            path + "\n"
              + ByteCountFormatter.string(fromByteCount: manifest.bytes, countStyle: .file)
              + " · \(manifest.items.count) " + t("объектов", "items") + "\n"
              + t(
                "Закройте приложения, использующие эту папку. Все вложенные файлы будут перемещены. Место не освободится до окончательного удаления.",
                "Close applications using this folder. All nested files will be moved. Space is not freed until permanent deletion."
              ))
        else {
          busy = false
          status = t("Отменено", "Cancelled")
          return
        }
        status = t(
          "Переносим папку и проверяем целостность…", "Moving folder and checking integrity…")
        _ = try await Task.detached {
          try store.moveDirectory(
            source, expected: manifest, protectedPaths: protected, cancellation: token)
        }.value
        log("Quarantined directory: " + path)
        // Keep the saved scan visibly dated; its entries are always revalidated before actions.
        status = t(
          "Папка в карантине. Обновите сканирование для актуальной карты.",
          "Folder quarantined. Rescan to refresh the map.")
        page = "quarantine"
      } catch {
        if !(error is CancellationError) { self.error = error.localizedDescription }
        status = t(
          "Операция остановлена. Проверьте журнал карантина.",
          "Operation stopped. Check quarantine journal.")
      }
      entries = store.entries()
      busy = false
      scheduleReminder()
    }
  }
  func quarantineSelected() {
    let files = report.files.filter { selected.contains($0.path) }
    guard !files.isEmpty && !busy else { return }
    for group in duplicates where group.allSatisfy({ selected.contains($0.path) }) {
      error = t(
        "Оставьте хотя бы одну копию: \(group[0].name)", "Keep at least one copy: \(group[0].name)")
      return
    }
    guard
      confirm(
        t("Переместить в карантин?", "Move to quarantine?"),
        "\(files.count) · \(ByteCountFormatter.string(fromByteCount:SpaceEstimate(files: files).logical,countStyle:.file))\n"
          + t(
            "Место не освободится до окончательного удаления.\n",
            "Space remains occupied until permanent deletion.\n")
          + files.prefix(8).map(\.path).joined(separator: "\n"))
    else { return }
    busy = true
    let store = quarantine
    let protected = exclusions
    cancellation = Cancellation()
    let token = cancellation
    let duplicateGroups = duplicates
    task = Task {
      let results = await Task.detached {
        files.map { f -> (String, String?) in
          do {
            try token.check()
            if let group = duplicateGroups.first(where: {
              $0.contains(where: { $0.path == f.path })
            }) {
              guard
                let keeper = group.first(where: { candidate in
                  !files.contains(where: { $0.path == candidate.path })
                })
              else { throw CleanerError.message("Keep at least one duplicate") }
              try keeper.validate()
              guard FileManager.default.contentsEqual(atPath: keeper.path, andPath: f.path) else {
                throw CleanerError.message("Retained copy changed; scan again")
              }
            }
            _ = try store.move(f, protectedPaths: protected)
            return (f.path, nil)
          } catch { return (f.path, error.localizedDescription) }
        }
      }.value
      for (path, failure) in results {
        log(
          (failure == nil ? "Quarantined: " : "Skipped: ") + path
            + (failure.map { " · " + $0 } ?? ""))
        if failure == nil { report.files.removeAll { $0.path == path } }
      }
      selected = []
      entries = store.entries()
      busy = false
      duplicates = []
      duplicatesReadAt = nil
      report.folders = [:]
      if results.contains(where: { $0.1 != nil }) {
        error = results.compactMap { $0.1 }.joined(separator: "\n")
      }
      scheduleReminder()
    }
  }
  func restore(_ e: QuarantineEntry, alternate: Bool = false) {
    var dest: URL?
    if alternate {
      let p = NSSavePanel()
      p.nameFieldStringValue = URL(fileURLWithPath: e.original).lastPathComponent
      if p.runModal() != .OK { return }
      dest = p.url
    }
    guard !busy else { return }
    busy = true
    cancellation = Cancellation(); let token = cancellation
    status = t("Проверяем и восстанавливаем копию…", "Verifying and restoring copy…")
    let store = quarantine
    let destination = dest
    task = Task {
      do {
        try await Task.detached { try store.restore(e, destination: destination, cancellation: token) }.value
        status = t("Восстановление завершено", "Restore complete")
        log("Restored: \(e.original)")
      } catch { self.error = error is CancellationError ? t("Восстановление отменено до перемещения данных", "Restore cancelled before moving data") : error.localizedDescription }
      entries = store.entries()
      busy = false
      scheduleReminder()
    }
  }
  func erase(_ e: QuarantineEntry) {
    guard !busy,
      confirm(
        t("Удалить безвозвратно?", "Delete permanently?"),
        e.original + "\n"
          + t(
            "Восстановление средствами приложения станет невозможно.",
            "The app will no longer be able to restore this file."), destructive: true)
    else { return }
    busy = true
    let store = quarantine
    task = Task {
      do {
        try await Task.detached { try store.erase(e) }.value
        log("Permanently deleted: \(e.original)")
      } catch { self.error = error.localizedDescription }
      entries = store.entries()
      busy = false
      scheduleReminder()
    }
  }
  func importTranscript(native: Bool = false) {
    guard !busy else { return }
    let p = NSOpenPanel()
    p.canChooseDirectories = false
    p.allowsMultipleSelection = false
    if native {
      p.directoryURL = Agents.catalog.first { $0.id == agent }?.locations(home: home).first
    }
    p.message = t(
      "Экспорт одной завершённой сессии: TXT, MD, JSON или JSONL. Исходник не изменяется.",
      "Export of one inactive session: TXT, MD, JSON or JSONL. Original remains intact.")
    if p.runModal() == .OK, let url = p.url {
      let selectedAgent = agent
      cancellation = Cancellation()
      let token = cancellation
      busy = true
      transcript = nil
      output = ""
      task = Task {
        do {
          let loaded = try await Task.detached {
            if native {
              return try Transcript.loadNative(url, agent: selectedAgent, cancellation: token) { done, total in
                Task { @MainActor in self.status = self.t("Импорт истории: ", "Importing history: ") + "\(total > 0 ? done * 100 / total : 0)%" }
              }
            }
            return try Transcript.load(url, agent: selectedAgent)
          }.value
          try token.check()
          if agent == selectedAgent { transcript = loaded }
          status = t("История загружена", "History loaded")
        } catch { self.error = error.localizedDescription }
        busy = false
      }
    }
  }
  func refreshModels() {
    guard !busy, !engineChecking else { return }
    engineChecking = true
    engineMessage = t("Проверяем Ollama…", "Checking Ollama…")
    Task {
      defer { engineChecking = false }
      do {
        models = try await engine.models(); engineReady = true
        if !models.contains(model) { model = models.first(where: { $0 == "qwen2.5:7b" }) ?? models.first ?? "" }
        engineMessage = t("Ollama работает. Локальных моделей: ", "Ollama is running. Local models: ") + String(models.count)
      } catch {
        engineReady = false
        engineMessage = installedOllama == nil
          ? t("Движок недоступен. Установите Ollama или запустите свою установку.", "Engine unavailable. Install Ollama or start your existing installation.")
          : t("Ollama установлена, но не отвечает. Нажмите «Запустить».", "Ollama is installed but not responding. Click Launch.")
      }
    }
  }
  func pull(_ name: String) {
    guard !busy, !engineChecking else { return }
    if models.contains(name), engineReady {
      model = name; engineMessage = t("Модель уже установлена и выбрана: ", "Model already installed and selected: ") + name
      return
    }
    guard engineReady else { refreshModels(); return }
    guard confirm(t("Скачать локальную модель?", "Download local model?"), name + "\n" + t("3B: около 2 ГБ; 7B: около 5 ГБ. Нужен интернет. Тексты чатов не отправляются.", "3B: about 2 GB; 7B: about 5 GB. Internet required. No chat content is uploaded.")) else { return }
    busy = true; pullingModel = name; modelProgress = nil
    status = t("Подключаемся к загрузке модели…", "Connecting to model download…")
    task = Task {
      defer { busy = false; pullingModel = nil }
      do {
        try await engine.pull(name) { item in
          Task { @MainActor in
            guard self.pullingModel == name else { return }
            self.modelProgress = item
            self.status = self.pullStatus(item.status)
          }
        }
        models = try await engine.models()
        guard models.contains(name) else { throw CleanerError.message("Downloaded model not found. Refresh models and retry.") }
        model = name; engineReady = true
        status = t("Модель установлена и выбрана: ", "Model installed and selected: ") + name
        engineMessage = status; log("Local model downloaded: \(name)")
      } catch {
        status = t("Загрузка остановлена. Можно повторить и продолжить её.", "Download stopped. Retry to resume.")
        engineMessage = status
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
  func pullStatus(_ value: String) -> String {
    if value == "success" { return t("Загрузка завершена. Проверяем модель…", "Download complete. Checking model…") }
    if value.contains("verifying") { return t("Проверяем контрольную сумму…", "Verifying checksum…") }
    if value.contains("manifest") { return t("Получаем сведения о модели…", "Reading model manifest…") }
    if value.contains("pulling") { return t("Скачиваем модель…", "Downloading model…") }
    return value
  }
  func summarize() {
    guard let transcript, !model.isEmpty, !busy else { return }
    guard
      confirm(
        t("Подготовить продолжение?", "Prepare handoff?"),
        t(
          "Подтвердите, что сессия завершена. Создадим резервную копию и выжимку исходных цитат для новой сессии. Исходную историю не удаляем.",
          "Confirm the session is inactive. A backup and local handoff will be created. Original history is not deleted."
        ))
    else { return }
    busy = true
    output = ""
    let selectedModel = model
    let compression = style
    cancellation = Cancellation()
    let token = cancellation
    let backupRoot = support.appendingPathComponent("HistoryBackups")
    task = Task {
      do {
        let saved = try await Task.detached { try transcript.backup(in: backupRoot, cancellation: token) }.value
        try token.check()
        log("Verified history backup: \(saved.lastPathComponent)")
        output = try await engine.summarize(transcript, model: selectedModel, style: compression) {
          s in
          Task { @MainActor in self.status = self.t("Обработка частей: ", "Processing chunks: ") + s
          }
        }
        status = t("Проверьте результат перед продолжением", "Review before starting a new session")
      } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
      busy = false
    }
  }
  func exportContext() {
    let p = NSSavePanel()
    p.nameFieldStringValue = "\(agent)-handoff.md"
    if p.runModal() == .OK, let url = p.url {
      do { try output.write(to: url, atomically: true, encoding: .utf8) } catch {
        self.error = error.localizedDescription
      }
    }
  }
  func enableNotifications() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      granted, _ in
      Task { @MainActor in
        UserDefaults.standard.set(granted, forKey: "reminders")
        self.scheduleReminder()
      }
    }
  }
  func scheduleReminder() {
    let center = UNUserNotificationCenter.current()
    let active = entries.filter { $0.state == "quarantined" }
    guard UserDefaults.standard.bool(forKey: "reminders"), !active.isEmpty else {
      center.removePendingNotificationRequests(withIdentifiers: ["quarantine"])
      return
    }
    let body = t(
      "В карантине \(active.count) объектов: \(ByteCountFormatter.string(fromByteCount:active.reduce(0){$0+$1.bytes},countStyle:.file)). Откройте приложение для проверки.",
      "Quarantine: \(active.count) items. Open the app to review.")
    center.getPendingNotificationRequests { requests in
      guard !requests.contains(where: { $0.identifier == "quarantine" }) else { return }
      let c = UNMutableNotificationContent()
      c.title = "OxyMac Cleaner"
      c.body = body
      c.categoryIdentifier = "quarantine"
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(
          identifier: "quarantine", content: c,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5 * 24 * 3600, repeats: true)))
    }
  }

  func remind() {
    if QuarantineStore.reminderDue(
      entries: entries, last: UserDefaults.standard.object(forKey: "lastReminder") as? Date)
    {
      status = t(
        "Проверьте карантин: файлы продолжают занимать место",
        "Review quarantine: files still occupy disk space")
    }
  }
}
func runTool(_ executable: String, _ args: [String]) throws -> String {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: executable)
  p.arguments = args
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = pipe
  try p.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  let text = String(data: data, encoding: .utf8) ?? ""
  guard p.terminationStatus == 0 else { throw CleanerError.message(text) }
  return text
}
