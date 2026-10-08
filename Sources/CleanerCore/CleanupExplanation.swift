import Foundation

/// Describes consequences, not eligibility. Every action still uses its own fresh safety checks.
public struct CleanupExplanation: Sendable {
  public let owner: String
  public let consequence: String
  public let recovery: String
  public static func forSection(_ section: String, russian: Bool) -> CleanupExplanation {
    func t(_ ru: String, _ en: String) -> String { russian ? ru : en }
    switch section {
    case "archives": return .init(owner: "Xcode", consequence: t("Удаление сборки и её символов может лишить возможности разбирать старые сбои.", "Deleting a build and its symbols may prevent diagnosing old crashes."), recovery: t("Только из сохранённой копии или карантина, если выбран. Прямое удаление необратимо.", "Only from a retained backup or quarantine, if selected. Direct deletion is irreversible."))
    case "derived": return .init(owner: "Xcode / DerivedData", consequence: t("Следующая сборка и индексация могут занять больше времени.", "The next build and indexing may take longer."), recovery: t("Xcode пересоздаёт кэш; удалённые логи не восстанавливаются.", "Xcode regenerates caches; deleted logs are not restored."))
    case "simulators", "testSimulators": return .init(owner: section == "testSimulators" ? "Xcode / XCTestDevices" : "Xcode / CoreSimulator", consequence: t("Удаление устройства уничтожает установленные приложения и тестовые данные.", "Removing a device destroys installed apps and test data."), recovery: t("Устройство можно создать заново. Данные — только из отдельной копии; runtime доступен для загрузки не всегда.", "A device can be recreated. Data requires a separate backup; a runtime may no longer be downloadable."))
    case "worktrees": return .init(owner: "Git", consequence: t("Удаляется дополнительная рабочая папка. Основной checkout и ветка сохраняются.", "Removes a linked working directory. The main checkout and branch are preserved."), recovery: t("Создать worktree заново из сохранённой ветки. Задачи агентов нужно предварительно завершить.", "Recreate the worktree from the retained branch. Finish associated agent tasks first."))
    case "projectData": return .init(owner: t("Выбранный проект; точный маркер в разделе", "Selected project; see its exact marker in the section"), consequence: t("Удаление поддержанного кэша замедлит следующую сборку. Зависимости доступны только для просмотра.", "Removing a supported cache slows the next build. Dependencies are review-only."), recovery: t("По правилу конкретного проекта. Команды восстановления автоматически не запускаются.", "Follow the specific project rule. Recovery commands are not run automatically."))
    case "duplicates", "personal": return .init(owner: t("Личные файлы; приложение-владелец не определено", "Personal files; owning application unknown"), consequence: t("Файл исчезнет из прежней папки. Ссылки на этот путь могут перестать работать.", "The file leaves its original folder. References to that path may stop working."), recovery: t("Из карантина до окончательного удаления. Карантин продолжает занимать место.", "Restore from quarantine before permanent deletion. Quarantine still occupies disk space."))
    default: return .init(owner: t("Не определён", "Unknown"), consequence: t("Последствия не определены: только просмотр.", "Consequences unknown: review only."), recovery: t("Восстановление не подтверждено.", "Recovery has not been verified."))
    }
  }
}
