import CleanerCore
import SwiftUI

/// Selection is limited to the displayed filter. Destructive actions remain separate.
struct SelectionControls: View {
  @EnvironmentObject var vm: AppModel
  let count: Int
  let bytes: Int64?
  let canSelect: Bool
  let select: () -> Void
  let clear: () -> Void
  var shownOnly = false
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack { buttons; Spacer(); summary }
      VStack(alignment: .leading) { buttons; summary }
    }.disabled(vm.busy)
  }
  private var buttons: some View {
    HStack {
      Button(shownOnly ? vm.t("Выбрать показанные", "Select shown") : vm.t("Выбрать по фильтру", "Select matching"), action: select)
        .disabled(!canSelect)
        .help(shownOnly ? vm.t("Выбирает только показанные в списке доступные объекты. Ничего не удаляет.", "Selects only eligible items currently shown in the list. Deletes nothing.") : vm.t("Заменяет выбор доступными объектами текущего фильтра, включая другие страницы. Ничего не удаляет.", "Replaces selection with eligible items matching the filter, including other pages. Deletes nothing."))
      Button(vm.t("Снять выбор", "Clear selection"), action: clear).disabled(count == 0)
    }
  }
  private var summary: some View {
    Text(vm.t("Выбрано: ", "Selected: ") + "\(count) · " + (bytes.map {
      ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
    } ?? vm.t("размер не измерен", "size not measured")))
      .font(.callout).monospacedDigit().accessibilityElement(children: .combine)
  }
}

extension AppModel {
  func fileSelectable(_ file: FileRecord) -> Bool {
    !QuarantineStore.protected(file.path) && file.links == 1
      && !Scanner.inside(file.path, quarantine.root.path)
      && !exclusions.contains { Scanner.inside(file.path, $0) }
  }
  func copyPath(_ path: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
  }
}

struct FileActions: View {
  @EnvironmentObject var vm: AppModel
  let path: String
  var file: FileRecord? = nil
  var body: some View {
    Button(vm.t("Показать в Finder", "Show in Finder")) { vm.reveal(path) }
    Button(vm.t("Копировать путь", "Copy path")) { vm.copyPath(path) }
    if let file, vm.fileSelectable(file) {
      Button(vm.t("В карантин…", "Quarantine…")) { vm.quarantineSelected(paths: [path]) }
        .disabled(vm.busy)
    }
    Button(vm.t("Защитить / исключить", "Protect / exclude")) { vm.protect(path) }
      .disabled(vm.busy)
  }
}
