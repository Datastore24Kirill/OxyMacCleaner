import CleanerCore
import SwiftUI

struct QuarantineInspectionView: View {
  @EnvironmentObject var vm: AppModel
  let entry: QuarantineEntry
  @State private var result: QuarantineStore.Inspection?
  @State private var loading = false
  @State private var showing = false
  @State private var token = Cancellation()
  var body: some View {
    Button(vm.t("Проверить копии…", "Inspect copies…")) {
      loading = true; showing = true; result = nil; token = Cancellation()
      let cancellation = token; let store = vm.quarantine
      Task { let value = await Task.detached { store.inspect(entry, cancellation: cancellation) }.value; if !cancellation.cancelled { result = value }; loading = false }
    }.accessibilityLabel(vm.t("Проверить копии: ", "Inspect copies: ") + URL(fileURLWithPath: entry.original).lastPathComponent).disabled(vm.busy || loading)
      .help(vm.t("Проверяет контрольные суммы и показывает расположение обеих копий. Не удаляет данные.", "Verifies checksums and shows both copy locations. Deletes nothing."))
      .sheet(isPresented: $showing, onDismiss: { token.cancel() }) {
        VStack(alignment: .leading, spacing: 14) {
          Text(vm.t("Состояние восстановления", "Recovery status")).font(.title2.bold())
          if loading { ProgressView(vm.t("Проверяем контрольные суммы…", "Verifying checksums…")) }
          if let result {
            Text(result.payloadValid ? vm.t("Копия карантина проверена", "Quarantine copy verified") : vm.t("Копия карантина недоступна или изменилась. Подключите исходный диск и повторите проверку. Удаление не предлагается.", "Quarantine copy is unavailable or changed. Connect its disk and check again. Deletion is not offered."))
            path(result.payload)
            if let destination = result.destination {
              Text(result.destinationValid ? vm.t("Восстановленная копия проверена", "Restored copy verified") : vm.t("Назначение не подтверждено. Не удаляйте оставшиеся копии.", "Destination not verified. Keep remaining copies."))
              path(destination)
            }
            if let previous = result.previous {
              Text(vm.t("После переноса осталась прежняя копия. Она не удаляется автоматически; проверьте её отдельно.", "A previous copy remains after relocation. It is not deleted automatically; inspect it separately."))
              path(previous)
            }
            if entry.state == "restored-copy", result.payloadValid, result.destinationValid {
              Button(vm.t("Убрать лишнюю копию в Корзину…", "Move redundant copy to Trash…")) {
                guard vm.confirm(vm.t("Убрать копию карантина?", "Remove quarantine copy?"), vm.t("Восстановленный файл останется. Обе копии будут проверены повторно. Копию карантина можно вернуть из Корзины.", "The restored file stays. Both copies will be rechecked. The quarantine copy can be recovered from Trash.")) else { return }
                vm.busy = true; let store = vm.quarantine
                Task {
                  do { try await Task.detached { try store.trashRestoredCopy(entry) }.value }
                  catch { vm.error = error.localizedDescription }
                  vm.entries = store.entries(); vm.busy = false; showing = false
                }
              }.disabled(vm.busy)
            }
          }
          Button(vm.t("Закрыть", "Close")) { showing = false }.keyboardShortcut(.cancelAction).disabled(vm.busy)
        }.padding(20).frame(width: 680)
      }
  }
  private func path(_ value: String) -> some View {
    HStack { Text(value).font(.caption).textSelection(.enabled); Spacer(); Button(vm.t("В Finder", "Reveal")) { vm.reveal(value) } }
  }
}
