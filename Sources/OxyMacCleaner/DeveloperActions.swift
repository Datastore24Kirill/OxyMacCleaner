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
        simulatorReadAt = Date(); simulatorReadIssue = nil
        selectedDevices.formIntersection(simulatorInventory.devices.filter(\.removable).map(\.id))
        selectedRuntimes.formIntersection(
          simulatorInventory.runtimes.filter {
            Simulators.canRemove($0, devices: simulatorInventory.devices)
          }.map(\.id))
        status = t("Список симуляторов обновлён", "Simulator inventory refreshed")
      } catch { simulatorReadIssue = error.localizedDescription; self.error = error.localizedDescription }
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
            "Это удаление через Xcode, без карантина. Устройства потеряют установленные приложения и тестовые данные без восстановления. Runtimes можно скачать заново в Xcode → Settings → Components, если версия доступна. Остальные устройства с удаляемым runtime станут недоступны. Запущенные устройства и устройства активных тестов защищены. Сборки на других устройствах не мешают.",
            "This uses Xcode deletion without quarantine. Devices lose installed apps and test data permanently. Runtimes can be downloaded again in Xcode Settings → Components if available. Other devices using a removed runtime become unavailable. Running devices and active test destinations are protected. Builds on other devices do not block cleanup."
          ), destructive: true)
    else { return }
    busy = true
    developerResult = ""
    cancellation = Cancellation()
    let token = cancellation
    task = Task {
      var messages: [String] = []
      var removedDevicePaths: [String] = []
      var completed = 0
      var failures = 0
      for device in devices {
        if token.cancelled { break }
        status = t("Удаляем устройство: ", "Deleting device: ") + device.name
        do {
          let removed = try await Task.detached { try Simulators.removeDevice(device.id) }.value
          if removed { completed += 1; selectedDevices.remove(device.id); removedDevicePaths.append(home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/" + device.id).path) }
          messages.append(
            device.name + ": "
              + (removed
                ? t("удалено", "deleted")
                : t("команда выполнена; проверьте список", "command completed; check inventory")))
        } catch { failures += 1; messages.append(device.name + ": " + error.localizedDescription) }
      }
      for runtime in runtimes {
        if token.cancelled { break }
        status = t("Удаляем runtime: ", "Deleting runtime: ") + runtime.version
        do {
          let removed = try await Task.detached { try Simulators.removeRuntime(runtime.id) }.value
          if removed { completed += 1; selectedRuntimes.remove(runtime.id) }
          messages.append(
            runtime.version + ": "
              + (removed
                ? t("удалён", "deleted")
                : t(
                  "удаление запрошено; обновите список позже", "deletion requested; refresh later"))
          )
        } catch { failures += 1; messages.append(runtime.version + ": " + error.localizedDescription) }
      }
      let summary = CleanupSummary(selected: devices.count + runtimes.count, completed: completed, attempted: messages.count).text(russian: language != "en")
      developerResult = summary + "\n" + messages.joined(separator: "\n")
      if failures > 0 { self.error = summary + "\n\n" + messages.joined(separator: "\n") }
      log(developerResult)
      do {
        simulatorInventory = try await Task.detached { try Simulators.inventory() }.value
        simulatorReadAt = Date(); simulatorReadIssue = nil
        selectedDevices.formIntersection(simulatorInventory.devices.filter(\.removable).map(\.id))
        selectedRuntimes.formIntersection(simulatorInventory.runtimes.map(\.id))
      } catch { simulatorReadIssue = error.localizedDescription; self.error = error.localizedDescription }
      await reconcileRemovedPaths(removedDevicePaths, invalidateOnly: completed > 0)

      status =
        token.cancelled
        ? t("Остановлено между операциями", "Stopped between operations")
        : summary
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
        derivedReadIssue = nil
      } catch { derivedReadIssue = error.localizedDescription; self.error = error.localizedDescription }
      busy = false
      status = derivedReadIssue == nil ? t("Проверка DerivedData завершена", "DerivedData inspection complete") : t("Не удалось прочитать DerivedData. Обновите список после устранения причины.", "Could not read DerivedData. Resolve the issue and refresh.")
    }
  }
  func quarantineDerivedData() { cleanDerivedData(permanently: false) }
  func deleteDerivedData() { cleanDerivedData(permanently: true) }
  private func cleanDerivedData(permanently: Bool) {
    guard !busy else { return }
    let caches = derivedCaches.filter { selectedDerived.contains($0.id) }
    guard !caches.isEmpty else { return }
    guard
      confirm(
        permanently
          ? t("Удалить выбранные кэши?", "Delete selected caches?")
          : t("Перенести выбранные кэши в карантин?", "Quarantine selected caches?"),
        caches.map { $0.project + " · " + $0.category }.joined(separator: "\n") + "\n\n"
          + t(
            "Активные сборки и кэши, изменённые за последние 10 минут, защищены. Индекс и промежуточные файлы будут созданы заново. Следующая сборка займёт больше времени. Старые логи восстановить нельзя. Исходники, SourcePackages и готовые продукты не затрагиваются.",
            "Active builds and caches modified within 10 minutes are protected. Indexes and intermediates will be rebuilt. The next build will take longer. Old logs cannot be recovered. Sources, SourcePackages and built products are excluded."
          )
          + "\n"
          + (permanently
            ? t("Удаление без Корзины и карантина.", "Deletion without Trash or quarantine.")
            : t("Карантин продолжает занимать место.", "Quarantine still occupies space.")),
        destructive: permanently,
        action: permanently ? t("Удалить кэши", "Delete caches") : t("В карантин", "Quarantine"))
    else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let store = quarantine
    let excluded = exclusions
    task = Task {
      var messages: [String] = []
      var removedPaths: [String] = []
      for cache in caches {
        if token.cancelled { break }
        status =
          t("Обрабатываем кэши: ", "Processing caches: ") + cache.project + " · "
          + cache.category
        do {
          _ = try await Task.detached {
            let plan = try DerivedData.prepare(cache, cancellation: token)
            if permanently {
              try DerivedData.delete(plan, protectedPaths: excluded, cancellation: token)
            } else {
              _ = try store.moveDerivedData(plan, protectedPaths: excluded, cancellation: token)
            }
          }.value
          derivedCaches.removeAll { $0.id == cache.id }
          removedPaths.append(cache.path)
          messages.append(
            cache.project + " / " + cache.category + ": "
              + (permanently ? t("удалён", "deleted") : t("в карантине", "quarantined")))
        } catch { messages.append(cache.project + ": " + error.localizedDescription) }
      }
      await reconcileRemovedPaths(removedPaths)
      let summary = CleanupSummary(selected: caches.count, completed: removedPaths.count, attempted: messages.count).text(russian: language != "en")
      developerResult = summary + "\n" + messages.joined(separator: "\n")
      log(developerResult)
      entries = store.entries()
      selectedDerived = []
      busy = false
      status = summary
      if !permanently { scheduleReminder() }
    }
  }
  func quarantineExcessArchives() { processExcessArchives(deleteImmediately: false) }
  func deleteExcessArchives() { processExcessArchives(deleteImmediately: true) }
  func quarantineArchive(_ archive: XcodeArchive) {
    processExcessArchives(deleteImmediately: false, selected: [archive])
  }
  func deleteArchive(_ archive: XcodeArchive) {
    processExcessArchives(deleteImmediately: true, selected: [archive])
  }
  func processSelectedArchives(_ archives: [XcodeArchive], deleteImmediately: Bool) {
    guard !archives.isEmpty else { return }
    processExcessArchives(deleteImmediately: deleteImmediately, selected: archives)
  }
  private func processExcessArchives(deleteImmediately: Bool, selected: [XcodeArchive]? = nil) {
    guard !busy else { return }
    let root = archiveRoot
    var chosenBackup: URL?
    if deleteImmediately && archiveBackupBeforeDelete {
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.message = t(
        "Куда сохранить копии? Лучше выбрать другой диск.",
        "Where should backups be saved? Prefer another disk.")
      guard panel.runModal() == .OK, let folder = panel.url else { return }
      guard !Scanner.inside(folder.path, root.path), !Scanner.inside(root.path, folder.path),
        !Scanner.inside(folder.path, quarantine.root.path)
      else {
        error = t(
          "Выберите папку вне архивов Xcode и карантина.",
          "Choose a folder outside Xcode archives and quarantine.")
        return
      }
      chosenBackup = folder
    }
    let backupRoot = chosenBackup
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let store = quarantine
    developerResult = ""
    task = Task {
      var messages: [String] = []
      var removedPaths: [String] = []
      var completed = 0
      var failures = 0
      do {
        do { try await Task.detached { try DeveloperActivity.assertArchivesIdle() }.value }
        catch {
          throw CleanerError.message(t("Удаление не началось. Дождитесь завершения xcodebuild; Xcode можно оставить открытым. ", "Cleanup did not start. Wait for xcodebuild; Xcode may remain open. ") + error.localizedDescription)
        }
        let fresh = await Task.detached { XcodeArchives.scan(root: root, cancellation: token) }
          .value
        guard fresh.complete, fresh.issues.isEmpty else {
          throw CleanerError.message("Archive inventory incomplete")
        }
        archiveInventory = fresh
        let decisions = ArchiveRetention.decisions(
          fresh.archives, keep: archiveKeep, pinned: pinnedArchives)
        let candidates = fresh.archives.filter {
          if let selected {
            return selected.contains($0) && ArchiveRetention.permits(
              decisions[$0.path], explicitlySelected: true)
          }
          return decisions[$0.path] == .review
        }
        guard !candidates.isEmpty else {
          throw CleanerError.message(t(
            "Нет подходящих архивов. Архив мог измениться, быть защищён или иметь неполные данные. Обновите список.",
            "No eligible archives. The archive may have changed, be protected, or have incomplete metadata. Refresh the list."))
        }
        var plans: [ArchiveTransferPlan] = []
        for (index, archive) in candidates.enumerated() {
          try token.check()
          status =
            t("Проверяем архивы: ", "Checking archives: ") + "\(index + 1)/\(candidates.count)"
          do {
            plans.append(
              try await Task.detached {
                try ArchiveTransfer.prepare(archive: archive, cancellation: token)
              }.value)
          } catch { failures += 1; messages.append(archive.path + ": " + error.localizedDescription) }
        }
        try token.check()
        guard !plans.isEmpty else {
          throw CleanerError.message("No archives passed checks; originals retained")
        }
        let copyNote =
          backupRoot.map {
            t("Сначала сохраним и проверим копии: ", "First save and verify backups: ") + $0.path
          }
          ?? t(
            "Без резервной копии. Восстановление из приложения невозможно.",
            "No backup. These files cannot be restored by this app.")
        let explanation =
          deleteImmediately
          ? t(
            "Оригиналы будут удалены без Корзины и карантина. Архивы и dSYM выпущенных сборок могут понадобиться для разбора сбоев. ",
            "Originals will be deleted without Trash or quarantine. Released archives and dSYMs may be needed to diagnose crashes. "
          ) + copyNote
          : t(
            "Архивы будут перенесены в карантин: можно восстановить, но место пока не освободится. Отдельная копия не нужна.",
            "Archives will move to quarantine: they can be restored but still occupy space. No separate backup is needed."
          )
        let selectionNote = selected == nil
          ? t("Операция включает все архивы сверх лимита, независимо от фильтра.",
              "Includes all archives beyond the limit regardless of filters.")
          : t("Обрабатываются только отмеченные архивы. Лимит хранения для ручного действия не применяется. Если это последний архив приложения, в Organizer не останется его архивов. Архив и dSYM могут потребоваться для разбора сбоев выпущенной версии.",
              "Only the selected archives are processed. Manual selection overrides the count limit. If this is the application's last archive, none will remain in Organizer. The archive and dSYMs may be needed to diagnose released-version crashes.")
        let names = plans.prefix(8).map { $0.source.lastPathComponent }.joined(separator: "\n")
        let extra =
          plans.count > 8
          ? t("\n… и ещё \(plans.count - 8)", "\n… and \(plans.count - 8) more") : ""
        guard
          confirm(
            deleteImmediately
              ? (selected == nil ? t("Удалить архивы сверх лимита?", "Delete archives beyond the limit?") : t("Удалить выбранные архивы?", "Delete selected archives?"))
              : t("Перенести архивы в карантин?", "Quarantine archives?"),
            "\(plans.count) · "
              + ByteCountFormatter.string(
                fromByteCount: plans.reduce(0) { $0 + $1.manifest.bytes }, countStyle: .file)
              + "\n" + names + extra + "\n\n" + explanation + "\n\n" + selectionNote + "\n\n"
              + t(
                "Защищённые архивы пропускаются. Xcode можно оставить открытым. Архивы, изменённые за последние 10 минут, пропускаются. Объём логический: реальная экономия может отличаться.",
                "Protected archives are skipped. Xcode may remain open. Archives modified within 10 minutes are skipped. Logical size may differ from reclaimed space."
              ),
            destructive: deleteImmediately,
            action: deleteImmediately ? t("Удалить", "Delete") : t("В карантин", "Quarantine"))
        else {
          busy = false
          developerResult = messages.joined(separator: "\n")
          status = t("Отменено. Файлы не изменены.", "Cancelled. Files unchanged.")
          return
        }
        let pins = pinnedArchives
        let keep = archiveKeep
        let excluded = exclusions
        for (index, preview) in plans.enumerated() {
          try token.check()
          status = t("Обработка архивов: ", "Processing archives: ") + "\(index + 1)/\(plans.count)"
          do {
            let backupPath = try await Task.detached {
              try DeveloperActivity.assertArchivesIdle()
              let current = XcodeArchives.scan(root: root, cancellation: token)
              guard current.complete, current.issues.isEmpty else {
                throw CleanerError.message("Inventory changed or incomplete")
              }
              let rules = ArchiveRetention.decisions(current.archives, keep: keep, pinned: pins)
              guard ArchiveRetention.permits(rules[preview.source.path], explicitlySelected: selected?.contains(where: { $0.path == preview.source.path }) == true),
                let archive = current.archives.first(where: { $0.path == preview.source.path }),
                try DirectoryManifest.capture(preview.source, cancellation: token)
                  == preview.manifest
              else { throw CleanerError.message("Archive changed or is retained") }
              var plan = preview
              if let backupRoot {
                guard Scanner.inside(preview.source.path, root.path) else {
                  throw CleanerError.message("Archive is outside selected root")
                }
                let relative = String(preview.source.path.dropFirst(root.path.count + 1))
                let backup = backupRoot.appendingPathComponent(relative)
                try FileManager.default.createDirectory(
                  at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: backup.path) {
                  try ArchiveTransfer.createBackup(
                    source: preview.source, destination: backup, cancellation: token)
                }
                plan = try ArchiveTransfer.prepare(
                  archive: archive, backup: backup, cancellation: token)
                guard plan.manifest == preview.manifest else {
                  throw CleanerError.message("Archive changed while preparing backup")
                }
              }
              let retained = ArchiveRetention.retainedPaths(rules, explicitlySelected: selected?.contains(where: { $0.path == preview.source.path }) == true ? preview.source.path : nil)
              if deleteImmediately {
                try store.deleteArchive(
                  plan, pinned: pins, retained: retained, protectedPaths: excluded,
                  cancellation: token)
              } else {
                _ = try store.moveArchive(
                  plan, pinned: pins, retained: retained, protectedPaths: excluded,
                  cancellation: token)
              }
              return plan.backup?.path
            }.value
            completed += 1
            archiveInventory.archives.removeAll { $0.path == preview.source.path }
            archiveSymbols.removeValue(forKey: preview.source.path)
            removedPaths.append(preview.source.path)
            messages.append(
              preview.source.path + ": "
                + (deleteImmediately ? t("удалён", "deleted") : t("в карантине", "quarantined"))
                + (backupPath.map { t("; копия: ", "; backup: ") + $0 } ?? ""))
          } catch { failures += 1; messages.append(preview.source.path + ": " + error.localizedDescription) }
        }
      } catch { failures += 1; messages.append(error.localizedDescription) }
      await reconcileRemovedPaths(removedPaths)
      status = t("Обновляем список архивов…", "Refreshing archives…")
      archiveInventory = await Task.detached {
        XcodeArchives.scan(root: root, cancellation: Cancellation())
      }.value
      archiveScanDate = Date()
      let summary = (deleteImmediately ? t("Удалено архивов: ", "Archives deleted: ") : t("В карантине: ", "Quarantined: ")) + "\(completed)" + t(" · ошибок/блокировок: ", " · errors/blocks: ") + "\(failures)"
      developerResult = summary + "\n" + messages.joined(separator: "\n")
      if completed == 0 && failures > 0 { error = summary + "\n\n" + (messages.first ?? "") }
      log(developerResult)
      entries = store.entries()
      busy = false
      if !deleteImmediately { scheduleReminder() }
      status = summary
    }
  }
  func eraseQuarantinedArchives() {
    guard !busy else { return }
    let archives = entries.filter { $0.state == "quarantined" && $0.isArchive }
    guard !archives.isEmpty,
      confirm(
        t("Удалить архивы из карантина навсегда?", "Permanently delete quarantined archives?"),
        "\(archives.count) · "
          + ByteCountFormatter.string(
            fromByteCount: archives.reduce(0) { $0 + $1.bytes }, countStyle: .file) + "\n"
          + t(
            "Восстановление из карантина станет невозможно. Если при переносе была указана резервная копия, проверим её перед удалением. При ошибке архив останется в карантине.",
            "Quarantine restoration will no longer be possible. If a backup was specified during transfer, it is rechecked before deletion. Failed checks leave the archive in quarantine."
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
