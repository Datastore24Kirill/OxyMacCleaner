import SwiftUI
import CleanerCore

struct TestSimulatorView: View {
  @EnvironmentObject var vm: AppModel
  @State private var devices: [SimulatorDevice] = []
  @State private var selected: Set<String> = []
  @State private var sizes: [String: Int64] = [:]
  @State private var report = ""
  @State private var confirming = false
  @State private var measuring = false
  @State private var stopMeasurement = false
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(vm.t("Тестовые симуляторы Xcode", "Xcode test simulators")).font(.title2.bold())
      Text(vm.t("Отдельные копии устройств для автотестов (XCTestDevices). Их можно создать заново; приложения и данные внутри удалённого устройства будут потеряны. Обычные симуляторы и образы iOS здесь не удаляются.", "Separate test devices (XCTestDevices). They can be recreated; apps and data inside deleted devices will be lost. Regular simulators and iOS runtimes are not removed here."))
      HStack {
        Button(vm.t("Обновить список", "Refresh")) { refresh() }
          .help(vm.t("Читает отдельный набор XCTestDevices через simctl. Ничего не удаляет.", "Reads the XCTestDevices set via simctl without deleting anything."))
        Button(vm.t("Посчитать размеры", "Measure sizes")) { measure() }.disabled(devices.isEmpty)
          .help(vm.t("Измеряет каждое устройство. APFS может совместно хранить блоки: сумма не гарантирует освобождение такого же места.", "Measures each device. Shared APFS blocks mean the sum is not guaranteed reclaimed space."))
        Button(vm.t("Удалить выбранные", "Delete selected"), role: .destructive) { confirming = true }
          .disabled(selected.isEmpty)
          .help(vm.t("Удаляет только отмеченные выключенные тестовые устройства через simctl. Завершите тесты и закройте Xcode перед удалением.", "Deletes selected shut-down test devices via simctl. Stop tests and close Xcode first."))
      }.disabled(vm.busy)
      if measuring { Button(vm.t("Остановить подсчёт", "Stop measuring")) { stopMeasurement = true }.help(vm.t("Останавливает после текущего устройства.", "Stops after the current device.")) }
      Text("\(devices.count) · " + ByteCountFormatter.string(fromByteCount: sizes.values.reduce(0,+), countStyle: .file) + vm.t(" измерено", " measured"))
      Text(report).font(.caption).textSelection(.enabled)
      ForEach(devices) { device in
        HStack {
          Toggle(isOn: Binding(get: { selected.contains(device.id) }, set: { if $0 { selected.insert(device.id) } else { selected.remove(device.id) } })) {
            VStack(alignment: .leading) {
              Text(device.name)
              Text(device.runtime + " · " + device.state).font(.caption).foregroundStyle(.secondary)
              Text(device.id).font(.caption2).foregroundStyle(.secondary)
            }
          }.disabled(vm.busy || !device.removable)
          Spacer()
          Text(sizes[device.id].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
        }
        Divider()
      }
    }.confirmationDialog(vm.t("Удалить выбранные тестовые устройства без восстановления?", "Permanently delete selected test devices?"), isPresented: $confirming, titleVisibility: .visible) {
      Button(vm.t("Удалить", "Delete"), role: .destructive) { remove() }
    } message: {
      Text(vm.t("Устройств: ", "Devices: ") + "\(selected.count). " + vm.t("Сохранённые внутри данные будут потеряны. Xcode создаст необходимые тестовые копии при следующих запусках тестов.", "Their stored data will be lost. Xcode creates required test copies on later test runs."))
    }
  }
  func refresh() {
    vm.busy = true
    Task { @MainActor in
      defer { vm.busy = false }
      do {
        devices = try await Task.detached { try TestSimulators.devices() }.value
        selected.formIntersection(devices.filter(\.removable).map(\.id))
        sizes = sizes.filter { key, _ in devices.contains { $0.id == key } }
        report = vm.t("Список обновлён", "List refreshed")
      } catch { report = error.localizedDescription }
    }
  }
  func measure() {
    vm.busy = true
    measuring = true; stopMeasurement = false
    let ids = devices.map(\.id)
    Task { @MainActor in
      defer { vm.busy = false }
      defer { measuring = false }
      for (index,id) in ids.enumerated() {
        if stopMeasurement { report = vm.t("Подсчёт остановлен", "Measurement stopped"); break }
        report = vm.t("Измеряем: ", "Measuring: ") + "\(index+1)/\(ids.count)"
        do { sizes[id] = try await Task.detached { try TestSimulators.size(id) }.value }
        catch { report = error.localizedDescription; return }
      }
      if !stopMeasurement { report = vm.t("Размеры измерены. Реальная экономия может отличаться.", "Sizes measured. Reclaimed space may differ.") }
    }
  }
  func remove() {
    vm.busy = true
    let ids = selected.sorted()
    Task { @MainActor in
      defer { vm.busy = false }
      var messages: [String] = []
      for id in ids {
        do {
          let removed = try await Task.detached { try TestSimulators.remove(id) }.value
          messages.append(id + (removed ? vm.t(": удалено", ": deleted") : vm.t(": осталось в списке", ": still present")))
          if removed { devices.removeAll { $0.id == id }; selected.remove(id); sizes.removeValue(forKey: id) }
        } catch { messages.append(error.localizedDescription); break }
      }
      report = messages.joined(separator: "\n")
      vm.log(report)
    }
  }
}
