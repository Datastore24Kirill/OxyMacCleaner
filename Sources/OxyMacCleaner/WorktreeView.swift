import CleanerCore
import SwiftUI

extension AppModel {
  func chooseWorktreeRepository() {
    guard !busy else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    if panel.runModal() == .OK, let url = panel.url {
      worktreeRepository = url
      UserDefaults.standard.set(url.path, forKey: "worktreeRepository")
      readWorktrees()
    }
  }
  func readWorktrees() {
    guard !busy, let repository = worktreeRepository else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let excluded = exclusions
    worktreeReviews = []
    worktreeReadAt = nil
    worktreeIssue = nil
    task = Task {
      do {
        let trees = try await Task.detached { try GitWorktrees.list(repository) }.value
        guard let main = trees.first else { throw CleanerError.message("No main worktree") }
        let mainRepository = URL(fileURLWithPath: main.path)
        worktreeRepository = mainRepository
        UserDefaults.standard.set(main.path, forKey: "worktreeRepository")
        for (index, tree) in trees.enumerated() {
          try token.check()
          status =
            t("Проверяем рабочие деревья", "Inspecting worktrees") + " \(index + 1)/\(trees.count)"
          let review = await Task.detached {
            GitWorktrees.inspect(
              tree, repository: mainRepository, exclusions: excluded, cancellation: token)
          }.value
          worktreeReviews.append(review)
        }
        try token.check()
        worktreeReadAt = Date()
        status = t("Рабочие деревья проверены", "Worktree inspection complete")
      } catch {
        worktreeIssue =
          error is CancellationError
          ? t("Проверка остановлена", "Inspection stopped") : error.localizedDescription
        status = worktreeIssue ?? ""
      }
      busy = false
    }
  }
  func removeWorktree(_ review: WorktreeReview) {
    guard !busy, review.eligible else { return }
    busy = true
    cancellation = Cancellation()
    let token = cancellation
    let excluded = exclusions
    status = t("Повторная проверка дерева…", "Rechecking worktree…")
    task = Task {
      do {
        let plan = try await Task.detached {
          try GitWorktrees.prepare(review, exclusions: excluded, cancellation: token)
        }.value
        try token.check()
        guard
          confirm(
            t("Удалить рабочее дерево?", "Remove worktree?"),
            review.id + "\n" + review.tree.branch + "\n\n"
              + t(
                "Будет удалена эта рабочая папка через Git, без карантина. Ветка и общий репозиторий сохраняются. Закройте редакторы и завершите задачи агентов, связанные с этой папкой. Отсутствие открытых файлов не доказывает, что агент больше её не использует. Проверка remote-tracking refs локальная: сервер не опрашивался. Продолжайте, только если дерево больше не нужно.",
                "Git will remove this working directory without quarantine. The branch and shared repository remain. Close editors and finish agent tasks using this folder. No open files does not prove an agent has stopped using it. Remote-tracking refs were checked locally; no server was contacted. Continue only if this tree is no longer needed."
              ), destructive: true)
        else {
          busy = false
          status = t("Удаление отменено", "Removal cancelled")
          return
        }
        try await Task.detached {
          try GitWorktrees.remove(plan, exclusions: excluded, cancellation: token)
        }.value
        log("Git worktree removed: " + review.id)
        worktreeReviews.removeAll { $0.id == review.id }
        worktreeReadAt = Date()
        status = t("Рабочее дерево удалено. Ветка сохранена.", "Worktree removed. Branch retained.")
      } catch {
        self.error = error.localizedDescription
        status = t(
          "Удаление не подтверждено. Обновите список.", "Removal not confirmed. Refresh the list.")
      }
      busy = false
    }
  }
}

struct WorktreeView: View {
  @EnvironmentObject var vm: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(vm.t("Рабочие деревья Git", "Git worktrees")).font(.title3.bold())
      Text(
        vm.t(
          "Дополнительные рабочие папки одного репозитория, включая созданные агентами. Сначала выберите репозиторий. Проверка ничего не удаляет.",
          "Additional checkouts of a repository, including agent-created ones. Choose a repository first. Inspection deletes nothing."
        ))
      HStack {
        Button(vm.t("Выбрать репозиторий…", "Choose repository…")) { vm.chooseWorktreeRepository() }
          .help(
            vm.t(
              "Выберите основной checkout или одно из его рабочих деревьев.",
              "Choose the main checkout or one of its linked worktrees."))
        Button(vm.t("Обновить список", "Refresh list")) { vm.readWorktrees() }
          .disabled(vm.worktreeRepository == nil)
          .help(
            vm.t(
              "Читает список Git, изменения, локальные refs, размеры и признаки активности. Команды могут занять до минуты.",
              "Reads Git registration, changes, local refs, sizes and activity signals. Commands may take up to a minute."
            ))
      }.disabled(vm.busy)
      if let repo = vm.worktreeRepository { Text(repo.path).font(.caption).textSelection(.enabled) }
      Text(
        vm.t(
          "Для удаления: дополнительное дерево, без изменений и ignored-файлов, коммиты сохранены в remote-tracking refs, нет изменений 30 дней и открытых файлов. Неизвестные состояния блокируются. Ветки не удаляются.",
          "Removal requires a linked tree with no changes or ignored files, commits reachable from remote-tracking refs, no changes for 30 days and no open files. Unknown states block removal. Branches are retained."
        )
      )
      .font(.caption).foregroundStyle(.secondary)
      if let issue = vm.worktreeIssue {
        Text(issue).foregroundStyle(.orange).textSelection(.enabled)
      }
      if let date = vm.worktreeReadAt {
        Text(vm.t("Проверено: ", "Checked: ") + date.formatted()).font(.caption)
      }
      ForEach(vm.worktreeReviews) { review in
        worktreeRow(review)
      }
    }
  }
  private func worktreeRow(_ review: WorktreeReview) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(URL(fileURLWithPath: review.id).lastPathComponent).font(.headline)
        Spacer()
        Text(
          review.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            ?? vm.t("Размер не определён", "Size unknown"))
      }
      Text(review.id).font(.caption).textSelection(.enabled)
      Text(review.tree.branch + " · " + String(review.tree.head.prefix(12))).font(.caption)
      if let date = review.modified {
        Text(vm.t("Последнее изменение: ", "Last change: ") + date.formatted()).font(.caption)
      }
      Text(
        review.eligible
          ? vm.t(
            "Кандидат для просмотра. Убедитесь, что задача агента завершена.",
            "Review candidate. Make sure the agent task is finished.")
          : review.blockers.joined(separator: "\n")
      )
      .font(.callout).foregroundStyle(review.eligible ? Color.primary : Color.secondary)
      HStack {
        Button(vm.t("Показать в Finder", "Reveal in Finder")) { vm.reveal(review.id) }.oxyHelp(
          .finder)
        Button(vm.t("Удалить дерево…", "Remove worktree…"), role: .destructive) {
          vm.removeWorktree(review)
        }
        .disabled(!review.eligible || vm.busy || vm.worktreeIssue != nil)
        .help(
          vm.t(
            "Повторно проверяет данные, показывает подтверждение и выполняет git worktree remove без --force. Без карантина; ветка сохраняется.",
            "Rechecks data, asks for confirmation and runs git worktree remove without --force. No quarantine; branch retained."
          ))
      }
    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
  }
}
