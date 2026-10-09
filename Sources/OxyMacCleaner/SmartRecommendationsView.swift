import CleanerCore
import SwiftUI

struct SmartRecommendationsView: View {
  @EnvironmentObject var vm: AppModel
  @State private var catalog: [SmartRecommendation] = []
  @State private var selected = Set<String>()
  @State private var query = ""
  @State private var limit = 50
  @State private var previewing = false
  private func size(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
  private func title(_ group: SmartRecommendation.Group) -> String {
    switch group {
    case .regenerable: return vm.t("Восстанавливаемые данные разработки", "Regenerable development data")
    case .review: return vm.t("Личные и ценные данные — просмотрите", "Personal and valuable data — review")
    case .blocked: return vm.t("Защищено или требует проверки", "Protected or needs inspection")
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(vm.t("Общий план просмотра", "Combined review plan")).font(.headline)
      Text(vm.t("Сначала меньший риск и полные доказательства, затем размер и стоимость восстановления. Объекты не выбираются автоматически. Активность повторно проверяется перед действием.", "Lower risk and complete evidence first, then size and recovery cost. Nothing is automatically selected. Activity is checked again before acting.")).font(.caption).foregroundStyle(.secondary)
      TextField(vm.t("Найти рекомендацию", "Find recommendation"), text: $query).textFieldStyle(.roundedBorder)
      HStack {
        Text(vm.t("Выбрано: ", "Selected: ") + "\(selected.count)")
        Button(vm.t("Снять выбор", "Clear selection")) { selected = [] }.disabled(selected.isEmpty)
        Button(vm.t("Общий предпросмотр…", "Combined preview…")) { previewing = true }
          .disabled(selected.isEmpty || vm.busy)
      }
      let matching = catalog.filter { query.isEmpty || ($0.title + ($0.path ?? "") + $0.owner).localizedCaseInsensitiveContains(query) }
      ForEach(SmartRecommendation.Group.allCases, id: \.rawValue) { group in
        DisclosureGroup(title(group) + " · \(matching.filter { $0.group == group }.count)") {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(matching.filter { $0.group == group }.prefix(limit))) { item in row(item) }
          }
        }
      }
      if SmartRecommendation.Group.allCases.contains(where: { group in matching.filter { $0.group == group }.count > limit }) {
        Button(vm.t("Показать ещё 50", "Show 50 more")) { limit += 50 }
      }
      if catalog.isEmpty { Text(vm.t("Обновите сводку. Дополнительные источники проверяются в своих разделах.", "Refresh the summary. Additional sources are inspected in their own sections.")).foregroundStyle(.secondary) }
    }
    .onAppear { reload() }
    .onChange(of: vm.busy) { _, busy in if !busy { reload() } }
    .onChange(of: vm.recommendationsRevision) { _, _ in reload() }
    .onChange(of: vm.exclusions) { _, _ in reload() }
    .onChange(of: vm.language) { _, _ in reload() }
    .onChange(of: query) { _, _ in limit = 50 }
    .sheet(isPresented: $previewing) { preview }
  }
  private func row(_ item: SmartRecommendation) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Toggle(item.title, isOn: Binding(get: { selected.contains(item.id) }, set: {
          if $0 { selected.insert(item.id) } else { selected.remove(item.id) }
        })).toggleStyle(.checkbox).disabled(!item.selectable || vm.busy)
        Spacer()
        Text(item.bytes.map(size) ?? vm.t("Размер неизвестен", "Size unknown")).font(.caption)
      }
      Text(item.path ?? item.id).font(.caption).lineLimit(1).truncationMode(.middle).help(item.path ?? item.id)
      DisclosureGroup(vm.t("Причина, риск и восстановление", "Evidence, risk and recovery")) {
        VStack(alignment: .leading, spacing: 4) {
          Text(vm.t("Владелец: ", "Owner: ") + item.owner)
          Text(vm.t("Риск: ", "Risk: ") + (item.risk == .rebuild ? vm.t("повторная сборка", "rebuild") : item.risk == .irreplaceable ? vm.t("невосполнимые данные", "irreplaceable data") : vm.t("потеря данных", "data loss")))
          Text(item.evidence.joined(separator: "\n"))
          Text(item.blockers.joined(separator: "\n")).foregroundStyle(.orange)
          Text(item.conditions.joined(separator: "\n"))
          Text(item.recovery)
          Text(item.rule + " · v\(item.version) · " + (item.checkedAt?.formatted() ?? vm.t("Не проверено", "Not inspected")))
          Text(item.evidenceComplete ? vm.t("Метаданные заполнены; это не гарантия безопасности", "Metadata complete; not a safety guarantee") : vm.t("Доказательства или размер неполные", "Evidence or size incomplete"))
        }.font(.caption).textSelection(.enabled)
      }
      Button(vm.t("Посмотреть в разделе", "Review in section")) { open(item.section) }.disabled(vm.busy)
      Divider()
    }
  }
  private var preview: some View {
    let report = RecommendationPreview(catalog.filter { selected.contains($0.id) })
    return VStack(alignment: .leading, spacing: 14) {
      Text(vm.t("Предпросмотр выбранного", "Selection preview")).font(.title2.bold())
      Text("\(report.objects.count) · " + size(report.knownLogicalBytes) + vm.t(" — известный логический объём", " — known logical size"))
      Text(vm.t("Пересечения исключены: \(report.omittedOverlapCount). Заблокировано или сохраняется как копия: \(report.rejectedCount). Размер неизвестен: \(report.unknownSizeCount).", "Overlaps omitted: \(report.omittedOverlapCount). Blocked or retained as a copy: \(report.rejectedCount). Unknown sizes: \(report.unknownSizeCount)."))
      Text(vm.t("Это не обещание свободного места. Карантин остаётся на диске; общие блоки APFS не измерены.", "This is not guaranteed free space. Quarantine remains on disk; shared APFS blocks are not measured."))
      if report.hasUnverifiedDirectoryOverlap {
        Text(vm.t("Размеры папок агрегированы: жёсткие ссылки между разными папками могут завышать сумму. Точный суммарный объём не подтверждён.", "Folder sizes are aggregates: hard links across folders may inflate the sum. Exact total is not verified.")).foregroundStyle(.orange)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(report.objects) { item in
            VStack(alignment: .leading) {
              Text(item.title).bold()
              Text(item.path ?? item.id).font(.caption).textSelection(.enabled)
              Text(item.owner).font(.caption).foregroundStyle(.secondary)
              Text(item.recovery).font(.caption)
              Button(vm.t("Проверить и выбрать действие в разделе", "Validate and choose action in section")) {
                previewing = false; open(item.section)
              }
            }
          }
        }
      }
      Button(vm.t("Закрыть", "Close")) { previewing = false }.keyboardShortcut(.cancelAction)
    }.padding(24).frame(width: 650, height: 520)
  }
  private func open(_ section: String) {
    if section == "personal" { vm.page = "files" } else { vm.openOpportunity(section) }
  }
  private func reload() {
    catalog = SmartRecommendations.catalog(personal: vm.recommendations, snapshotDate: vm.snapshotDate,
      archives: vm.archiveInventory, archiveDate: vm.archiveScanDate, keep: vm.archiveKeep,
      pinned: vm.pinnedArchives, derived: vm.derivedCaches, derivedDate: vm.derivedReadAt,
      derivedIssue: vm.derivedReadIssue, duplicates: vm.duplicates, duplicateDate: vm.duplicatesReadAt,
      projects: vm.projectData, projectDate: vm.projectDataDate, projectIssue: vm.projectDataIssue,
      worktrees: vm.worktreeReviews, worktreeDate: vm.worktreeReadAt, worktreeIssue: vm.worktreeIssue,
      simulators: vm.simulatorInventory, simulatorDate: vm.simulatorReadAt, simulatorIssue: vm.simulatorReadIssue,
      testDevices: vm.testDevices, testDate: vm.testDeviceReadAt, testIssue: vm.testDeviceIssue,
      exclusions: vm.exclusions, russian: vm.language != "en")
    selected = []
  }
}
