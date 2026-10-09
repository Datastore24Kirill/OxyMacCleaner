import SwiftUI
import CleanerCore

struct ContextProgressView: View {
  @EnvironmentObject var vm: AppModel
  private var title: String {
    if vm.contextMethod != "semantic" { return vm.status }
    guard let stage = vm.contextStage else { return vm.t("Готовим резервную копию…", "Preparing backup…") }
    switch stage.kind {
    case .preparing: return vm.t("Читаем и подготавливаем историю…", "Reading and preparing history…")
    case .extracting: return vm.t("Сокращаем часть", "Summarizing part") + " \(stage.part)/\(stage.total)"
    case .verifying: return vm.t("Проверяем часть", "Reviewing part") + " \(stage.part)/\(stage.total)"
    case .finished: return vm.t("Готово к вашей проверке", "Ready for your review")
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        ProgressView().controlSize(.small)
        Text(title).font(.headline)
        Spacer()
        Button(vm.t("Остановить", "Stop")) { vm.cancel() }
      }
      if let fraction = vm.contextStage?.fraction { ProgressView(value: fraction) }
      if vm.contextStage?.retry == true {
        Text(vm.t("Ответ не прошёл проверку. Повтор этой части: 1 из 1.", "Response failed validation. Retrying this part: 1 of 1.")).font(.caption)
      }
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let elapsed = max(0, Int(context.date.timeIntervalSince(vm.contextStarted ?? context.date)))
        Text(vm.t("Прошло: ", "Elapsed: ") + "\(elapsed / 60):" + String(format: "%02d", elapsed % 60)).font(.caption.monospacedDigit())
      }
      Text(vm.t("Полоса считает завершённые части и их проверки, а не оставшееся время. Оригинал не изменяется. Обработка идёт на вашем Mac.", "Progress counts completed parts and reviews, not time remaining. The original is unchanged. Processing stays on your Mac.")).font(.caption).foregroundStyle(.secondary)
    }.padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
  }
}
struct ContextResultView: View {
  @EnvironmentObject var vm: AppModel
  @State private var evidenceLimit = 20
  @State private var reviewLimit = 20
  private var sourceBytes: Int { vm.contextAudit?.sourceBytes ?? Int(vm.transcript?.streaming?.bytes ?? Int64(vm.transcript?.text.utf8.count ?? 0)) }
  private var resultBytes: Int { vm.output.utf8.count }
  private func size(_ count: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(vm.t("Готово к переносу", "Ready to transfer"), systemImage: "text.badge.checkmark").font(.headline)
        Spacer()
        Text(size(sourceBytes) + " → " + size(resultBytes)).font(.headline.monospacedDigit())
      }
      if sourceBytes > 0 {
        let percent = Int((1 - Double(resultBytes) / Double(sourceBytes)) * 100)
        Text(percent >= 0 ? vm.t("Текущий текст короче на \(percent)%", "Current text is \(percent)% smaller") : vm.t("Текущий текст больше исходника на \(-percent)%", "Current text is \(-percent)% larger"))
        Text(vm.t("Сравниваем UTF-8 байты, не токены. Это сокращение текста для переноса, не освобождение диска.", "Comparison uses UTF-8 bytes, not tokens. This reduces transferred text, not disk usage.")).font(.caption).foregroundStyle(.secondary)
      }
      if let audit = vm.contextAudit {
        Text(vm.t("Черновик со ссылками: \(audit.facts.count). Реплики пользователя сохранены по порядку; сообщения агента подписаны отдельно.", "Cited draft: \(audit.facts.count) entries. User statements retain their order; agent reports are attributed separately.")).font(.callout)
        Text(vm.t("Перед переносом сверьте актуальность. Проверка той же моделью не гарантирует точность.", "Review currency before transfer. Review by the same model does not guarantee accuracy.")).font(.caption).foregroundStyle(.secondary)
        if vm.output != audit.text {
          Label(vm.t("Текст изменён после проверки. Замечания относятся к исходному черновику.", "Edited after review. Findings refer to the original draft."), systemImage: "pencil.circle").foregroundStyle(.orange)
        }
        DisclosureGroup(vm.t("Источники пересказа", "Summary evidence")) {
          ForEach(Array(audit.facts.prefix(evidenceLimit).enumerated()), id: \.offset) { _, fact in
            evidenceRow(fact)
          }
          if evidenceLimit < audit.facts.count { Button(vm.t("Ещё 20", "Next 20")) { evidenceLimit += 20 } }
        }
        Divider()
        Label(vm.t("Нужно проверить", "Needs review"),systemImage:"text.magnifyingglass").font(.headline)
        Text(vm.t("Фрагментов: \(audit.missing.count) · Контрольных строк без ссылки: \(audit.unrepresented.count)", "Fragments: \(audit.missing.count) · Unreferenced control lines: \(audit.unrepresented.count)")).font(.callout)
        Text(vm.t("Эти фрагменты не добавляются в копируемый текст автоматически. Это исходные записи, а не новые задачи модели.", "These fragments are not automatically included in the copied text. They are original evidence, not new model tasks.")).font(.caption).foregroundStyle(.secondary)
        if !audit.missing.isEmpty {
          DisclosureGroup(vm.t("Открыть фрагменты для сверки", "Open review fragments")) {
            ForEach(Array(audit.missing.prefix(reviewLimit).enumerated()),id: \.offset) { _, fact in evidenceRow(fact) }
            if reviewLimit < audit.missing.count { Button(vm.t("Ещё 20 фрагментов", "Next 20 fragments")) { reviewLimit += 20 } }
          }
        }
        if !audit.concerns.isEmpty {
          DisclosureGroup(vm.t("Дополнительные замечания", "Additional findings")) {
            ForEach(Array(audit.concerns.enumerated()),id: \.offset) { _, text in Text(text).font(.caption).textSelection(.enabled) }
          }
        }

      }
      if let path = vm.contextBackup {
        Button(vm.t("Показать резервную копию", "Show backup")) { vm.reveal(path) }
      }
      ContextComparisonView()
    }.padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
  }
  private func evidenceRow(_ fact: ContextFact) -> some View {
    VStack(alignment:.leading,spacing:5) {
      Text(fact.text).font(.callout).lineLimit(3)
      DisclosureGroup(vm.t("Полный фрагмент", "Full evidence")) {
        Text(fact.quote).font(.caption).textSelection(.enabled)
      }
      ContextComparisonView(reference:fact.line)
    }.padding(.vertical,6)
  }

}
