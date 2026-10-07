import CleanerCore
import SwiftUI

struct UpdateBackupsView: View {
  @EnvironmentObject var vm: AppModel
  @EnvironmentObject var updater: AppUpdater
  @State private var entries: [UpdateBackup] = []
  @State private var loading = false
  @State private var expanded = false
  @State private var status = ""
  var body: some View {
    VStack(alignment: .leading) {
      Button(vm.t(expanded ? "Скрыть копии обновлений" : "Старые копии обновлений…", expanded ? "Hide update copies" : "Previous update copies…")) { expanded.toggle() }
        .help(vm.t("Показывает завершённые резервные версии приложения. Последняя защищена от удаления.", "Shows completed app backups. The newest rollback copy is protected."))
      if expanded {
      VStack(alignment: .leading, spacing: 10) {
        Button(vm.t("Проверить копии", "Find update copies")) { refresh() }.disabled(loading || vm.busy || updater.busy)
        Text(vm.t("Последняя копия для отката защищена. Остальные можно отправить в Корзину — место освободится после её очистки. Незавершённые и неизвестные папки не выбираются.", "The latest rollback copy is protected. Older copies can go to Trash; space is freed when Trash is emptied. Incomplete and unknown folders are excluded.")).font(.caption)
        Text(status).font(.caption)
        ForEach(entries) { entry in
          HStack {
            Text(entry.version + " · " + ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file))
            Spacer()
            if entry.protected { Text(vm.t("Последняя копия", "Latest rollback copy")) }
            else {
              Button(vm.t("В Корзину…", "Move to Trash…")) {
                guard vm.confirm(vm.t("Убрать старую копию?", "Remove older copy?"), entry.url.path + "\n" + vm.t("Можно восстановить из Корзины.", "You can restore it from Trash.")) else { return }
                loading = true
                Task {
                  do { try await Task.detached { try UpdateBackups.trash(entry, beside: Bundle.main.bundleURL) }.value }
                  catch { vm.error = error.localizedDescription }
                  loading = false; refresh()
                }
              }.disabled(loading || vm.busy || updater.busy)
            }
          }
        }
      }
      }
    }
  }
  private func refresh() {
    loading = true; status = vm.t("Проверяем копии…", "Checking copies…")
    Task {
      do { entries = try await Task.detached { try UpdateBackups.list(beside: Bundle.main.bundleURL) }.value; status = vm.t("Найдено: ", "Found: ") + "\(entries.count)" }
      catch { status = error.localizedDescription }
      loading = false
    }
  }
}
