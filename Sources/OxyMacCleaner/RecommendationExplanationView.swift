import CleanerCore
import SwiftUI

struct RecommendationExplanationView: View {
  @EnvironmentObject var vm: AppModel
  @Environment(\.dismiss) private var dismiss
  let item: SmartRecommendation
  @State private var selected: [RecommendationExplanation.Fact] = []
  @State private var running = false
  @State private var failure: String?
  @State private var task: Task<Void, Never>?
  @State private var generation = UUID()
  private var explanation: RecommendationExplanation { .init(item, russian: vm.language != "en") }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(vm.t("Понятно об этой рекомендации", "Understand this recommendation")).font(.title2.bold())
      Text(item.title).font(.headline)
      Text(vm.t("Модель работает локально и выбирает важные факты. Она не решает, что удалять. Полный список ограничений остаётся ниже.", "The local model highlights relevant facts. It does not decide what to delete. All constraints remain below.")).font(.caption)
      HStack {
        Button(vm.t("Выделить главное локальной моделью", "Highlight with local model")) { explain() }.disabled(running || vm.model.isEmpty)
        if running { ProgressView().controlSize(.small); Button(vm.t("Отмена", "Cancel")) { generation = UUID(); task?.cancel(); running = false } }
      }
      if vm.model.isEmpty {
        Text(vm.t("Выберите установленную модель в разделе «Локальный движок». Проверенные факты доступны без модели.", "Select an installed model in Local Engine. Verified facts are available without a model.")).font(.caption).foregroundStyle(.secondary)
      }
      if let failure { Text(failure).font(.caption).foregroundStyle(.orange) }
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if !selected.isEmpty {
            Text(vm.t("Модель выделила", "Model highlights")).bold()
            ForEach(selected) { Text($0.text) }
            Divider()
          }
          Text(vm.t("Все проверенные факты и ограничения", "All verified facts and constraints")).bold()
          ForEach(explanation.facts) { Text($0.text) }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
      }
      Button(vm.t("Закрыть", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
    }.padding(24).frame(width: 650, height: 560)
      .onDisappear { generation = UUID(); task?.cancel() }
  }
  private func explain() {
    let facts = explanation, model = vm.model, engine = vm.engine
    let token = UUID(); generation = token
    running = true; failure = nil; selected = []
    task = Task {
      do {
        let response = try await engine.generate(facts.prompt, model: model,
          system: RecommendationExplanation.system, schema: RecommendationExplanation.schema)
        try Task.checkCancellation()
        let result = try facts.selected(response)
        guard generation == token else { return }
        selected = result; running = false
      } catch {
        guard generation == token else { return }
        running = false
        if !(error is CancellationError) { failure = vm.t("Модель недоступна или ответ не прошёл проверку. Используйте факты ниже. ", "Model unavailable or response rejected. Use the facts below. ") + error.localizedDescription }
      }
    }
  }
}
