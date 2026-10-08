import CleanerCore
import SwiftUI

struct ProjectDiscoveryView: View {
  @EnvironmentObject var vm: AppModel
  @State private var result: ProjectDiscoveryResult?
  @State private var filter = ""
  @State private var location = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button(vm.t("Найти проекты в папке…", "Find projects in folder…")) { choose() }.disabled(vm.busy)
        .help(vm.t("Ищет признаки проектов без запуска их кода. Не обходит зависимости, облачные файлы и исключения. Ничего не удаляет.", "Finds project markers without running code. Skips dependencies, cloud files and exclusions. Deletes nothing."))
      if let result {
        Text(location).font(.caption).textSelection(.enabled)
        Text(vm.t("Найдено проектов: ", "Projects found: ") + String(result.projects.count))
        if result.incomplete { Text(vm.t("Поиск неполный: остановлен, достигнут лимит или есть недоступные пути. Выберите более узкую папку.", "Search incomplete: cancelled, limit reached or paths inaccessible. Choose a narrower folder.")).foregroundStyle(.orange) }
        TextField(vm.t("Поиск проекта по пути", "Filter projects by path"), text: $filter)
        ForEach(result.projects.filter { filter.isEmpty || $0.id.localizedCaseInsensitiveContains(filter) }.prefix(100)) { project in
          HStack {
            VStack(alignment: .leading) {
              Text(project.url.lastPathComponent).font(.headline)
              Text(project.id).font(.caption).textSelection(.enabled)
              Text(project.markers.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if project.markers.contains(".git") {
              Button(vm.t("Рабочие деревья", "Worktrees")) {
                vm.worktreeRepository = project.url; vm.developerSection = "worktrees"; vm.readWorktrees()
              }.disabled(vm.busy).accessibilityLabel(vm.t("Рабочие деревья проекта ", "Project worktrees: ") + project.url.lastPathComponent)
            }
            Button(vm.t("Проверить данные", "Inspect data")) {
              vm.dataProject = project.url; UserDefaults.standard.set(project.id, forKey: "dataProject"); vm.readProjectData()
            }.disabled(vm.busy).accessibilityLabel(vm.t("Проверить данные проекта ", "Inspect project data: ") + project.url.lastPathComponent)
          }
        }
        Text(vm.t("Показаны первые 100 совпадений. Проверка данных связывает кэши с выбранным проектом и показывает способ восстановления; очистка требует отдельных проверок.", "First 100 matches shown. Inspect data associates caches with the selected project and explains recovery; cleanup requires separate checks.")).font(.caption)
      }
    }
  }
  private func choose() {
    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
    guard panel.runModal() == .OK, let root = panel.url else { return }
    location = root.path; vm.busy = true; vm.cancellation = Cancellation()
    let token = vm.cancellation; let excluded = vm.exclusions
    vm.status = vm.t("Ищем проекты…", "Finding projects…")
    vm.task = Task {
      result = await Task.detached {
        ProjectDiscovery.discover(root, exclusions: excluded, cancellation: token) { count in
          Task { @MainActor in guard vm.busy, vm.cancellation === token else { return }; vm.status = vm.t("Проверено объектов: ", "Entries inspected: ") + String(count) }
        }
      }.value
      vm.busy = false; vm.status = vm.t("Поиск проектов завершён", "Project search finished")
    }
  }
}
