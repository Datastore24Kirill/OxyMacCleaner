import CleanerCore
import SwiftUI

struct ContextCoverageView: View {
  let facts: [ContextFact]
  let output: String
  @EnvironmentObject var vm: AppModel
  @State private var rows: [ContextCoverage.Row] = []
  @State private var loading = false
  private struct Request: Hashable { let output: String; let facts: [ContextFact] }
  var body: some View {
    DisclosureGroup(vm.t("Сохранность формулировок по категориям", "Wording retention by category")) {
      Text(vm.t("Сравниваем текущий текст с проверяемым черновиком, не со всей историей. Ссылка и дословная формулировка считаются отдельно: ни одно совпадение не доказывает сохранение смысла или актуальность решения.", "Compares the current text with the reviewable draft, not the entire history. References and verbatim wording are counted separately; neither proves meaning or currency.")).font(.caption).foregroundStyle(.secondary)
      if loading { ProgressView() }
      ForEach(rows) { row in
        HStack {
          Text(row.category.title(russian: vm.language != "en"))
          Spacer()
          Text(vm.t("Ссылки: ", "References: ") + "\(row.referenced)/\(row.total) · " + vm.t("Дословно: ", "Verbatim: ") + "\(row.verbatim)/\(row.total)").monospacedDigit()
        }.font(.caption)
      }
      Text(vm.t("Если формулировка изменена, сверьте её с исходником кнопкой ниже. Перефразирование тоже считается изменением.", "Use Compare with source below to review changed wording. Paraphrasing also counts as a change.")).font(.caption)
    }.task(id: Request(output: output, facts: facts)) {
      let token = Cancellation(), source = facts, text = output
      loading = true; rows = []
      do {
        try await Task.sleep(for: .milliseconds(250))
        let result = try await withTaskCancellationHandler {
          try await Task.detached { try ContextCoverage.compare(facts: source, output: text, cancellation: token) }.value
        } onCancel: { token.cancel() }
        try Task.checkCancellation(); rows = result; loading = false
      } catch { if !Task.isCancelled { loading = false } }
    }
  }
}
