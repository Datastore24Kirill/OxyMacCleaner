import SwiftUI

struct HomeShortcuts: View {
  @EnvironmentObject var vm: AppModel
  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
      tile("sparkles", vm.t("Найти возможности очистки", "Find cleanup opportunities"), vm.t("Посмотреть рекомендации", "Review recommendations"), "advisor")
      tile("doc.fill", vm.t("Разобрать крупные файлы", "Review large files"), vm.t("Выбрать только ненужное", "Choose only what you don't need"), "files")
      tile("hammer.fill", vm.t("Очистить данные разработки", "Clean development data"), vm.t("Архивы, кэши и симуляторы", "Archives, caches and simulators"), "developer")
      tile("arrow.uturn.backward", vm.t("Восстановить файлы", "Restore files"), vm.t("Посмотреть карантин", "Review quarantine"), "quarantine")
    }
  }
  private func tile(_ icon: String, _ title: String, _ subtitle: String, _ page: String) -> some View {
    Button { vm.page = page } label: {
      HStack(spacing: 14) {
        Image(systemName: icon).font(.title2).foregroundStyle(.teal).frame(width: 42)
        VStack(alignment: .leading, spacing: 5) {
          Text(title).font(.headline)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
      }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
    }.buttonStyle(.plain)
  }
}
