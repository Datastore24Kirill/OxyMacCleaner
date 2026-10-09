import CleanerCore
import SwiftUI

struct SpaceEstimateView: View {
  @EnvironmentObject var vm: AppModel
  var body: some View {
    let value = SpaceEstimate(files: vm.report.files.filter { vm.selected.contains($0.path) })
    VStack(alignment: .leading, spacing: 4) {
      Text(summary(value)).font(.caption)
      Text(vm.t("Фактическая экономия неизвестна: APFS-клоны, снимки и жёсткие ссылки могут удерживать блоки. Карантин на этом диске место не освобождает.", "Actual reclaimed space is unknown: APFS clones, snapshots and hard links may retain blocks. Quarantine on this disk does not free space.")).font(.caption).foregroundStyle(.secondary)
      if value.hardLinked > 0 { Text(vm.t("С жёсткими ссылками: ", "With hard links: ") + String(value.hardLinked)).font(.caption) }
    }.accessibilityElement(children: .combine)
  }
  private func summary(_ value: SpaceEstimate) -> String {
    let count = vm.t("Выбрано уникальных файлов: ", "Unique files selected: ") + String(value.count)
    let logical = vm.t("Размер: ", "Logical: ") + size(value.logical)
    let allocated = vm.t("Занятые блоки: ", "Allocated blocks: ") + size(value.allocated)
    return [count, logical, allocated].joined(separator: " · ")
  }
  private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
