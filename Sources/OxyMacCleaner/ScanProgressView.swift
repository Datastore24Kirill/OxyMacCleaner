import CleanerCore
import SwiftUI

struct ScanProgressView: View {
  @EnvironmentObject var vm: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let progress: ScanProgress
  let active: Bool
  @State private var showCategories = false
  private var ranked: [(key: String, value: Int64)] {
    progress.categories.filter { $0.value > 0 }.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }
  }
  private var segments: [(key: String, value: Int64)] {
    let largest = Array(ranked.prefix(5))
    let remaining = ranked.dropFirst(5).reduce(Int64(0)) { $0 + $1.value }
    return remaining > 0 ? largest + [(key: "remaining", value: remaining)] : largest
  }
  private func label(_ key: String) -> String {
    guard let kind = FileCategory(rawValue: key) else { return vm.t("Остальное", "Remaining") }
    return vm.t(kind.russian, kind.english)
  }
  private func color(_ key: String) -> Color {
    guard let kind = FileCategory(rawValue: key),
      let index = FileCategory.allCases.firstIndex(of: kind)
    else { return .gray }
    let palette: [Color] = [
      .cyan, .purple, .mint, .indigo, .pink, .teal, .brown, .green, .blue, .orange, .yellow, .red,
      .purple, .gray, .secondary,
    ]
    return palette[index]
  }
  private var title: String {
    switch progress.phase {
    case .enumerating: return vm.t("Исследуем диск", "Exploring your disk")
    case .sorting: return vm.t("Готовим результаты", "Preparing results")
    case .finished: return vm.t("Сканирование завершено", "Scan complete")
    case .cancelled: return vm.t("Сканирование остановлено", "Scan stopped")
    }
  }
  private func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
  var body: some View {
    HStack(spacing: 24) {
      TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active || reduceMotion)) {
        timeline in
        ZStack {
          Circle().stroke(.teal.opacity(0.12), lineWidth: 16)
          ForEach(0..<3) { index in
            Circle().stroke(.cyan.opacity(0.12), lineWidth: 1)
              .padding(CGFloat(index * 15))
          }
          if active {
            Circle().trim(from: 0, to: 0.22)
              .stroke(
                AngularGradient(colors: [.clear, .cyan, .mint], center: .center),
                style: StrokeStyle(lineWidth: 5, lineCap: .round)
              )
              .rotationEffect(
                .degrees(
                  reduceMotion
                    ? -90
                    : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(
                      dividingBy: 3) * 120))
          }
          Image(
            systemName: active
              ? "internaldrive.fill" : progress.phase == .cancelled ? "pause.fill" : "checkmark"
          )
          .font(.system(size: 32, weight: .medium)).foregroundStyle(.teal)
        }.frame(width: 112, height: 112)
      }.accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(title).font(.title3.bold())
          Spacer()
          Text(
            "\(Int(progress.elapsed)) s · \(Int(Double(progress.files) / max(1, progress.elapsed))) "
              + vm.t("файл/с", "files/s")
          )
          .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        HStack(spacing: 24) {
          metric("\(progress.files.formatted())", vm.t("файлов проверено", "files scanned"))
          metric(size(progress.bytes), vm.t("объём файлов", "file size"))
          metric("\(progress.directories.formatted())", vm.t("папок пройдено", "folders visited"))
          if progress.issues > 0 { metric("\(progress.issues)", vm.t("пропусков", "skipped")) }
        }
        GeometryReader { geometry in
          HStack(spacing: 0) {
            ForEach(segments, id: \.key) { item in
              color(item.key).frame(
                width: geometry.size.width * Double(item.value) / Double(max(1, progress.bytes))
              )
              .help(label(item.key) + " · " + size(item.value))
            }
          }.clipShape(Capsule())
        }.frame(height: 8).background(.quaternary, in: Capsule())
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading,
          spacing: 6
        ) {
          ForEach(segments, id: \.key) { item in
            HStack(spacing: 5) {
              Circle().fill(color(item.key)).frame(width: 6, height: 6)
              Text(label(item.key)).lineLimit(1)
              Text(size(item.value)).foregroundStyle(.secondary)
            }.help(label(item.key))
          }
        }.font(.system(size: 10))
        Button(vm.t("Все категории", "All categories")) { showCategories = true }.oxyHelp(
          .categories
        )
        .buttonStyle(.link).font(.caption)
        .popover(isPresented: $showCategories) {
          VStack(alignment: .leading, spacing: 12) {
            Text(vm.t("Состав найденных файлов", "Scanned file breakdown")).font(.headline)
            ScrollView {
              ForEach(ranked, id: \.key) { item in
                HStack {
                  Circle().fill(color(item.key)).frame(width: 8, height: 8)
                  Text(label(item.key))
                  Spacer()
                  Text(size(item.value)).monospacedDigit()
                  Text(
                    String(
                      format: "%.1f%%", Double(item.value) * 100 / Double(max(1, progress.bytes)))
                  )
                  .foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
                  Button(vm.t("Файлы", "Files")) {
                    vm.categoryFilter = item.key
                    vm.search = ""
                    vm.page = "files"
                    showCategories = false
                  }.oxyHelp(.categoryFiles).disabled(active)
                }.padding(.vertical, 4)
              }
            }.frame(maxHeight: 360)
            Text(
              vm.t(
                "Классификация по пути и типу файла. Игры определяются по известным папкам. Категория не означает, что файл можно безопасно удалить.",
                "Classification uses paths and file types. Games use known library locations. Categories do not imply that files are safe to delete."
              )
            )
            .font(.caption).foregroundStyle(.secondary)
          }.padding(20).frame(width: 540)
        }
        Text(
          active
            ? progress.currentPath
            : vm.t(
              "Результаты доступны ниже. Файлы не изменены.",
              "Results are available below. Files are unchanged.")
        )
        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        .help(progress.currentPath)
        if active {
          Text(
            vm.t(
              "Обход файлов · общий объём работы станет известен после обхода. Полоса показывает состав найденного объёма.",
              "Enumerating files · total work is not yet known. The bar shows the scanned size breakdown."
            )
          )
          .font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
    }.padding(22)
      .background(
        LinearGradient(
          colors: [.teal.opacity(0.09), .blue.opacity(0.04)], startPoint: .topLeading,
          endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20)
      )
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(.teal.opacity(0.18)))
  }
  private func metric(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.title3.bold().monospacedDigit())
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
  }
}
