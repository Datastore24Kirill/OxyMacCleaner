import CleanerCore
import SwiftUI

extension AppModel {
  func chooseDataProject() {
    guard !busy else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    if panel.runModal() == .OK, let url = panel.url {
      dataProject = url
      UserDefaults.standard.set(url.path, forKey: "dataProject")
      readProjectData()
    }
  }
  func readProjectData() {
    guard !busy, let root = dataProject else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    projectData = []
    projectDataDate = nil
    projectDataIssue = nil
    status = t("Изучаем данные проекта…", "Inspecting project data…")
    task = Task {
      do {
        projectData = try await Task.detached {
          try ProjectData.inventory(root, cancellation: token)
        }.value
        projectDataDate = Date()
        status = t("Данные проекта прочитаны", "Project data inspected")
      } catch {
        projectDataIssue = error.localizedDescription
        status = t("Проверка неполная", "Inspection incomplete")
      }
      busy = false
    }
  }
  func cleanProjectData(_ item: ProjectDataItem) {
    guard !busy, item.cleanable else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let excluded = exclusions
    status = t("Проверяем возможность очистки…", "Checking cleanup eligibility…")
    task = Task {
      do {
        let plan = try await Task.detached {
          try ProjectData.prepare(item, exclusions: excluded, cancellation: token)
        }.value
        try token.check()
        guard
          confirm(
            t("Очистить кэш проекта?", "Clean project cache?"),
            item.id + "\n\n" + item.recovery + "\n\n"
              + t(
                "Удаление без Корзины и карантина. Следующая сборка будет дольше. Не запускайте сборку или сервер во время очистки. Команды восстановления автоматически не выполняются.",
                "Deletes without Trash or quarantine. The next build may take longer. Do not start builds or servers during cleanup. Recovery commands are not run automatically."
              ), destructive: true)
        else {
          busy = false
          status = t("Очистка отменена", "Cleanup cancelled")
          return
        }
        try await Task.detached {
          try ProjectData.remove(plan, exclusions: excluded, cancellation: token)
        }.value
        projectData.removeAll { $0.id == item.id }
        await reconcileRemovedPaths([item.id])
        projectDataDate = Date()
        log("Project cache removed: " + item.id)
        status = t("Кэш проекта очищен", "Project cache cleaned")
      } catch {
        self.error = error.localizedDescription
        status = t(
          "Очистка не подтверждена. Обновите список.", "Cleanup not confirmed. Refresh the list.")
      }
      busy = false
    }
  }
}
struct ProjectDataView: View {
  @EnvironmentObject var vm: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(vm.t("Генерируемые данные и зависимости", "Generated data and dependencies")).font(
        .title3.bold())
      Text(
        vm.t(
          "Выберите корень проекта. Проверяем известные папки, не исполняя код проекта и команды установки.",
          "Choose the project root. Known folders are inspected without executing project code or install commands."
        ))
      ProjectDiscoveryView()
      HStack {
        Button(vm.t("Выбрать проект…", "Choose project…")) { vm.chooseDataProject() }
        Button(vm.t("Обновить список", "Refresh list")) { vm.readProjectData() }.disabled(
          vm.dataProject == nil)
      }.disabled(vm.busy).help(
        vm.t(
          "Читает размеры известных данных в выбранном проекте. Ничего не удаляет.",
          "Reads known data sizes in the chosen project. Deletes nothing."))
      if let root = vm.dataProject { Text(root.path).font(.caption).textSelection(.enabled) }
      if let issue = vm.projectDataIssue { Text(issue).foregroundStyle(.orange) }
      if let date = vm.projectDataDate {
        Text(vm.t("Проверено: ", "Checked: ") + date.formatted()).font(.caption)
        if vm.projectData.isEmpty {
          Text(
            vm.t(
              "Поддерживаемые папки не найдены. Произвольные build/dist не считаем мусором.",
              "No supported folders found. Arbitrary build/dist directories are not treated as junk."
            ))
        }
      }
      ForEach(vm.projectData) { item in row(item) }
      Text(
        vm.t(
          "Очистка: только .next/cache/webpack и Rust target/{debug,release}/incremental. Нужен Git-корень, ignored-каталог без отслеживаемых и защищённых файлов, без изменений 10 минут и открытых файлов. Остальные зависимости — только просмотр.",
          "Cleanup supports only .next/cache/webpack and Rust target/{debug,release}/incremental. Requires a Git root, ignored directory without tracked/protected data, no changes for 10 minutes and no open files. Other dependencies are review-only."
        )
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
  private func row(_ item: ProjectDataItem) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(item.rule).font(.headline)
        Spacer()
        Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
      }
      Text(item.id).font(.caption).textSelection(.enabled)
      Text(item.recovery).font(.callout)
      Text(
        item.cleanable
          ? vm.t(
            "Кэш: перед очисткой нужны дополнительные проверки.",
            "Cache: additional checks required before cleanup.")
          : vm.t(
            "Только просмотр: зависимости могут содержать локальные изменения или невосстановимые данные.",
            "Review only: dependencies may contain local edits or unrecoverable data.")
      )
      .foregroundStyle(.secondary).font(.caption)
      if item.issues > 0 {
        Text(vm.t("Неполная проверка: ", "Incomplete inspection: ") + "\(item.issues)")
          .foregroundStyle(.orange)
      }
      HStack {
        Button(vm.t("Показать в Finder", "Reveal in Finder")) { vm.reveal(item.id) }.oxyHelp(
          .finder)
        Button(vm.t("Проверить и очистить…", "Check & clean…")) { vm.cleanProjectData(item) }
          .disabled(vm.busy || !item.cleanable || item.issues > 0)
          .help(
            vm.t(
              "Проверяет Git, процессы, секреты и содержимое. После подтверждения повторяет проверки и удаляет только этот кэш.",
              "Checks Git, processes, secrets and contents. Rechecks after confirmation and removes only this cache."
            ))
      }
    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
  }
}
