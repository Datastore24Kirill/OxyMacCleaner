import CleanerCore
import SwiftUI

struct ScanProgressView: View {
  @EnvironmentObject var vm: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let progress: ScanProgress
  let active: Bool
  private let kinds = ["DerivedData", "Xcode Archive", "Build", "Archive", "File"]
  private let colors: [Color] = [.cyan, .purple, .mint, .orange, .blue]
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
            ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
              colors[index].frame(
                width: geometry.size.width * Double(progress.categories[kind, default: 0])
                  / Double(max(1, progress.bytes)))
            }
          }.clipShape(Capsule())
        }.frame(height: 7).background(.quaternary, in: Capsule())
        HStack(spacing: 12) {
          ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
            HStack(spacing: 4) {
              Circle().fill(colors[index]).frame(width: 5, height: 5)
              Text(kind == "File" ? vm.t("Другие", "Other") : kind)
            }
          }
        }.font(.system(size: 10)).foregroundStyle(.secondary)
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
