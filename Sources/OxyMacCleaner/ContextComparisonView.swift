import CleanerCore
import SwiftUI

struct ContextComparisonView: View {
  @EnvironmentObject var vm: AppModel
  @State private var showing = false
  @State private var source = ""
  @State private var loading = false
  var body: some View {
    Button(vm.t("Сравнить с исходником", "Compare with source")) {
      guard let transcript = vm.transcript else { return }
      loading = true
      Task {
        do { source = try await Task.detached { try transcript.preview() }.value; showing = true }
        catch { vm.error = error.localizedDescription }
        loading = false
      }
    }.disabled(vm.busy || loading)
      .help(vm.t("Показывает исходные строки и результат рядом. Для больших историй загружается только начало, без изменения оригинала.", "Shows source lines and output side by side. Only the start of large histories is loaded; originals are unchanged."))
      .sheet(isPresented: $showing) {
        VStack(alignment: .leading, spacing: 12) {
          Text(vm.t("Проверка перед переносом", "Review before transfer")).font(.title2.bold())
          Text(vm.t("Исходник: первые 50 000 символов. Ссылки [L…] указывают на строки; для JSON — на нормализованные записи. Сверьте последние требования, запреты и результаты тестов. Выжимка не разрешает противоречия автоматически.", "Source: first 50,000 characters. [L…] identifies source lines, or normalized records for JSON. Check the latest requirements, prohibitions and test results. Excerpts do not resolve conflicts automatically.")).font(.caption)
          HStack(alignment: .top) {
            pane(vm.t("Исходник", "Source"), text: source)
            pane(vm.t("Результат", "Result"), text: vm.output)
          }
          Text(vm.t("Результат: ", "Result: ") + "\(vm.output.count)" + vm.t(" символов", " characters"))
          Button(vm.t("Закрыть", "Close")) { showing = false }.keyboardShortcut(.cancelAction)
        }.padding(20).frame(width: 900, height: 640)
      }
  }
  private func pane(_ title: String, text: String) -> some View {
    VStack(alignment: .leading) {
      Text(title).font(.headline)
      ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        .accessibilityLabel(title)
    }.frame(maxWidth: .infinity)
  }
}
