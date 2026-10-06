import CleanerCore
import SwiftUI

extension AppModel {
  func openOpportunity(_ section: String) {
    if section == "duplicates" {
      page = "duplicates"
    } else {
      developerSection = section
      page = "developer"
    }
  }
  /// Explicit read-only refresh. Duplicate hashing stays opt-in in its own screen.
  func refreshOpportunities() {
    guard !busy else { return }
    refreshRecommendations()
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let root = archiveRoot
    archiveSymbols = [:]
    task = Task {
      status = t(
        "Возможности очистки · 1/3 · архивы Xcode…", "Cleanup opportunities · 1/3 · Xcode archives…"
      )
      archiveInventory = await Task.detached { XcodeArchives.scan(root: root, cancellation: token) }
        .value
      archiveScanDate = Date()
      if !token.cancelled {
        status = t(
          "Возможности очистки · 2/3 · DerivedData…", "Cleanup opportunities · 2/3 · DerivedData…")
        do {
          derivedCaches = try await Task.detached { try DerivedData.inventory(cancellation: token) }
            .value
          derivedReadAt = Date()
          derivedReadIssue = nil
        } catch { derivedReadIssue = error.localizedDescription }
      }
      if !token.cancelled {
        status = t(
          "Возможности очистки · 3/3 · симуляторы…", "Cleanup opportunities · 3/3 · simulators…")
        do {
          let result = try await Task.detached { try Simulators.inventory() }.value
          if !token.cancelled {
            simulatorInventory = result
            simulatorReadAt = Date()
            simulatorReadIssue = nil
          }
        } catch { simulatorReadIssue = error.localizedDescription }
      }
      selectedDerived = []
      selectedDevices = []
      selectedRuntimes = []
      busy = false
      status =
        token.cancelled
        ? t(
          "Проверка остановлена. Даты показаны у каждого источника.",
          "Inspection stopped. Each source shows its own date.")
        : t(
          "Сводка обновлена. Дубликаты проверяются отдельно по содержимому.",
          "Summary refreshed. Duplicates require a separate content comparison.")
    }
  }
}
