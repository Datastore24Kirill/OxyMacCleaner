import CleanerCore
import SwiftUI
import UserNotifications
import CoreServices

@main struct CleanerApp: App {
  @StateObject private var vm = AppModel()
  @StateObject private var updater = AppUpdater()
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  var body: some Scene {
    WindowGroup("OxyMac Cleaner") {
      RootView().environmentObject(vm).environmentObject(updater)
        .preferredColorScheme(vm.theme == "light" ? .light : vm.theme == "dark" ? .dark : nil)
        .frame(minWidth: 1000, minHeight: 700)
        .onChange(of: vm.language) { _, _ in
          if !vm.busy { vm.status = vm.t("Язык интерфейса изменён", "Interface language changed") }
        }
        .onAppear {
          updater.checkOnLaunch()
          AppUpdater.markHealthy()
          delegate.model = vm
          vm.scheduleReminder()
          vm.prepareDiskAccess()
          vm.restoreScan()
        }
    }.windowStyle(.hiddenTitleBar).defaultSize(width: 1180, height: 800)
      .commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu(vm.t("Разделы", "Sections")) {
          Button(vm.t("Обзор", "Overview")) { vm.page = "overview" }.keyboardShortcut("1").disabled(updater.installing)
          Button(vm.t("Карта диска", "Disk map")) { vm.page = "map" }.keyboardShortcut("2").disabled(updater.installing)
          Button(vm.t("Xcode и проекты", "Xcode and projects")) { vm.page = "developer" }.keyboardShortcut("3").disabled(updater.installing)
          Button(vm.t("Агенты и контекст", "Agents and context")) { vm.page = "agents" }.keyboardShortcut("4").disabled(updater.installing)
          Button(vm.t("Карантин", "Quarantine")) { vm.page = "quarantine" }.keyboardShortcut("5").disabled(updater.installing)
          Button(vm.t("Файлы и папки", "Files and folders")) { vm.page = "files" }.keyboardShortcut("6").disabled(updater.installing)
          Button(vm.t("Дубликаты", "Duplicates")) { vm.page = "duplicates" }.keyboardShortcut("7").disabled(updater.installing)
          Button(vm.t("Возможности очистки", "Cleanup opportunities")) { vm.page = "advisor" }.keyboardShortcut("8").disabled(updater.installing)
          Button(vm.t("Локальный движок", "Local engine")) { vm.page = "engine" }.keyboardShortcut("9").disabled(updater.installing)
          Button(vm.t("История операций", "Operation history")) { vm.page = "history" }.keyboardShortcut("0").disabled(updater.installing)
          Button(vm.t("Архивы и загрузки", "Archives and downloads")) { vm.page = "archives" }.keyboardShortcut("1", modifiers: [.command, .shift]).disabled(updater.installing)
          Divider()
          Button(vm.t("Остановить операцию", "Stop operation")) { vm.cancel() }.keyboardShortcut(".").disabled(!vm.busy || updater.installing)
          Button(vm.t("Настройки", "Settings")) { vm.page = "settings" }.keyboardShortcut(",").disabled(updater.installing)
        }
      }
  }
}
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  weak var model: AppModel?
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Refresh only this bundle’s display metadata; never reset TCC permissions.
    LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: "quarantine",
        actions: [
          UNNotificationAction(identifier: "open", title: "Открыть карантин", options: .foreground),
          UNNotificationAction(identifier: "later", title: "Напомнить через 5 дней", options: []),
        ], intentIdentifiers: [])
    ])
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    Task { @MainActor in
      UserDefaults.standard.set(Date(), forKey: "lastReminder")
      if response.actionIdentifier != "later" { model?.page = "quarantine" }
      model?.scheduleReminder()
      completionHandler()
    }
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    Task { @MainActor in
      UserDefaults.standard.set(Date(), forKey: "lastReminder")
      model?.scheduleReminder()
      completionHandler([.banner, .sound])
    }
  }
}
struct RootView: View {
  private static let brandImage = NSImage(contentsOf: Bundle.main.url(forResource: "BrandIcon", withExtension: "png") ?? URL(fileURLWithPath: "/nonexistent")) ?? NSImage()
  @AccessibilityFocusState(for: .voiceOver) private var headingFocused: Bool
  @EnvironmentObject var updater: AppUpdater
  @State private var showHelp = false
  @State private var quarantineQuery = ""
  @State private var selectedQuarantine: Set<UUID> = []
  @EnvironmentObject var vm: AppModel
  let pages: [(String, String, String, String)] = [
    ("overview", "Обзор", "Overview", "square.grid.2x2"),
    ("advisor", "Возможности очистки", "Cleanup opportunities", "sparkles"),
    ("map", "Карта диска", "Disk map", "square.grid.3x3.fill"),
    ("files", "Файлы и папки", "Files & folders", "externaldrive"),
    ("duplicates", "Дубликаты", "Duplicates", "square.on.square"),
    ("archives", "Архивы и загрузки", "Archives & downloads", "shippingbox"),
    ("developer", "Xcode и проекты", "Xcode & projects", "hammer"),
    ("agents", "Агенты и контекст", "Agents & context", "text.bubble"),
    ("engine", "Локальный движок", "Local engine", "cpu"),
    ("quarantine", "Карантин", "Quarantine", "archivebox"),
    ("history", "История операций", "Activity", "clock"),
    ("settings", "Настройки", "Settings", "gearshape"),
  ]
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(nsImage: Self.brandImage).resizable().scaledToFit().frame(width: 58, height: 58).accessibilityLabel(
            "OxyMac Cleaner")
          VStack(alignment: .leading) {
            Text("OxyMac").font(.title2.bold())
            Text("CLEANER").font(.caption.monospaced()).tracking(3)
          }
        }.padding(.vertical, 24)
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(pages, id: \.0) { p in
              if p.0 == "overview" || p.0 == "developer" || p.0 == "quarantine" {
                Text(p.0 == "overview" ? vm.t("ОЧИСТКА", "CLEANUP") : p.0 == "developer" ? vm.t("РАЗРАБОТЧИКУ", "DEVELOPER") : vm.t("УПРАВЛЕНИЕ", "MANAGE"))
                  .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).padding(.leading, 11)
              }
              Button {
                vm.page = p.0
                vm.search = ""
                vm.categoryFilter = "all"
              } label: {
                Label(vm.t(p.1, p.2), systemImage: p.3).frame(
                  maxWidth: .infinity, alignment: .leading
                )
                .padding(11).background(
                  vm.page == p.0 ? Color.mint.opacity(0.18) : .clear,
                  in: RoundedRectangle(cornerRadius: 10))
              }.accessibilityValue(vm.page == p.0 ? vm.t("Выбран", "Selected") : "").help(vm.t("Открыть раздел: ", "Open section: ") + vm.t(p.1, p.2)).buttonStyle(
                .plain)
            }
          }
        }
        Spacer()
        Text(vm.t("ЛОКАЛЬНО · ПОД ВАШИМ КОНТРОЛЕМ", "LOCAL · UNDER YOUR CONTROL")).font(
          .system(size: 9, weight: .semibold)
        ).foregroundStyle(.secondary)
        Text("0.4.13 · Preview").font(.caption).foregroundStyle(.secondary)
      }.padding(18).frame(width: 240).background(.thinMaterial)
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text(pages.first { $0.0 == vm.page }.map { vm.t($0.1, $0.2) } ?? "").font(
            .largeTitle.bold()).accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
            .onChange(of: vm.page) { _, _ in headingFocused = true }
          Spacer()
          Button {
            showHelp = true
          } label: {
            Label(vm.t("Как пользоваться", "How to use"), systemImage: "questionmark.circle")
          }.oxyHelp(.help)
            .popover(isPresented: $showHelp) {
              SectionHelpView(page: vm.page, developerSection: vm.developerSection).environmentObject(
                vm)
            }
          if vm.busy {
            if !vm.isScanning { ProgressView().controlSize(.small) }
            Button(vm.t("Стоп", "Stop")) { vm.cancel() }.oxyHelp(.stop)
          }
        }.padding(.top, 22)
        if let release = updater.release {
          HStack {
            Text(vm.t("Доступно обновление: ", "Update available: ") + release.version)
            Button(vm.t("Подробнее", "Details")) { vm.page = "settings" }
          }.font(.callout)
        }
        if updater.installing { ProgressView(updater.status, value: updater.fraction) }
        if let progress = vm.scanProgress, vm.isScanning {
          ScanProgressView(progress: progress, active: vm.isScanning)
        }
        if vm.recoveredInterruptedScan {
          HStack {
            Text(vm.t("Восстановлен неполный результат прерванного обхода. Для актуальных данных нужен новый обход.", "Partial results recovered from an interrupted scan. A new traversal is required for current data."))
            Button(vm.t("Повторить обход", "Repeat scan")) { vm.scan() }.disabled(vm.busy)
          }.font(.callout)
        }
        if let date = vm.snapshotDate {
          Text(
            vm.t("Снимок от ", "Snapshot from ") + date.formatted()
              + (vm.report.complete ? "" : vm.t(" · неполный обход", " · partial scan"))
              + vm.t(". Данные могли измениться.", ". Files may have changed.")
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Group {
          switch vm.page {
          case "overview": overview
          case "advisor": CleanupAdvisorView().environmentObject(vm)
          case "map": DiskMapView().environmentObject(vm)
          case "files", "archives": FileBrowserView().environmentObject(vm)
          case "duplicates": duplicates
          case "developer": developer
          case "agents": agents
          case "engine": engine
          case "quarantine": quarantine
          case "history":
            ScrollView {
              Text(vm.logs.reversed().joined(separator: "\n\n")).font(
                .system(.caption, design: .monospaced)
              ).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
          case "settings": settings
          default: overview
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        HStack {
          Circle().fill(vm.busy ? Color.orange : Color.mint).frame(width: 6, height: 6)
          Text(
            vm.status.isEmpty
              ? vm.t(
                "Готово. Выберите диск и запустите сканирование.",
                "Ready. Select a disk and start scanning.")
              : vm.status
          ).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          Spacer()
        }.padding(.bottom, 16)
      }.padding(.horizontal, 28)
    }.disabled(updater.installing).sheet(isPresented: $vm.showDiskAccess) { DiskAccessView().environmentObject(vm) }
      .sheet(isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
        ErrorRecoveryView(raw: vm.error ?? "").environmentObject(vm)
      }
  }
  func note(_ ru: String, _ en: String) -> some View {
    Text(vm.t(ru, en)).font(.callout).foregroundStyle(.secondary).fixedSize(
      horizontal: false, vertical: true)
  }
  func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14, content: content).padding(20).frame(
      maxWidth: .infinity, alignment: .leading
    ).background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(
      RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
  }
  func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
  var scanButtons: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(
          systemName: vm.volumes.first(where: { $0.id == vm.volumeID })?.internalDisk == false
            ? "externaldrive.fill" : "internaldrive.fill"
        ).font(.title).foregroundStyle(.teal)
        Picker(
          vm.t("Диск", "Disk"),
          selection: Binding(get: { vm.volumeID }, set: { vm.selectVolume($0) })
        ) {
          ForEach(vm.volumes) { volume in Text(volume.name).tag(volume.id) }
          if vm.volumeID == "custom" {
            Text(vm.t("Выбранная папка", "Selected folder")).tag("custom")
          }
        }.oxyHelp(.volume).labelsHidden().frame(maxWidth: 340)
        Button {
          vm.refreshVolumes()
        } label: {
          Image(systemName: "arrow.clockwise")
        }.oxyHelp(.refreshVolumes)
        Spacer()
        if !vm.report.complete, vm.report.checkpoint != nil {
          Button(vm.t("Продолжить обход", "Resume scan")) { vm.scan(resume: true) }
            .help(vm.t("Завершённые папки сохранят прежние результаты, незавершённые будут проверены заново. Для полностью свежих данных запустите новый скан.", "Completed folders retain previous observations; unfinished folders are rescanned. Start a new scan for fresh data."))
        }
        Button(
          vm.t(
            vm.volumeID == "custom" ? "Сканировать папку" : "Сканировать диск",
            vm.volumeID == "custom" ? "Scan folder" : "Scan disk")
        ) { vm.scan() }.oxyHelp(.scan).buttonStyle(.borderedProminent).tint(.teal)
      }.disabled(vm.busy)
      if let disk = vm.volumes.first(where: { $0.id == vm.volumeID }) {
        ProgressView(value: Double(disk.used), total: Double(max(1, disk.total))).tint(.teal)
        Text(
          vm.t("Занято: ", "Used: ") + size(disk.used) + vm.t(" · Свободно: ", " · Available: ")
            + size(disk.available) + vm.t(" · Всего: ", " · Total: ") + size(disk.total)
        ).font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button(vm.t("Выбрать отдельную папку…", "Choose a specific folder…")) { vm.chooseRoots() }
          .oxyHelp(.folder)
          .buttonStyle(.link).disabled(vm.busy)
        Spacer()
        Button(vm.t("Доступ к диску", "Disk access")) {
          vm.pendingDiskScan = false
          vm.showDiskAccess = true
        }.oxyHelp(.access).buttonStyle(.link)
      }
      note(
        "Проверяем доступные данные выбранного диска. Защищённые macOS объекты будут отмечены в отчёте; для расширенного сканирования может понадобиться полный доступ к диску.",
        "Scans accessible data on the selected disk. macOS-protected items appear in the report; broader coverage may require Full Disk Access."
      )
    }
  }
  var overview: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        card {
          Text(vm.t("Больше места. Меньше догадок.", "More space. Less guesswork.")).font(
            .title.bold())
          note(
            "Найдите тяжёлые файлы, сравните копии и сохраните важное. Сканирование ничего не удаляет.",
            "Find large files, compare copies and keep what matters. Scanning never deletes files.")
          scanButtons
          ForEach(vm.roots, id: \.path) { Text($0.path).font(.caption).textSelection(.enabled) }
        }
        HomeShortcuts()
        HStack {
          metric(
            vm.t("Найдено файлов", "Files found"),
            "\(vm.isScanning ? (vm.scanProgress?.files ?? 0) : vm.report.files.count)")
          metric(
            vm.t("Логический объём", "Logical size"),
            size(vm.isScanning ? (vm.scanProgress?.bytes ?? 0) : vm.report.total))
          metric(
            vm.t("В карантине", "In quarantine"),
            size(vm.entries.filter { $0.state == "quarantined" }.reduce(0) { $0 + $1.bytes }))
        }
        note(
          "Размер файлов не равен гарантированно освобождаемому месту: APFS может совместно хранить данные. Карантин пока занимает диск.",
          "File sizes are not guaranteed recoverable space: APFS may share blocks. Quarantine still occupies disk."
        )
        if !vm.report.issues.isEmpty {
          DisclosureGroup(
            vm.t(
              "Пропуски и ошибки: \(vm.report.issues.count)",
              "Skipped / errors: \(vm.report.issues.count)")
          ) {
            Text(vm.report.issues.prefix(100).joined(separator: "\n")).font(.caption).textSelection(
              .enabled)
          }.oxyHelp(.disclosure)
        }
        card {
          Label(vm.t("Первая тестовая версия", "First preview"), systemImage: "testtube.2").font(
            .headline)
          note(
            "Карантин файлов и обычных папок на одном диске готов. DerivedData и архивы очищаются в разделе Xcode. Симуляторы удаляются штатным simctl после подтверждения. Истории агентов импортируются вручную; базы чатов не изменяются.",
            "File and ordinary-folder quarantine on the same disk is available. DerivedData and archives are managed under Xcode. Simulator deletion uses simctl after confirmation. Agent histories are imported manually; chat databases are never modified."
          )
        }
      }
    }
  }
  func metric(_ title: String, _ value: String) -> some View {
    card {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.title2.bold()).monospacedDigit()
    }
  }
  var duplicates: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionIntro(icon: "square.on.square.fill", title: vm.t("Оставьте одну копию", "Keep one copy"), subtitle: vm.t("Сравним содержимое файлов и поможем выбрать лишние.", "Compare file contents and review extra copies."))
      note(
        "Сначала выполните сканирование. Проверяем содержимое; ссылки не считаем отдельными копиями. Выберите лишние файлы, сохранив минимум одну копию.",
        "Scan first. Contents are verified; hard links are not separate copies. Select extras while retaining at least one copy."
      )
      HStack {
        Button(vm.t("Найти точные копии", "Find exact duplicates")) { vm.findDuplicates() }.oxyHelp(
          .duplicates
        )
        .disabled(vm.busy || vm.report.files.isEmpty)
        Spacer()
        Button(vm.t("В карантин", "Quarantine")) { vm.quarantineSelected() }.oxyHelp(.quarantine)
          .disabled(
            vm.selected.isEmpty || vm.busy)
      }
      HStack {
        Button(vm.t("Выбрать лишние копии", "Select extra copies")) {
          vm.selected = Set(vm.duplicates.flatMap { group in
            group.sorted { $0.path < $1.path }.dropFirst().filter { vm.fileSelectable($0) }.map(\.path)
          })
        }.disabled(vm.busy || vm.duplicates.isEmpty)
          .help(vm.t("Оставляет первую по пути копию в каждой группе. Проверьте, какую копию хотите сохранить.", "Keeps the first path in each group. Review which copy you want to keep."))
        Button(vm.t("Снять выбор", "Clear selection")) { vm.selected = [] }.disabled(vm.busy || vm.selected.isEmpty)
      }
      SpaceEstimateView()
      List {
        ForEach(Array(vm.duplicates.enumerated()), id: \.offset) { _, group in
          Section("\(group.count) × \(size(group[0].bytes))") {
            ForEach(group) { f in
              Toggle(
                isOn: Binding(
                  get: { vm.selected.contains(f.path) },
                  set: { if $0 { vm.selected.insert(f.path) } else { vm.selected.remove(f.path) } })
              ) { Text(f.path).font(.caption).textSelection(.enabled) }.oxyHelp(.selectDuplicate)
                .toggleStyle(.checkbox).disabled(vm.busy || !vm.fileSelectable(f))
                .contextMenu { FileActions(path: f.path, file: f) }
            }
          }
        }
      }
    }
  }
  var developer: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker(vm.t("Раздел", "Section"), selection: $vm.developerSection) {
        Text(vm.t("Архивы Xcode", "Xcode archives")).tag("archives")
        Text(vm.t("Кэши сборки", "Build caches")).tag("derived")
        Text(vm.t("Симуляторы", "Simulators")).tag("simulators")
        Text(vm.t("Тестовые симуляторы", "Test simulators")).tag("testSimulators")
        Text(vm.t("Рабочие деревья", "Worktrees")).tag("worktrees")
        Text(vm.t("Данные проектов", "Project data")).tag("projectData")
      }.oxyHelp(.developerTab).pickerStyle(.segmented)
      if !vm.developerResult.isEmpty {
        DisclosureGroup(vm.t("Результат последней операции", "Last operation result")) {
          ScrollView { Text(vm.developerResult).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180)
        }
      }
      ScrollView {
        if vm.developerSection == "archives" {
          card { XcodeArchiveView().environmentObject(vm) }
        } else if vm.developerSection == "testSimulators" {
          card { TestSimulatorView().environmentObject(vm) }
        } else if vm.developerSection == "derived" {
          card { DerivedDataView().environmentObject(vm) }
        } else if vm.developerSection == "projectData" {
          card { ProjectDataView().environmentObject(vm) }
        } else if vm.developerSection == "worktrees" {
          card { WorktreeView().environmentObject(vm) }
        } else {
          card { SimulatorCleanupView().environmentObject(vm) }
        }
      }
    }
  }
  var agents: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SectionIntro(icon: "text.bubble.fill", title: vm.t("Продолжите работу с коротким контекстом", "Continue with a shorter context"), subtitle: vm.t("1. Выберите историю   2. Подготовьте пересказ   3. Проверьте и перенесите", "1. Choose a history   2. Prepare a summary   3. Review and transfer"))
        card {
          Picker(vm.t("Агент", "Agent"), selection: $vm.agent) {
            ForEach(Agents.catalog) { Text($0.name).tag($0.id) }
          }.oxyHelp(.agent).disabled(vm.busy).onChange(of: vm.agent) { _, _ in
            vm.transcript = nil
            vm.sessionCatalog = nil
            vm.output = ""
          }
          if let definition = Agents.catalog.first(where: { $0.id == vm.agent }) {
            Text(definition.nativeFormat.map { vm.t("Формат истории: ", "History format: ") + $0 }
              ?? vm.t("Импорт экспорта", "Export import")).font(.subheadline).bold()
            Text(definition.importLimitations(russian: vm.t("ru", "en") == "ru"))
              .font(.caption).foregroundStyle(.secondary)
            let paths = definition.locations(home: vm.home)
            note(
              paths.isEmpty
                ? "Стандартное расположение не найдено. Можно импортировать экспорт сессии."
                : "Обнаружено расположение данных. Это не означает поддержку внутреннего формата истории.",
              paths.isEmpty
                ? "Default location not found. You can import a session export."
                : "Data location found. This does not imply support for its internal history format."
            )
            ForEach(paths, id: \.path) { url in
              HStack {
                Text(url.path).font(.caption).lineLimit(2)
                Spacer()
                Button(vm.t("Посмотреть файлы", "View files")) {
                  vm.scan([url])
                  vm.page = "files"
                }.oxyHelp(.agentSize).disabled(vm.busy)
              }
            }
          }
          if ["codex", "claude", "cursor", "gemini", "continue", "cline", "roo", "aider", "opencode"].contains(vm.agent) {
            if vm.agent != "opencode" { SessionCatalogView() }
            else { Text(vm.t("Выберите JSON, созданный командой opencode export для одной сессии. База данных не читается.", "Choose JSON from opencode export for one session. The database is not read.")).font(.caption) }
            Button(vm.t("Открыть историю агента…", "Open agent history…")) {
              vm.importTranscript(native: true)
            }.disabled(vm.busy).help(vm.t(
              "Выберите одну историю поддерживаемого агента. JSON — до 30 MB; JSONL — до 1 GB. Только чтение; оригинал и неизвестные записи сохраняются.",
              "Choose one supported agent history. JSON up to 30 MB; JSONL up to 1 GB. Read only; original and unknown records are preserved."))
          }
          Button(vm.t("Импортировать одну сессию", "Import one session")) { vm.importTranscript() }
            .oxyHelp(.importSession)
            .disabled(vm.busy)
          note(
            "TXT / MD / JSON / JSONL. Прямое чтение баз и запуск новой сессии пока не реализованы. Результат можно скопировать в новый чат нужного агента.",
            "TXT / MD / JSON / JSONL. Direct database access and new-session launch are not implemented yet. Copy the handoff into a new chat of the selected agent."
          )
        }
        if let input = vm.transcript {
          card {
            Text(input.source.lastPathComponent).font(.headline)
            if let streamed = input.streaming {
              Text(vm.t("Потоковый импорт: ", "Streaming import: ") + ByteCountFormatter.string(fromByteCount: streamed.bytes, countStyle: .file)).font(.caption)
            } else {
            Text(
              vm.t(
                "Исходник: \(input.text.count) символов", "Original: \(input.text.count) characters"
              )
            ).font(.caption)
            }
            if let report = input.nativeHistory {
              Text(vm.t("История: сообщений ", "History: messages ") + "\(report.messages)"
                + vm.t(" · других записей сохранено: ", " · other records retained: ") + "\(report.retainedRecords)")
                .font(.caption)
              Text(vm.t("Записи идут в порядке файла, включая ветки и служебные события. Сжатие создаёт отдельный текст для нового чата; оригинальная история не уменьшается и не удаляется.",
                "Records remain in file order, including branches and system events. Compression creates separate text for a new chat; original history is not shrunk or deleted."))
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
              Picker(vm.t("Режим", "Mode"), selection: $vm.style) {
                Text(vm.t("Бережный", "Careful")).tag("Бережный")
                Text(vm.t("Сбалансированный", "Balanced")).tag("Сбалансированный")
                Text(vm.t("Краткий", "Concise")).tag("Краткий")
              }.oxyHelp(.summaryStyle).disabled(vm.busy)
              Button(vm.t("Оптимизировать для продолжения", "Optimize for continuation")) { vm.summarize() }.oxyHelp(
                .summarize
              )
              .buttonStyle(.borderedProminent).disabled(vm.busy || vm.model.isEmpty)
            }
            Button(vm.t("Начать с чистого контекста…", "Prepare a clean context…")) { vm.prepareCleanContext() }
              .disabled(vm.busy).help(vm.t("Создаёт проверенную копию и пустой шаблон новой задачи без вызова модели. Новый чат открывается вами в агенте; исходная история остаётся.", "Creates a verified backup and a blank task template without a model call. Open the new chat in your agent; original history remains."))
            Text(vm.t("Результат — цитаты исходных строк со ссылками, а не свободный пересказ. Проверьте актуальность решений перед переносом. Фильтр секретов не гарантирует обнаружение всех значений.", "The result uses cited source excerpts, not free-form paraphrase. Review current decisions before transfer. Secret filtering cannot detect every value.")).font(.caption).foregroundStyle(.secondary)
            if vm.model.isEmpty {
              Button(vm.t("Настроить локальную модель", "Set up local model")) {
                vm.page = "engine"
              }.oxyHelp(.engine)
            }
          }
        }
        if !vm.output.isEmpty {
          ContextComparisonView()
          card {
            HStack {
              Text(
                vm.t(
                  "Результат: \(vm.output.count) символов", "Result: \(vm.output.count) characters")
              )
              Spacer()
              Button(vm.t("Копировать", "Copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(vm.output, forType: .string)
              }.oxyHelp(.copy)
              Button(vm.t("Экспорт MD", "Export MD")) { vm.exportContext() }.oxyHelp(.export)
            }
            TextEditor(text: $vm.output).oxyHelp(.editor).font(.system(.body, design: .monospaced))
              .frame(
                minHeight: 320)
            note(
              "Проверьте и дополните результат перед переносом: он не заменяет полную историю. Резервная копия сохранена.",
              "Review and complete the result before transfer; it does not replace the full history. A verified backup is retained."
            )
          }
        }
      }
    }
  }
  var engine: some View { EnginePanel() }
  var visibleQuarantine: [QuarantineEntry] {
    vm.entries.filter { ["quarantined", "prepared", "restoring", "attention", "restored-copy"].contains($0.state)
      && (quarantineQuery.isEmpty || $0.original.localizedCaseInsensitiveContains(quarantineQuery)) }
  }
  var quarantine: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionIntro(icon: "arrow.uturn.backward.circle.fill", title: vm.t("Вернуть или удалить", "Restore or remove"), subtitle: vm.t("Здесь хранятся отложенные файлы. Пока они занимают место.", "Your set-aside files remain here and still occupy space."))
      note(
        "Файлы здесь продолжают занимать диск. Удаление безвозвратно; восстановление не перезаписывает существующие файлы.",
        "Files here still occupy disk space. Deletion is permanent; restoration never overwrites existing files."
      )
      HStack {
        Menu(vm.t("Ещё", "More")) {
          Button(vm.t("Напоминать каждые 5 дней", "Remind every 5 days")) {
            vm.enableNotifications()
          }
          .oxyHelp(.notify)
          Button(vm.t("Проверить незавершённые операции", "Check interrupted operations")) {
            vm.recoverQuarantine()
          }.oxyHelp(.recover).disabled(vm.busy)
          Button(vm.t("Открыть папку", "Open folder")) { vm.reveal(vm.quarantine.root.path) }
            .oxyHelp(
              .finder)
        }.help(
          vm.t(
            "Напоминания, папка карантина и проверка прерванных операций.",
            "Reminders, quarantine folder and interrupted-operation checks.")
        )
        .fixedSize()
        Spacer()
        Button(
          vm.t("Удалить все архивы из карантина…", "Permanently delete quarantined archives…"),
          role: .destructive
        ) { vm.eraseQuarantinedArchives() }.oxyHelp(.eraseArchives)
          .disabled(
            vm.busy || !vm.entries.contains { $0.state == "quarantined" && $0.isArchive }
          )
      }
      TextField(vm.t("Поиск в карантине", "Search quarantine"), text: $quarantineQuery)
        .onChange(of: quarantineQuery) { _, _ in selectedQuarantine = [] }
      QuarantineSelection(selected: $selectedQuarantine, entries: visibleQuarantine)
      if visibleQuarantine.isEmpty { Text(vm.t("В карантине нет подходящих объектов.", "No matching quarantine items.")).foregroundStyle(.secondary) }
      List(visibleQuarantine) { e in
        VStack(alignment: .leading, spacing: 8) {
          Toggle(URL(fileURLWithPath: e.original).lastPathComponent, isOn: Binding(
            get: { selectedQuarantine.contains(e.id) },
            set: { if $0 { selectedQuarantine.insert(e.id) } else { selectedQuarantine.remove(e.id) } }
          )).toggleStyle(.checkbox).font(.headline).disabled(e.state != "quarantined")
          Text(
            (e.kind == "directory" ? vm.t("Папка", "Folder") : vm.t("Файл", "File")) + " · "
              + vm.quarantineState(e.state)
          ).font(.caption).foregroundStyle(.secondary)
          Text(e.original).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          if let external = e.externalPayload { Text(external).font(.caption).textSelection(.enabled) }
          Button(vm.t("Копировать исходный путь", "Copy original path")) { vm.copyPath(e.original) }.font(.caption)
          QuarantineInspectionView(entry: e)
          HStack {
            Text(size(e.bytes))
            Text(e.date.formatted())
            Spacer()
            if e.state == "quarantined" {
              Button(vm.t("На другой диск…", "Move to another disk…")) { vm.relocateQuarantine(e) }
                .disabled(vm.busy).help(vm.t("Копирует в выбранную папку, проверяет содержимое и только затем убирает прежнюю копию карантина.", "Copies to the selected folder, verifies content, then removes the previous quarantine payload."))
            }
            Button(vm.t("Вернуть", "Restore")) { vm.restore(e) }.oxyHelp(.restore)
            Button(vm.t("Вернуть в…", "Restore to…")) { vm.restore(e, alternate: true) }.oxyHelp(
              .restoreElsewhere)
            Button(role: .destructive) {
              vm.erase(e)
            } label: {
              Image(systemName: "trash")
            }.oxyHelp(.erase).disabled(e.state != "quarantined")
          }.font(.caption)
        }.padding(.vertical, 6)
      }.disabled(vm.busy)
    }
  }
  var settings: some View {
    Form {
      Picker(vm.t("Оформление", "Appearance"), selection: $vm.theme) {
        Text(vm.t("Системное", "System")).tag("system")
        Text(vm.t("Светлое", "Light")).tag("light")
        Text(vm.t("Тёмное", "Dark")).tag("dark")
      }.oxyHelp(.theme)
      Picker("Language / Язык", selection: $vm.language) {
        Text("Русский").tag("ru")
        Text("English").tag("en")
      }.oxyHelp(.language)
      Section(vm.t("Исключения", "Exclusions")) {
        ForEach(vm.exclusions, id: \.self) { p in
          HStack {
            Text(p).font(.caption)
            Spacer()
            Button(vm.t("Убрать", "Remove")) {
              vm.exclusions.removeAll { $0 == p }
              UserDefaults.standard.set(vm.exclusions, forKey: "exclusions")
            }.oxyHelp(.removeExclusion)
          }
        }
      }
      Section(vm.t("Доступ и данные", "Access & data")) {
        Button(vm.t("Проверить доступ к диску", "Check disk access")) {
          vm.pendingDiskScan = false
          vm.showDiskAccess = true
        }.oxyHelp(.access)
        Text(
          vm.t(
            "Выбирайте диск или отдельную папку для сканирования. Недоступные объекты будут перечислены в отчёте. Доступ к записи экрана не нужен.",
            "Choose a disk or specific folder to scan. Inaccessible items appear in the report. Screen recording is not required."
          ))
        Button(vm.t("Папка данных приложения", "Application data folder")) {
          vm.reveal(vm.support.path)
        }.oxyHelp(.finder)
      }
      Section(vm.t("Обновления", "Updates")) {
        AppUpdateView().environmentObject(vm)
        Button("GitHub Releases") {
          NSWorkspace.shared.open(
            URL(string: "https://github.com/Datastore24Kirill/OxyMacCleaner/releases")!)
        }.oxyHelp(.releases)
      }
    }.formStyle(.grouped)
  }
}
