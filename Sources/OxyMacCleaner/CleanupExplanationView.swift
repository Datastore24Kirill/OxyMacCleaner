import CleanerCore
import SwiftUI

struct CleanupExplanationView: View {
  @EnvironmentObject var vm: AppModel
  let section: String
  var body: some View {
    let info = CleanupExplanation.forSection(section, russian: vm.language != "en")
    DisclosureGroup(vm.t("Владелец, последствия и восстановление", "Owner, consequences and recovery")) {
      VStack(alignment: .leading, spacing: 6) {
        Text(vm.t("Владелец: ", "Owner: ") + info.owner)
        Text(vm.t("Последствия: ", "Consequences: ") + info.consequence)
        Text(vm.t("Восстановление: ", "Recovery: ") + info.recovery)
      }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }.help(vm.t("Поясняет действие. Не выбирает файлы и не подтверждает возможность удаления.", "Explains the action. Does not select files or confirm deletion eligibility."))
  }
}
