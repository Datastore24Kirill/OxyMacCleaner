import CleanerCore
import SwiftUI

extension AppModel {
  func readSimulators() {
    guard !busy else { return }
    busy = true
    status = t("Читаем симуляторы…", "Reading simulators…")
    task = Task {
      do {
        simulatorInventory = try await Task.detached { try Simulators.inventory() }.value
        selectedDevices.formIntersection(simulatorInventory.devices.filter(\.removable).map(\.id))
        selectedRuntimes.formIntersection(
          simulatorInventory.runtimes.filter {
            Simulators.canRemove($0, devices: simulatorInventory.devices)
          }.map(\.id))
        status = t("Список симуляторов обновлён", "Simulator inventory refreshed")
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
  func deleteSelectedSimulators() {
    guard !busy else { return }
    let devices = simulatorInventory.devices.filter {
      selectedDevices.contains($0.id) && $0.removable
    }
    let runtimes = simulatorInventory.runtimes.filter {
      selectedRuntimes.contains($0.id)
        && Simulators.canRemove($0, devices: simulatorInventory.devices)
    }
    guard !devices.isEmpty || !runtimes.isEmpty else { return }
    let names =
      devices.map { $0.name + " · " + $0.runtime }
      + runtimes.map { "Runtime " + $0.version + " (" + $0.build + ")" }
    guard
      confirm(
        t("Удалить выбранные симуляторы?", "Delete selected simulators?"),
        names.joined(separator: "\n") + "\n\n"
          + t(
            "Это удаление через Xcode, без карантина. Устройства потеряют установленные приложения и тестовые данные без восстановления. Runtimes можно скачать заново в Xcode → Settings → Components, если версия доступна. Остальные устройства с удаляемым runtime станут недоступны. Закройте Xcode и остановите сборки.",
            "This uses Xcode deletion without quarantine. Devices lose installed apps and test data permanently. Runtimes can be downloaded again in Xcode Settings → Components if available. Other devices using a removed runtime become unavailable. Close Xcode and stop builds."
          ), destructive: true)
    else { return }
    busy = true
    developerResult = ""
    cancellation = Cancellation()
    let token = cancellation
    task = Task {
      var messages: [String] = []
      for device in devices {
        if token.cancelled { break }
        status = t("Удаляем устройство: ", "Deleting device: ") + device.name
        do {
          let removed = try await Task.detached { try Simulators.removeDevice(device.id) }.value
          messages.append(
            device.name + ": "
              + (removed
                ? t("удалено", "deleted")
                : t("команда выполнена; проверьте список", "command completed; check inventory")))
        } catch { messages.append(device.name + ": " + error.localizedDescription) }
      }
      for runtime in runtimes {
        if token.cancelled { break }
        status = t("Удаляем runtime: ", "Deleting runtime: ") + runtime.version
        do {
          let removed = try await Task.detached { try Simulators.removeRuntime(runtime.id) }.value
          messages.append(
            runtime.version + ": "
              + (removed
                ? t("удалён", "deleted")
                : t(
                  "удаление запрошено; обновите список позже", "deletion requested; refresh later"))
          )
        } catch { messages.append(runtime.version + ": " + error.localizedDescription) }
      }
      developerResult = messages.joined(separator: "\n")
      log(developerResult)
      do { simulatorInventory = try await Task.detached { try Simulators.inventory() }.value } catch
      { self.error = error.localizedDescription }
      selectedDevices = []
      selectedRuntimes = []
      status =
        token.cancelled
        ? t("Остановлено между операциями", "Stopped between operations")
        : t(
          "Обработка симуляторов завершена. См. отчёт.",
          "Simulator processing complete. See report.")
      busy = false
    }
  }
  func readDerivedData() {
    guard !busy else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    status = t("Читаем кэши проектов…", "Reading project caches…")
    task = Task {
      do {
        derivedCaches = try await Task.detached { try DerivedData.inventory(cancellation: token) }
          .value
        selectedDerived = []
        derivedReadAt = Date()
      } catch { self.error = error.localizedDescription }
      busy = false
      status = t("Проверка DerivedData завершена", "DerivedData inspection complete")
    }
  }
  func quarantineDerivedData() {
    guard !busy else { return }
    let caches = derivedCaches.filter { selectedDerived.contains($0.id) }
    guard !caches.isEmpty else { return }
    guard
      confirm(
        t("Перенести выбранные кэши в карантин?", "Quarantine selected caches?"),
        caches.map { $0.project + " · " + $0.category }.joined(separator: "\n") + "\n\n"
          + t(
            "Закройте Xcode и остановите сборки. Следующая сборка и индексирование займут больше времени. Исходники, SourcePackages и готовые продукты не затрагиваются. Карантин продолжает занимать место.",
            "Close Xcode and stop builds. The next build/indexing will take longer. Sources, SourcePackages and built products are excluded. Quarantine still occupies disk space."
          ))
    else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let store = quarantine
    let excluded = exclusions
    task = Task {
      var messages: [String] = []
      for cache in caches {
        if token.cancelled { break }
        status =
          t("Проверяем и переносим: ", "Checking and moving: ") + cache.project + " · "
          + cache.category
        do {
          _ = try await Task.detached {
            let plan = try DerivedData.prepare(cache, cancellation: token)
            return try store.moveDerivedData(plan, protectedPaths: excluded, cancellation: token)
          }.value
          derivedCaches.removeAll { $0.id == cache.id }
          messages.append(
            cache.project + " / " + cache.category + ": " + t("в карантине", "quarantined"))
        } catch { messages.append(cache.project + ": " + error.localizedDescription) }
      }
      developerResult = messages.joined(separator: "\n")
      log(developerResult)
      entries = store.entries()
      selectedDerived = []
      busy = false
      status = t(
        "Обработка DerivedData завершена. См. отчёт.",
        "DerivedData processing complete. See report.")
      scheduleReminder()
    }
  }
  func quarantineExcessArchives() {
    guard !busy else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = t(
      "Папка для полных резервных копий — желательно на другом диске. В ней будут созданы подпапки по датам архивов.",
      "Choose a full-backup folder, preferably on another disk. Archive date subfolders will be preserved."
    )
    guard panel.runModal() == .OK, let backupRoot = panel.url else { return }
    let root = archiveRoot
    guard !Scanner.inside(backupRoot.path, root.path), !Scanner.inside(root.path, backupRoot.path),
      !Scanner.inside(backupRoot.path, quarantine.root.path)
    else {
      error = t(
        "Выберите папку вне архива Xcode и карантина.",
        "Choose a folder outside Xcode archives and quarantine.")
      return
    }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let store = quarantine
    developerResult = ""
    task = Task {
      var messages: [String] = []
      do {
        let fresh = await Task.detached { XcodeArchives.scan(root: root, cancellation: token) }
          .value
        guard fresh.complete, fresh.issues.isEmpty else {
          throw CleanerError.message("Archive inventory incomplete")
        }
        archiveInventory = fresh
        let decisions = ArchiveRetention.decisions(
          fresh.archives, keep: archiveKeep, pinned: pinnedArchives)
        let candidates = fresh.archives.filter { decisions[$0.path] == .review }
        guard !candidates.isEmpty else {
          throw CleanerError.message("No eligible archives beyond retention limit")
        }
        guard
          confirm(
            t("Подготовить копии архивов сверх лимита?", "Prepare backups beyond retention limit?"),
            "\(candidates.count) · "
              + ByteCountFormatter.string(
                fromByteCount: candidates.reduce(0) { $0 + $1.bytes }, countStyle: .file) + "\n"
              + backupRoot.path + "\n"
              + t(
                "Сначала создадим или проверим полные копии. Потом покажем число архивов, прошедших проверки, и запросим перенос. Архивы с ошибками будут пропущены.",
                "First create or verify full backups. Then show the passing count and ask to transfer. Archives failing checks will be skipped."
              ))
        else {
          busy = false
          return
        }
        var plans: [ArchiveTransferPlan] = []
        for (index, archive) in candidates.enumerated() {
          try token.check()
          status =
            t("Копии и проверки: ", "Backups and checks: ") + "\(index + 1)/\(candidates.count) · "
            + archive.name
          do {
            let plan = try await Task.detached {
              let source = URL(fileURLWithPath: archive.path)
              guard Scanner.inside(source.path, root.path) else {
                throw CleanerError.message("Archive is outside selected root")
              }
              let relative = String(source.path.dropFirst(root.path.count + 1))
              let backup = backupRoot.appendingPathComponent(relative)
              try FileManager.default.createDirectory(
                at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
              if !FileManager.default.fileExists(atPath: backup.path) {
                try ArchiveTransfer.createBackup(
                  source: source, destination: backup, cancellation: token)
              }
              return try ArchiveTransfer.prepare(
                archive: archive, backup: backup, cancellation: token)
            }.value
            plans.append(plan)
          } catch {
            messages.append(
              archive.name + " (" + (archive.build ?? "?") + "): " + error.localizedDescription)
          }
        }
        try token.check()
        guard !plans.isEmpty else {
          throw CleanerError.message("No archives passed checks; originals retained")
        }
        guard
          confirm(
            t("Переместить проверенные архивы?", "Transfer verified archives?"),
            "\(plans.count) · "
              + ByteCountFormatter.string(
                fromByteCount: plans.reduce(0) { $0 + $1.manifest.bytes }, countStyle: .file) + "\n"
              + t(
                "Копии проверены. Закройте Xcode и сборки. После переноса архивы исчезнут из Organizer, но их можно восстановить из карантина. Место освободится только после отдельного окончательного удаления.",
                "Backups verified. Close Xcode and builds. Archives will disappear from Organizer but can be restored from quarantine. Space is freed only after separate permanent deletion."
              ))
        else {
          busy = false
          developerResult = messages.joined(separator: "\n")
          return
        }
        let pins = pinnedArchives
        let keep = archiveKeep
        let excluded = exclusions
        for (index, plan) in plans.enumerated() {
          try token.check()
          status = t("Перенос архивов: ", "Transferring archives: ") + "\(index + 1)/\(plans.count)"
          do {
            _ = try await Task.detached {
              let current = XcodeArchives.scan(root: root, cancellation: token)
              guard current.complete, current.issues.isEmpty else {
                throw CleanerError.message("Inventory changed or incomplete")
              }
              let rules = ArchiveRetention.decisions(current.archives, keep: keep, pinned: pins)
              guard rules[plan.source.path] == .review else {
                throw CleanerError.message("Archive is retained")
              }
              return try store.moveArchive(
                plan, pinned: pins, retained: Set(rules.filter { $0.value != .review }.map(\.key)),
                protectedPaths: excluded, cancellation: token)
            }.value
            archiveInventory.archives.removeAll { $0.path == plan.source.path }
            messages.append(plan.source.lastPathComponent + ": " + t("в карантине", "quarantined"))
          } catch {
            messages.append(plan.source.lastPathComponent + ": " + error.localizedDescription)
          }
        }
      } catch { messages.append(error.localizedDescription) }
      developerResult = messages.joined(separator: "\n")
      log(developerResult)
      entries = store.entries()
      busy = false
      scheduleReminder()
      status = t(
        "Обработка архивов завершена. См. отчёт.", "Archive processing complete. See report.")
    }
  }
  func eraseQuarantinedArchives() {
    guard !busy else { return }
    let archives = entries.filter { $0.state == "quarantined" && $0.archiveBackup != nil }
    guard !archives.isEmpty,
      confirm(
        t("Удалить архивы из карантина навсегда?", "Permanently delete quarantined archives?"),
        "\(archives.count) · "
          + ByteCountFormatter.string(
            fromByteCount: archives.reduce(0) { $0 + $1.bytes }, countStyle: .file) + "\n"
          + t(
            "Восстановление из карантина станет невозможно. Перед каждым удалением проверим полную резервную копию; при ошибке архив останется в карантине. Резервные копии не удаляются.",
            "Quarantine restoration will no longer be possible. Each full backup is rechecked; failures leave the archive in quarantine. Backups are retained."
          ), destructive: true)
    else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let store = quarantine
    task = Task {
      var messages: [String] = []
      for (index, entry) in archives.enumerated() {
        if token.cancelled { break }
        status =
          t("Удаление из карантина: ", "Deleting from quarantine: ")
          + "\(index + 1)/\(archives.count)"
        do {
          try await Task.detached { try store.erase(entry) }.value
          messages.append(entry.original + ": " + t("удалён", "deleted"))
        } catch { messages.append(entry.original + ": " + error.localizedDescription) }
      }
      entries = store.entries()
      developerResult = messages.joined(separator: "\n")
      log(developerResult)
      busy = false
      status = t(
        "Обработка завершена. Результат в истории операций.",
        "Processing complete. See operation history.")
    }
  }
}
