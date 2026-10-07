import CleanerCore
import SwiftUI

extension AppModel {
  func findAgentSessions() {
    guard !busy, ["codex", "claude"].contains(agent),
      let definition = Agents.catalog.first(where: { $0.id == agent }) else { return }
    let selected = agent
    let roots = definition.locations(home: home)
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    sessionCatalog = nil
    status = t("Ищем файлы сессий…", "Finding session files…")
    task = Task {
      do {
        let result = try await Task.detached {
          try SessionCatalog.discover(roots: roots, cancellation: token)
        }.value
        if agent == selected { sessionCatalog = result }
        status = t("Список файлов обновлён", "Session file list refreshed")
      } catch { status = error.localizedDescription }
      busy = false
    }
  }
  func openAgentSession(_ url: URL) {
    guard !busy else { return }
    let selected = agent
    busy = true
    transcript = nil
    output = ""
    task = Task {
      do {
        let loaded = try await Task.detached { try Transcript.loadNative(url, agent: selected) }.value
        if selected == agent { transcript = loaded }
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
}
struct SessionCatalogView: View {
  @EnvironmentObject var vm: AppModel
  @State private var query = ""
  @State private var shown = 20
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button(vm.t("Найти сессии", "Find sessions")) { vm.findAgentSessions() }
        .disabled(vm.busy).help(vm.t("Читает имена, даты и размеры JSONL в стандартных папках. Содержимое проверяется только при открытии.", "Reads JSONL names, dates and sizes in default folders. Content is validated only when opened."))
      if let catalog = vm.sessionCatalog {
        Text(vm.t("Найдено файлов: ", "Files found: ") + "\(catalog.files.count)")
        if catalog.issues > 0 || catalog.limited {
          Text(vm.t("Список неполный. Пропусков: ", "List incomplete. Skipped: ") + "\(catalog.issues)"
            + (catalog.limited ? vm.t(" · достигнут предел обхода", " · scan limit reached") : ""))
            .foregroundStyle(.orange)
        }
        TextField(vm.t("Поиск по имени или пути", "Search name or path"), text: $query)
          .onChange(of: query) { _, _ in shown = 20 }
        let filtered = catalog.files.filter { query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) }
        if filtered.isEmpty { Text(vm.t("Подходящих файлов нет. Можно выбрать историю вручную.", "No matching files. You can choose a history manually.")) }
        ForEach(Array(filtered.prefix(shown))) { file in
          VStack(alignment: .leading, spacing: 4) {
            Text(file.url.lastPathComponent).font(.headline).textSelection(.enabled)
            Text(file.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
              Text(file.modified.formatted() + " · " + ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file)).font(.caption)
              Spacer()
              Button(vm.t("Открыть", "Open")) { vm.openAgentSession(file.url) }
                .disabled(vm.busy || !file.importable)
                .help(vm.t("Загружает одну историю и проверяет агента и ID сессии. Исходник не меняется.", "Loads one history and validates agent and session ID. Original is unchanged."))
            }
            if !file.importable { Text(vm.t("Пустой файл или размер больше 30 MB", "Empty file or larger than 30 MB")).font(.caption).foregroundStyle(.orange) }
          }.padding(8).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        if filtered.count > shown { Button(vm.t("Показать ещё", "Show more")) { shown += 20 } }
        Text(vm.t("Это файлы-кандидаты, не подтверждённые сессии. Дата изменения не гарантирует, что агент закончил работу. Список не читает тексты чатов и ничего не удаляет.", "These are candidate files, not validated sessions. Modification time does not prove inactivity. Listing does not read chat contents or delete anything.")).font(.caption).foregroundStyle(.secondary)
      }
    }.onChange(of: vm.agent) { _, _ in query = ""; shown = 20 }
  }
}
