import CleanerCore
import SwiftUI

struct DiskMapView: View {
  @EnvironmentObject var vm: AppModel
  @State private var files: [String: FileRecord] = [:]
  @State private var limit = 200
  private var nodes: [DiskNode] { vm.diskIndex.children[vm.mapPath] ?? [] }
  private var shown: [DiskNode] {
    let top = Array(nodes.filter { $0.bytes > 0 }.prefix(24))
    let rest = nodes.filter { $0.bytes > 0 }.dropFirst(24).reduce(Int64(0)) { $0 + $1.bytes }
    return rest > 0 ? top + [DiskNode(path: "remaining", bytes: rest, directory: false)] : top
  }
  private func size(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Button {
          vm.mapPath = URL(fileURLWithPath: vm.mapPath).deletingLastPathComponent().path
        } label: {
          Label(vm.t("Выше", "Up"), systemImage: "arrow.up")
        }.oxyHelp(.up)
          .disabled(vm.roots.contains { $0.path == vm.mapPath } || vm.busy)
        Menu(vm.t("Корень", "Root")) {
          ForEach(vm.roots, id: \.path) { root in
            Button(root.path) { vm.mapPath = root.path }.oxyHelp(.mapRoot)
          }
        }.oxyHelp(.mapRoot).fixedSize()
        Text(vm.mapPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        Spacer()
        Text(size(nodes.reduce(0) { $0 + $1.bytes })).monospacedDigit()
      }
      if nodes.isEmpty {
        ContentUnavailableView(
          vm.t("Нет данных карты", "No map data"), systemImage: "square.grid.3x3",
          description: Text(
            vm.t(
              "Завершите сканирование или выберите другой корень.",
              "Finish a scan or select another root.")))
      } else {
        GeometryReader { geometry in
          let tiles = DiskLayout.tiles(
            weights: shown.map(\.bytes), width: geometry.size.width, height: geometry.size.height)
          ZStack(alignment: .topLeading) {
            ForEach(tiles, id: \.index) { tile in
              let node = shown[tile.index]
              mapTile(node: node, tile: tile)
            }
          }
        }.frame(minHeight: 180, idealHeight: 250, maxHeight: 320)
        List(nodes.prefix(limit)) { node in
          HStack {
            Button {
              if node.directory { vm.mapPath = node.path } else { vm.reveal(node.path) }
            } label: {
              Label(node.name, systemImage: node.directory ? "folder" : "doc")
            }.oxyHelp(.mapNode).buttonStyle(.plain)
            Spacer()
            Text(size(node.bytes)).monospacedDigit()
            Button {
              vm.reveal(node.path)
            } label: {
              Image(systemName: "arrow.up.right.square")
            }.oxyHelp(.finder).buttonStyle(.borderless)
            Menu(vm.t("Действия", "Actions")) {
              if node.directory {
                Button(vm.t("Открыть папку на карте", "Explore folder")) { vm.mapPath = node.path }
                Button(vm.t("В карантин…", "Quarantine…")) { vm.quarantineDirectory(node.path) }.disabled(vm.busy)
              }
              FileActions(path: node.path, file: files[node.path])
            }.fixedSize()
          }.contextMenu {
            if node.directory {
              Button(vm.t("Переместить папку в карантин…", "Quarantine folder…")) {
                vm.quarantineDirectory(node.path)
              }.oxyHelp(.quarantine).disabled(vm.busy)
            }
            FileActions(path: node.path, file: files[node.path])
          }
        }
        if nodes.count > limit { Button(vm.t("Показать ещё 200", "Show 200 more")) { limit += 200 } }
        Text(
          vm.t(
            "Площадь — логический размер файлов. Нажмите папку, чтобы открыть её. Карта не показывает гарантированно освобождаемое место. Список загружается порциями по 200 объектов.",
            "Area represents logical file size. Click a folder to explore. This is not guaranteed reclaimable space. List loads 200 items at a time."
          )
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }.task(id: vm.reportRevision) {
      let source = vm.report.files
      let lookup = await Task.detached { Dictionary(source.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first }) }.value
      guard !Task.isCancelled else { return }
      files = lookup
    }.onChange(of: vm.mapPath) { _, _ in limit = 200 }
  }

  private func tileHelp(_ node: DiskNode) -> String {
    if node.path == "remaining" {
      return vm.t(
        "Остальные объекты перечислены в списке под картой.",
        "Remaining items are listed below the map.")
    }
    return node.path + " · " + size(node.bytes) + "\n"
      + vm.t(
        node.directory ? "Открыть состав папки в карте." : "Показать файл в Finder.",
        node.directory ? "Explore this folder in the map." : "Reveal this file in Finder.")
  }
  private func mapTile(node: DiskNode, tile: DiskLayout.Tile) -> some View {
    Button {
      if node.directory {
        vm.mapPath = node.path
      } else if node.path != "remaining" {
        vm.reveal(node.path)
      }
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        if tile.width > 65 && tile.height > 40 {
          Text(
            node.path == "remaining"
              ? vm.t("Остальное · см. список", "Remaining · see list") : node.name
          ).font(.caption.bold()).lineLimit(2)
          Text(size(node.bytes)).font(.caption2).lineLimit(1)
        }
      }.padding(tile.width > 40 ? 8 : 0).frame(
        width: max(0, tile.width - 3), height: max(0, tile.height - 3),
        alignment: .topLeading
      )
      .background(
        Color(hue: Double(tile.index % 12) / 12, saturation: 0.5, brightness: 0.55),
        in: RoundedRectangle(cornerRadius: 6)
      )
      .foregroundStyle(.white).clipped()
    }.buttonStyle(.plain).offset(x: tile.x, y: tile.y)
      .help(tileHelp(node)).accessibilityHint(tileHelp(node))
      .accessibilityLabel(
        (node.path == "remaining"
          ? vm.t("Остальные объекты", "Remaining items") : node.name) + " "
          + size(node.bytes))
  }
}
