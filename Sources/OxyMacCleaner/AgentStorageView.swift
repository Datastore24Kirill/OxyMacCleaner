import CleanerCore
import SwiftUI

struct AgentStorageView: View {
  @EnvironmentObject var vm: AppModel
  @State private var totals: [AgentDataKind: Int64] = [:]
  @State private var counts: [AgentDataKind: Int] = [:]
  @State private var loading = false
  private struct Request: Hashable { let revision: Int; let agent: String }
  var body: some View {
    GroupBox(vm.t("Что занимает место у агента", "Agent storage breakdown")) {
      VStack(alignment: .leading, spacing: 10) {
        Text(vm.t("Размеры из последнего снимка. Категория определена по расположению и формату, а не по содержимому. Неполный обход может пропустить данные.", "Sizes come from the latest snapshot. Categories are inferred from paths and formats, not contents. Partial scans may omit data.")).font(.caption).foregroundStyle(.secondary)
        if loading {
          ProgressView(vm.t("Считаем размеры по сохранённому снимку…", "Calculating sizes from the saved snapshot…"))
        } else {
          ForEach(AgentDataKind.allCases, id: \.self) { kind in
            HStack {
              Text(kind.title(russian: vm.language != "en"))
              Spacer()
              Text("\(counts[kind, default: 0]) · " + ByteCountFormatter.string(fromByteCount: totals[kind, default: 0], countStyle: .file)).monospacedDigit()
            }
          }
        }
        Text(vm.t("Оптимизация создаёт отдельный пересказ выбранной истории. Истории, рабочие базы и кэши здесь не удаляются: для удаления нужна отдельная проверка объекта. Папка с названием cache сама по себе не доказывает безопасность.", "Optimization creates a separate summary of the selected history. Histories, working databases and caches are not deleted here: removal requires a separate object check. A folder named cache alone does not prove safety.")).font(.caption)
        if vm.snapshotDate == nil { Text(vm.t("Для оценки размеров выполните сканирование.", "Run a scan to measure sizes.")).foregroundStyle(.secondary) }
      }.padding(8)
    }.task(id: Request(revision: vm.reportRevision, agent: vm.agent)) {
      let files = vm.report.files
      let roots = Agents.catalog.first { $0.id == vm.agent }?.relativePaths.map { vm.home.appendingPathComponent($0).path } ?? []
      let token = Cancellation(); loading = true; totals = [:]; counts = [:]
      do {
        let result = try await withTaskCancellationHandler {
          try await Task.detached { () throws -> ([AgentDataKind: Int64], [AgentDataKind: Int]) in
            var sizes: [AgentDataKind: Int64] = [:], counts: [AgentDataKind: Int] = [:]
            for (index, file) in files.enumerated() {
              if index % 256 == 0 { try token.check() }
              guard let root = roots.first(where: { Scanner.inside(file.path, $0) }) else { continue }
              let kind = AgentDataKind.classify(file.path, root: root)
              sizes[kind, default: 0] += file.bytes; counts[kind, default: 0] += 1
            }
            return (sizes, counts)
          }.value
        } onCancel: { token.cancel() }
        try Task.checkCancellation()
        totals = result.0; counts = result.1; loading = false
      } catch { if !Task.isCancelled { loading = false } }
    }
  }
}
