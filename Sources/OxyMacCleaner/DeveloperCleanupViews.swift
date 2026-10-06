import CleanerCore
import SwiftUI

struct DeveloperReportView: View {
  @EnvironmentObject var vm: AppModel
  var body: some View {
    if !vm.developerResult.isEmpty {
      DisclosureGroup(vm.t("Отчёт последней операции", "Last operation report")) {
        ScrollView {
          Text(vm.developerResult).font(.caption).textSelection(.enabled).frame(
            maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 240)
      }.oxyHelp(.report)
    }
  }
}
struct SimulatorCleanupView: View {
  @EnvironmentObject var vm: AppModel
  @State private var query = ""
  @State private var page = 0
  private var devices: [SimulatorDevice] {
    vm.simulatorInventory.devices.filter {
      query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        || $0.runtime.localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(vm.t("Симуляторы", "Simulators")).font(.title2.bold())
      Text(
        vm.t(
          "Устройства — виртуальные iPhone/iPad с приложениями и данными. Runtime — общая версия ОС для этих устройств. Здесь удаляем через штатный simctl, без карантина.",
          "Devices are virtual iPhones/iPads with apps and data. A runtime is their shared OS version. Deletion uses Apple's simctl, without quarantine."
        )
      ).foregroundStyle(.secondary)
      HStack {
        Button(vm.t("Обновить список", "Refresh inventory")) { vm.readSimulators() }.oxyHelp(
          .simRead)
        Spacer()
        Button(
          vm.t(
            "Удалить выбранные (\(vm.selectedDevices.count + vm.selectedRuntimes.count))…",
            "Delete selected (\(vm.selectedDevices.count + vm.selectedRuntimes.count))…"),
          role: .destructive
        ) { vm.deleteSelectedSimulators() }.oxyHelp(.simDelete).disabled(
          vm.selectedDevices.isEmpty && vm.selectedRuntimes.isEmpty)
      }.disabled(vm.busy)
      DeveloperReportView()
      Text(vm.t("Устройства", "Devices")).font(.headline)
      HStack {
        Button(vm.t("Отметить недоступные", "Select unavailable")) {
          vm.selectedDevices.formUnion(
            vm.simulatorInventory.devices.filter { !$0.isAvailable && $0.removable }.map(\.id))
        }.oxyHelp(.simUnavailable)
        Button(vm.t("Снять выбор", "Clear selection")) {
          vm.selectedDevices = []
          vm.selectedRuntimes = []
        }.oxyHelp(.clearSelection)
      }.disabled(vm.busy)
      TextField(vm.t("Поиск устройства или версии ОС", "Search device or OS"), text: $query)
        .oxyHelp(.search)
        .textFieldStyle(.roundedBorder)
      HStack {
        Button(vm.t("Назад", "Previous")) { page -= 1 }.oxyHelp(.previous).disabled(page == 0)
        Text("\(page + 1)/\(max(1, (devices.count + 9) / 10)) · \(devices.count)")
        Button(vm.t("Далее", "Next")) { page += 1 }.oxyHelp(.next).disabled(
          (page + 1) * 10 >= devices.count)
      }
      ForEach(devices.dropFirst(page * 10).prefix(10)) { device in
        Toggle(
          isOn: Binding(
            get: { vm.selectedDevices.contains(device.id) },
            set: {
              if $0 {
                vm.selectedDevices.insert(device.id)
              } else {
                vm.selectedDevices.remove(device.id)
              }
            })
        ) {
          VStack(alignment: .leading) {
            Text(
              device.name + " · "
                + (device.runtime.components(separatedBy: ".").last ?? device.runtime))
            Text(
              device.state + " · "
                + (device.isAvailable
                  ? vm.t("доступно", "available")
                  : vm.t("runtime недоступен", "runtime unavailable"))
            ).font(.caption).foregroundStyle(.secondary)
            if !device.removable {
              Text(
                vm.t(
                  "Сначала завершите работу устройства в Simulator",
                  "Shut down the device in Simulator first")
              ).font(.caption).foregroundStyle(.orange)
            }
          }
        }.oxyHelp(.selectDevice).toggleStyle(.checkbox).disabled(vm.busy || !device.removable)
      }
      Divider()
      Text(vm.t("Runtimes — версии ОС", "Runtimes — OS versions")).font(.headline)
      Button(vm.t("Отметить неиспользуемые 90+ дней", "Select unused for 90+ days")) {
        vm.selectedRuntimes.formUnion(
          vm.simulatorInventory.runtimes.filter {
            $0.unused(days: 90) && Simulators.canRemove($0, devices: vm.simulatorInventory.devices)
          }.map(\.id))
      }.oxyHelp(.simOld).disabled(vm.busy)
      Text(
        vm.t(
          "Возраст не означает, что версия вам не нужна. Проверьте выбор. Удаление runtime оставит связанные устройства без ОС; их данные автоматически не удаляются.",
          "Age does not mean a version is unnecessary. Review your selection. Removing a runtime leaves related devices without an OS; their data is not automatically deleted."
        )
      ).font(.caption).foregroundStyle(.secondary)
      if let issue = vm.simulatorInventory.runtimeIssue {
        Text(issue).font(.caption).foregroundStyle(.orange)
      }
      ForEach(vm.simulatorInventory.runtimes) { runtime in
        Toggle(
          isOn: Binding(
            get: { vm.selectedRuntimes.contains(runtime.id) },
            set: {
              if $0 {
                vm.selectedRuntimes.insert(runtime.id)
              } else {
                vm.selectedRuntimes.remove(runtime.id)
              }
            })
        ) {
          VStack(alignment: .leading) {
            Text(
              (runtime.runtimeIdentifier.components(separatedBy: ".").last ?? "Runtime") + " · "
                + runtime.version + " (" + runtime.build + ")")
            Text(
              (runtime.sizeBytes.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
              } ?? "?") + " · " + runtime.state + " · " + vm.t("Устройств: ", "Devices: ")
                + "\(vm.simulatorInventory.devices.filter { $0.runtime == runtime.runtimeIdentifier }.count)"
            ).font(.caption)
            Text(
              vm.t("Последнее использование: ", "Last used: ")
                + (runtime.lastUsedAt ?? vm.t("неизвестно", "unknown"))
            ).font(.caption).foregroundStyle(.secondary)
            if !Simulators.canRemove(runtime, devices: vm.simulatorInventory.devices) {
              Text(
                vm.t(
                  "Защищён, используется или операция сейчас недоступна",
                  "Protected, in use or currently unavailable")
              ).font(.caption).foregroundStyle(.orange)
            }
          }
        }.oxyHelp(.selectRuntime).toggleStyle(.checkbox).disabled(
          vm.busy || !Simulators.canRemove(runtime, devices: vm.simulatorInventory.devices))
      }
      Text(
        vm.t(
          "Если Xcode не поддерживает операцию или требует системное подтверждение, ошибка появится в отчёте. Автоматический обход системных ограничений не выполняется. Отмена останавливает очередь после текущей команды.",
          "Unsupported operations or required system approval are reported as errors. System restrictions are not bypassed. Cancellation stops after the current command."
        )
      ).font(.caption).foregroundStyle(.secondary)
    }.modifier(
      InventoryLoading(
        isLoaded: !vm.simulatorInventory.devices.isEmpty || !vm.simulatorInventory.runtimes.isEmpty,
        load: vm.readSimulators)
    ).onChange(of: query) { _, _ in page = 0 }.onChange(of: vm.simulatorInventory.devices.count) {
      _, _ in page = 0
    }
  }
}
struct DerivedDataView: View {
  @EnvironmentObject var vm: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("DerivedData").font(.title2.bold())
      Text(
        vm.t(
          "Кэши привязаны к проекту по info.plist Xcode. Можно очистить промежуточные сборки, индекс и логи. Исходники, SourcePackages, готовые продукты и общие неизвестные кэши не выбираются.",
          "Caches are associated with projects through Xcode info.plist. Only build intermediates, index and logs are eligible. Sources, SourcePackages, built products and unknown shared caches are excluded."
        )
      ).foregroundStyle(.secondary)
      HStack {
        Button(vm.t("Обновить список", "Refresh list")) { vm.readDerivedData() }.oxyHelp(
          .derivedRead)
        Spacer()
        Button(
          vm.t(
            "Очистить выбранные (\(vm.selectedDerived.count))…",
            "Clean selected (\(vm.selectedDerived.count))…"), role: .destructive
        ) {
          vm.deleteDerivedData()
        }.oxyHelp(.derivedDelete).disabled(vm.selectedDerived.isEmpty)
        Menu(vm.t("Ещё", "More")) {
          Button(
            vm.t(
              "В карантин выбранные (\(vm.selectedDerived.count))…",
              "Quarantine selected (\(vm.selectedDerived.count))…")
          ) { vm.quarantineDerivedData() }.oxyHelp(.derivedQuarantine).disabled(
            vm.selectedDerived.isEmpty)
        }.help(
          vm.t(
            "Альтернатива: карантин с возможностью восстановления.",
            "Alternative: quarantine with restoration.")
        )
        .fixedSize()
      }.disabled(vm.busy)
      Text(
        vm.t(
          "Закройте Xcode и остановите сборки. Перед очисткой проверяем процессы и неизменность файлов; кэши с изменениями за последние 10 минут защищены. Следующая сборка и индексирование будут дольше. Ссылки и неполностью прочитанные каталоги защищены.",
          "Close Xcode and stop builds. Processes and file stability are checked before cleanup; caches changed within 10 minutes are protected. The next build and indexing will take longer. Links and incompletely read folders block transfer."
        )
      ).font(.caption).foregroundStyle(.secondary)
      DeveloperReportView()
      ForEach(vm.derivedCaches) { cache in
        Toggle(
          isOn: Binding(
            get: { vm.selectedDerived.contains(cache.id) },
            set: {
              if $0 {
                vm.selectedDerived.insert(cache.id)
              } else {
                vm.selectedDerived.remove(cache.id)
              }
            })
        ) {
          VStack(alignment: .leading, spacing: 4) {
            Text(cache.project + " · " + cache.category).font(.headline)
            Text(
              ByteCountFormatter.string(fromByteCount: cache.bytes, countStyle: .file) + " · "
                + cache.modified.formatted()
            ).font(.caption)
            Text(cache.workspace).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if cache.issues > 0 {
              Text(
                vm.t(
                  "Обход неполный — перенос недоступен", "Incomplete scan — transfer unavailable")
              ).font(.caption).foregroundStyle(.orange)
            }
          }
        }.oxyHelp(.selectDerived).toggleStyle(.checkbox).disabled(vm.busy || cache.issues > 0)
      }
      Text(DerivedData.root.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      if let date = vm.derivedReadAt {
        Text(vm.t("Проверено: ", "Checked: ") + date.formatted() + " · \(vm.derivedCaches.count)")
          .font(.caption)
        if vm.derivedCaches.isEmpty {
          Text(
            vm.t(
              "Подходящих кэшей проектов в стандартной папке не найдено. Общие ModuleCache/SymbolCache и пользовательские пути DerivedData пока не входят в эту проверку.",
              "No eligible project caches found in the default folder. Shared ModuleCache/SymbolCache and custom DerivedData locations are not included yet."
            )
          ).foregroundStyle(.secondary)
        }
      } else if vm.derivedCaches.isEmpty {
        Text(
          vm.t(
            "Обновите список, чтобы найти кэши проектов.",
            "Refresh the list to find project caches.")
        ).foregroundStyle(.secondary)
      }
    }.modifier(InventoryLoading(isLoaded: vm.derivedReadAt != nil, load: vm.readDerivedData))
  }
}
