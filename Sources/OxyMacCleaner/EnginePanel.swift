import CleanerCore
import SwiftUI

struct EnginePanel: View {
  @EnvironmentObject var vm: AppModel
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            Text(vm.t("Локально на вашем Mac", "Local on your Mac")).font(.title2.bold())
            Text(vm.t("Обработка на 127.0.0.1. Интернет нужен только для загрузки компонентов; тексты чатов остаются на Mac.", "Processing uses 127.0.0.1. Internet is needed only to download components; chat text stays on your Mac.")).foregroundStyle(.secondary)
            HStack {
              if vm.engineChecking { ProgressView().controlSize(.small) }
              else { Image(systemName: vm.engineReady ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(vm.engineReady ? .green : .orange) }
              Text(vm.engineMessage).textSelection(.enabled)
            }.accessibilityElement(children: .combine)
            HStack {
              if !vm.engineReady && !vm.engineChecking {
                if vm.installedOllama == nil {
                  Button(vm.t("Скачать и установить Ollama", "Download and install Ollama")) { vm.installOllama() }.oxyHelp(.installEngine)
                } else {
                  Button(vm.t("Запустить Ollama", "Launch Ollama")) { vm.launchOllama() }.oxyHelp(.launchEngine)
                }
              }
              Button(vm.t("Проверить состояние", "Check status")) { vm.refreshModels() }.oxyHelp(.checkEngine)
            }.disabled(vm.busy || vm.engineChecking)
            if vm.busy && vm.pullingModel == nil {
              ProgressView(); Text(vm.status)
            }
          }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            Text(vm.t("Модель для контекста", "Context model")).font(.headline)
            Text(vm.t("Память Mac: ", "Mac memory: ") + ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
            modelRow("qwen2.5:7b", title: "Qwen 2.5 · 7B", size: "~5 GB")
            modelRow("qwen2.5:3b", title: "Qwen 2.5 · 3B", size: "~2 GB")
            if let name = vm.pullingModel {
              VStack(alignment: .leading, spacing: 8) {
                Text(name + " · " + vm.status)
                if let progress = vm.modelProgress, let fraction = progress.fraction {
                  ProgressView(value: fraction).accessibilityLabel(vm.t("Прогресс текущего файла модели", "Current model file progress"))
                  Text(String(format: "%.0f%% · %.1f / %.1f MB", fraction * 100, progress.completed / 1e6, progress.total / 1e6)).monospacedDigit()
                  Text(vm.t("Прогресс текущего файла; модель может состоять из нескольких файлов.", "Current file progress; a model can contain several files.")).font(.caption)
                } else { ProgressView().accessibilityLabel(vm.status) }
                Button(vm.t("Отменить загрузку", "Cancel download")) { vm.cancel() }
              }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            if vm.engineReady && vm.models.isEmpty && !vm.engineChecking {
              Text(vm.t("Ollama работает, но локальных моделей пока нет. Скачайте 7B или установите совместимую модель в Ollama и обновите состояние.", "Ollama is running, but no local models were found. Download 7B or install a compatible model in Ollama and refresh status.")).font(.callout)
            }
            if !vm.models.isEmpty {
              Picker(vm.t("Выбранная модель", "Selected model"), selection: $vm.model) {
                ForEach(vm.models, id: \.self) { Text($0).tag($0) }
              }.oxyHelp(.model).disabled(vm.busy || !vm.engineReady)
            }
            Text(vm.t("Для контекста рекомендуем 7B. 3B не прошла проверку качества. Перед переносом проверьте результат; длинная история обрабатывается частями. Другие задачи Ollama не останавливаются.", "Prefer 7B for context. 3B failed quality checks. Review the result before transfer; long histories are processed in parts. Other Ollama tasks are not stopped.")).font(.caption).foregroundStyle(.secondary)
          }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .task { vm.refreshModels(force: false) }
    .onChange(of: scenePhase) { _, phase in if phase == .active { vm.refreshModels(force: false) } }
    .onChange(of: vm.busy) { _, busy in if !busy { vm.refreshModels(force: false) } }
  }
  private func modelRow(_ name: String, title: String, size: String) -> some View {
    HStack {
      VStack(alignment: .leading) {
        Text(title).font(.headline)
        Text(vm.models.contains(name) ? vm.t("Установлена", "Installed") : size).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if vm.models.contains(name) {
        if vm.model == name { Label(vm.t("Выбрана", "Selected"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        else { Button(vm.t("Выбрать", "Select")) { vm.pull(name) }.accessibilityLabel(vm.t("Выбрать модель ", "Select model ") + title).disabled(vm.busy || !vm.engineReady) }
      } else {
        Button(vm.t("Скачать", "Download")) { vm.pull(name) }.oxyHelp(.pull).disabled(vm.busy || vm.engineChecking || !vm.engineReady)
      }
    }.padding(.vertical, 6)
  }
}
