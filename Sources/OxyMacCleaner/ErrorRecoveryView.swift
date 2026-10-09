import CleanerCore
import SwiftUI

struct ErrorRecoveryView: View {
  @EnvironmentObject var vm: AppModel
  let raw: String
  @State private var copied = false
  private var guidance: RecoveryGuidance { RecoveryGuidance(raw, russian: vm.t("ru", "en") == "ru") }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label(vm.t("Проверьте результат операции", "Review the operation result"), systemImage: "exclamationmark.circle")
        .font(.title2.bold()).accessibilityAddTraits(.isHeader)
      Text(guidance.summary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      DisclosureGroup(vm.t("Технические подробности", "Technical details")) {
        ScrollView { Text(raw).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 200)
        Button(copied ? vm.t("Скопировано", "Copied") : vm.t("Скопировать подробности", "Copy details")) {
          NSPasteboard.general.clearContents(); NSPasteboard.general.setString(raw, forType: .string); copied = true
        }.help(vm.t("Копирует технический текст локально в буфер обмена. Никуда не отправляет.", "Copies technical text to your local clipboard. Sends nothing."))
      }
      HStack {
        if let destination = guidance.destination {
          Button(label(destination)) { vm.error = nil; vm.page = destination.rawValue }
            .disabled(vm.busy).help(vm.t("Открывает раздел. Не повторяет операцию и не меняет разрешения.", "Opens the section. Does not retry the operation or change permissions."))
        }
        Spacer()
        Button(vm.t("Закрыть", "Close")) { vm.error = nil }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 540).onExitCommand { vm.error = nil }
  }
  private func label(_ destination: RecoveryGuidance.Destination) -> String {
    switch destination {
    case .settings: vm.t("Открыть настройки", "Open settings")
    case .engine: vm.t("Открыть локальный движок", "Open local engine")
    case .agents: vm.t("Вернуться к историям", "Return to histories")
    case .history: vm.t("Открыть историю операций", "Open operation history")
    }
  }
}
