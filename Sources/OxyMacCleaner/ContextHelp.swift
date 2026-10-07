import SwiftUI

/// Action help shared by hover tooltips, VoiceOver and the section guide.
enum HelpTopic {
  case worktrees, symbols, backupOption, derivedDelete, backup, archiveDelete, archiveBatch, archiveQuarantine,
    retention, pin, archiveRead,
    archiveRoot,
    beyondFilter, search, previous, next, finder, stop, volume, refreshVolumes, scan, folder,
    access, category, size, age, quarantine, protect, duplicates, selectDuplicate, developerTab,
    simRead, simDelete, simUnavailable, clearSelection, simOld, selectDevice, selectRuntime,
    derivedRead, derivedQuarantine, selectDerived, agent, agentSize, importSession, summaryStyle,
    summarize, engine, copy, export, editor, installEngine, launchEngine, checkEngine, pull, model,
    notify, recover, eraseArchives, restore, restoreElsewhere, erase, theme, language,
    removeExclusion, releases, advisor, rule, review, duplicatesPage, up, mapRoot, mapNode,
    categories, categoryFiles, openSettings, recheck, accessDone, report, disclosure, help

  var text: (ru: String, en: String) {
    switch self {
    case .worktrees:
      return ("Выберите репозиторий. Проверяются дополнительные рабочие деревья: локальные и ignored-файлы, коммиты, блокировки и открытые файлы. Для удаления нужно 30 дней без изменений и подтверждение завершения задач. Ветки сохраняются; --force не используется.", "Choose a repository. Linked worktrees are checked for local/ignored files, commits, locks and open files. Removal requires 30 days without changes and confirmation that tasks are finished. Branches remain; --force is never used.")
    case .backupOption:
      return (
        "По желанию сохраняет полную проверенную копию перед удалением. Если копию создать не удастся, этот архив не удаляется. Для экономии места выберите другой диск.",
        "Optionally saves a verified full backup before deletion. If backup fails, that archive is skipped. Choose another disk to reclaim space."
      )
    case .derivedDelete:
      return (
        "Удаляет выбранные кэши после одного подтверждения, без карантина и Корзины. Индекс и промежуточные файлы пересоздаются; старые логи теряются. Закройте Xcode и сборки.",
        "Deletes selected caches after one confirmation, without quarantine or Trash. Indexes and intermediates are rebuilt; old logs are lost. Close Xcode and builds."
      )
    case .symbols:
      return (
        "Сравнивает UUID — идентификаторы сборок — и архитектуры приложения и его dSYM. dSYM помогает расшифровать отчёт о сбое. Файлы не меняются; полноту отладочной информации эта проверка не доказывает.",
        "Compares build identifiers (UUIDs) and CPU architectures in the app and its dSYMs. A dSYM helps decode crash reports. Files are unchanged; this does not verify completeness of debug information."
      )
    case .backup:
      return (
        "Сохраняет весь архив .xcarchive в выбранную папку и проверяет копию по SHA-256. Оригинал остаётся на месте. Копия занимает дополнительное место; для экономии на этом диске выберите другой диск.",
        "Copies the entire .xcarchive to a folder you choose and verifies it using SHA-256. The original stays in place. The copy needs extra space; choose another disk to save space on this one."
      )
    case .archiveDelete:
      return (
        "Удаляет все архивы сверх лимита после одного подтверждения, включая скрытые фильтром. Копия — по флажку; без копии восстановить из приложения нельзя. «Не удалять», активные сборки и изменения файлов защищены.",
        "Deletes all archives beyond the limit after one confirmation, including filtered-out items. Backup is optional; without one, in-app recovery is impossible. Protected archives, active builds and changed files are blocked."
      )
    case .archiveBatch:
      return (
        "Переносит все архивы сверх лимита в карантин после подтверждения. Отдельная копия и проверка UUID не нужны. Можно восстановить, но место пока не освобождается.",
        "Quarantines all archives beyond the limit after confirmation. No separate backup or UUID check is needed. Restorable, but space is not freed yet."
      )
    case .archiveQuarantine:
      return (
        "Переносит этот архив сверх лимита в карантин после подтверждения. Отдельная копия не нужна. Можно восстановить из раздела «Карантин».",
        "Quarantines this archive beyond the limit after confirmation. No separate backup is required. Restore it from Quarantine."
      )
    case .retention:
      return (
        "Количество последних архивов для каждого сочетания Bundle ID и команды. «Не удалять» сохраняет дополнительные архивы сверх этого лимита. Изменение числа само ничего не удаляет.",
        "Number of latest archives retained per Bundle ID and team. Keep protected retains additional archives. Changing this number does not delete anything."
      )
    case .pin:
      return (
        "Защищает этот архив от очистки в приложении независимо от лимита. Снятие флажка только отменяет защиту и ничего не удаляет.",
        "Protects this archive from cleanup in this app regardless of the limit. Unchecking only removes protection; it does not delete anything."
      )
    case .archiveRead:
      return (
        "Читает метаданные и размеры архивов Xcode из выбранной папки. Проверка символов и создание резервной копии выполняются отдельно.",
        "Reads Xcode archive metadata and sizes from the selected folder. Symbol checks and backups are separate actions."
      )
    case .archiveRoot:
      return (
        "Выберите папку с архивами .xcarchive, если они хранятся вне стандартной папки Xcode.",
        "Choose a folder containing .xcarchive bundles stored outside the default Xcode archive folder."
      )
    case .beyondFilter:
      return (
        "Показывает только кандидатов сверх лимита. Это не означает, что их можно безопасно удалить. Общая кнопка очистки обрабатывает весь список сверх лимита.",
        "Shows only archives beyond the retention limit, not a list guaranteed safe to delete. The batch action processes all archives beyond the limit."
      )
    case .search:
      return (
        "Фильтрует загруженный список по указанным в поле признакам. Новый обход диска не запускается.",
        "Filters the loaded list using the fields named in the search box. Does not start a new disk scan."
      )
    case .previous:
      return (
        "Показывает предыдущие 10 записей текущего списка.",
        "Shows the previous 10 entries in this list."
      )
    case .next:
      return (
        "Показывает следующие 10 записей текущего списка.",
        "Shows the next 10 entries in this list."
      )
    case .finder:
      return (
        "Показывает расположение объекта в Finder, не перемещая и не удаляя его.",
        "Reveals the item in Finder without moving or deleting it."
      )
    case .stop:
      return (
        "Запрашивает остановку текущей операции. Некоторые команды и копирование завершаются прежде, чем остановится очередь. Частичный результат сканирования сохраняется.",
        "Requests cancellation. Some commands and copies finish before the queue stops. A partial scan result is retained."
      )
    case .volume:
      return (
        "Выбирает диск для следующего сканирования. Сам выбор не запускает обход.",
        "Selects the disk for the next scan. Selecting it does not start scanning."
      )
    case .refreshVolumes:
      return (
        "Обновляет список подключённых дисков и сведения о свободном месте.",
        "Refreshes connected disks and available space information."
      )
    case .scan:
      return (
        "Обходит доступные файлы выбранного диска или папки без удаления. Недоступные пути попадут в отчёт. Новый снимок заменит предыдущий результат анализа.",
        "Scans accessible files on the selected disk or folder without deleting anything. Inaccessible paths are reported. The new snapshot replaces the previous analysis."
      )
    case .folder:
      return (
        "Позволяет ограничить следующий обход отдельной папкой вместо всего диска.",
        "Limits the next scan to a specific folder instead of the entire disk."
      )
    case .access:
      return (
        "Показывает результат проверки защищённых папок и инструкции macOS. Успешная проверка не гарантирует доступ ко всем файлам.",
        "Shows protected-folder access checks and macOS instructions. A successful check does not guarantee access to every file."
      )
    case .category:
      return (
        "Фильтрует файлы текущего снимка по типу. Категория определяется путём и расширением, а не содержимым файла.",
        "Filters the current snapshot by file type, inferred from paths and extensions rather than file contents."
      )
    case .size:
      return (
        "Оставляет в списке файлы не меньше выбранного размера. Размер логический; освобождённое место может отличаться.",
        "Shows files at least as large as the selected size. This is logical size; reclaimed disk space may differ."
      )
    case .age:
      return (
        "Фильтрует по дате изменения. Старый файл мог недавно использоваться и всё ещё быть нужен.",
        "Filters by modification date. An old file may have been used recently and may still be needed."
      )
    case .quarantine:
      return (
        "После проверки и подтверждения переносит выбранные объекты в карантин на том же томе. Их можно восстановить; место пока не освобождается. Защищённые объекты блокируются.",
        "After validation and confirmation, moves selected items to quarantine on the same volume. They can be restored and still occupy space. Protected items are blocked."
      )
    case .protect:
      return (
        "Исключает этот путь из последующих сканирований и очистки. Управлять исключениями можно в настройках. Сам файл не меняется.",
        "Excludes this path from subsequent scans and cleanup. Manage exclusions in Settings. The file itself is unchanged."
      )
    case .duplicates:
      return (
        "Ищет точные копии файлов текущего снимка по размеру, хешу и содержимому. При переносе сохраняется хотя бы одна копия. Ничего не удаляет автоматически.",
        "Finds exact duplicates in the current snapshot by size, hash and contents. At least one copy is retained during transfer. Nothing is deleted automatically."
      )
    case .selectDuplicate:
      return (
        "Отмечает эту копию для переноса в карантин. Проверьте путь; хотя бы одна копия группы должна остаться.",
        "Selects this copy for quarantine. Review its path; at least one copy in the group must remain."
      )
    case .developerTab:
      return (
        "Переключает независимые инструменты: архивы приложений, кэши проектов и симуляторы. Для каждого нужно отдельно загрузить список.",
        "Switches between app archives, project caches and simulators. Load the inventory separately in each tool."
      )
    case .simRead:
      return (
        "Запрашивает актуальные устройства и версии ОС у Xcode через simctl. Данные не удаляются.",
        "Reads current devices and OS runtimes from Xcode using simctl. Nothing is deleted."
      )
    case .simDelete:
      return (
        "После подтверждения удаляет выбранные устройства и runtimes через Xcode, без карантина. Данные приложений на устройствах будут потеряны. Закройте Xcode и остановите сборки; запущенные устройства защищены.",
        "After confirmation, deletes selected devices and runtimes through Xcode without quarantine. Device app data is lost. Close Xcode and stop builds; running devices are protected."
      )
    case .simUnavailable:
      return (
        "Отмечает остановленные устройства, для которых версия ОС недоступна. Только меняет выбор — проверьте его перед удалением.",
        "Selects stopped devices whose OS runtime is unavailable. Only changes selection; review before deleting."
      )
    case .clearSelection:
      return (
        "Снимает отметки со всех устройств и runtimes. Ничего не удаляет.",
        "Clears all device and runtime selections without deleting anything."
      )
    case .simOld:
      return (
        "Отмечает доступные для удаления runtimes, не использовавшиеся минимум 90 дней по данным Xcode. Возраст не означает ненужность.",
        "Selects removable runtimes unused for at least 90 days according to Xcode. Age alone does not mean they are unnecessary."
      )
    case .selectDevice:
      return (
        "Выбирает виртуальное устройство для удаления вместе с его приложениями и тестовыми данными. Сейчас ничего не удаляется. Запущенные устройства выбрать нельзя.",
        "Selects a virtual device for deletion with its apps and test data. Nothing is deleted yet. Running devices cannot be selected."
      )
    case .selectRuntime:
      return (
        "Выбирает общую версию ОС для удаления. Связанные устройства останутся без этой ОС. Повторная загрузка возможна, только если версия доступна у Apple.",
        "Selects a shared OS runtime for deletion. Related devices will lose access to this OS. Re-download is possible only if Apple still provides it."
      )
    case .derivedRead:
      return (
        "Ищет промежуточные сборки, индекс и логи проектов в стандартной папке DerivedData. Пользовательские пути и общие кэши пока не включены.",
        "Finds project build intermediates, indexes and logs in the default DerivedData folder. Custom locations and shared caches are not included yet."
      )
    case .derivedQuarantine:
      return (
        "Проверяет активность сборок и переносит выбранные кэши в карантин. Закройте Xcode; изменения за последние 10 минут блокируют перенос. Следующая сборка и индексирование будут дольше.",
        "Checks build activity and quarantines selected caches. Close Xcode; changes within the last 10 minutes block transfer. The next build and indexing will take longer."
      )
    case .selectDerived:
      return (
        "Отмечает кэш для выбранного действия: очистки или карантина. Исходники и готовые продукты не выбираются.",
        "Selects a cache for cleanup or quarantine. Sources and built products are excluded."
      )
    case .agent:
      return (
        "Выберите агента, чей экспорт сессии будете обрабатывать. При смене агента текущий импорт и результат очищаются из окна; сначала сохраните нужный результат.",
        "Choose the agent whose session export you will process. Switching clears the current import and result from the window; save any needed result first."
      )
    case .agentSize:
      return (
        "Сканирует найденную папку агента и открывает список файлов. Истории не сжимаются и базы данных не меняются.",
        "Scans the discovered agent folder and opens its file list. Does not summarize histories or modify databases."
      )
    case .importSession:
      return (
        "Открывает один экспорт TXT, MD, JSON или JSONL. Не читает внутреннюю базу агента и не объединяет разные сессии.",
        "Opens one TXT, MD, JSON or JSONL export. Does not read the agent’s internal database or merge sessions."
      )
    case .summaryStyle:
      return (
        "Задаёт подробность инструкции локальной модели: бережный, сбалансированный или краткий пересказ. Результат всё равно требует проверки.",
        "Sets the local model’s requested detail level: careful, balanced or concise. The result still needs review."
      )
    case .summarize:
      return (
        "Сохраняет проверенную копию исходника и обрабатывает сессию локальной моделью. Нужна запущенная Ollama и выбранная модель. Результат не заменяет историю агента.",
        "Retains a verified source backup and processes the session with a local model. Requires running Ollama and a selected model. The result does not replace agent history."
      )
    case .engine:
      return (
        "Открывает установку Ollama и выбор локальной модели для подготовки контекста.",
        "Opens Ollama setup and local model selection for preparing context."
      )
    case .copy:
      return (
        "Копирует текущий отредактированный результат в буфер обмена для вставки в новый чат.",
        "Copies the current edited result to the clipboard for pasting into a new chat."
      )
    case .export:
      return (
        "Сохраняет текущий результат в отдельный Markdown-файл. История исходного агента остаётся прежней.",
        "Saves the current result as a separate Markdown file. The original agent history is unchanged."
      )
    case .editor:
      return (
        "Можно исправить пересказ перед копированием или экспортом. Проверьте решения, ограничения и следующие шаги: модель может пропустить детали.",
        "Edit the summary before copying or exporting. Check decisions, constraints and next steps: the model may omit details."
      )
    case .installEngine:
      return (
        "Скачивает Ollama с официального источника и проверяет загрузку перед установкой. Нужны интернет и место на диске; модели скачиваются отдельно.",
        "Downloads Ollama from its official source and validates it before installation. Requires internet and disk space; models are downloaded separately."
      )
    case .launchEngine:
      return (
        "Запускает установленное приложение Ollama. После запуска нажмите «Обновить модели», чтобы обновить список локальных моделей.",
        "Launches the installed Ollama app. Then use Refresh models to refresh available local models."
      )
    case .checkEngine:
      return (
        "Проверяет подключение к локальной Ollama и перечитывает список установленных моделей. Ничего не скачивает.",
        "Checks the local Ollama connection and refreshes installed models without downloading anything."
      )
    case .pull:
      return (
        "Скачивает эту модель через Ollama. Нужны интернет, свободное место и работающий движок. Обработка контекста затем выполняется локально.",
        "Downloads this model through Ollama. Requires internet, disk space and a running engine. Context processing then runs locally."
      )
    case .model:
      return (
        "Выбирает уже установленную локальную модель. Большие модели обычно требуют больше памяти. Облачные модели не предлагаются.",
        "Selects an installed local model. Larger models generally need more memory. Cloud models are not offered."
      )
    case .notify:
      return (
        "Запрашивает разрешение на уведомления и включает напоминания о карантине каждые 5 дней. Автоматического удаления нет.",
        "Requests notification permission and enables quarantine reminders every 5 days. Does not enable automatic deletion."
      )
    case .recover:
      return (
        "Сверяет журнал карантина с файлами после прерывания операции. Спорные состояния отмечаются для проверки; это не команда окончательного удаления.",
        "Reconciles the quarantine journal with files after interrupted operations. Ambiguous states are flagged for review; this is not permanent deletion."
      )
    case .eraseArchives:
      return (
        "Безвозвратно удаляет архивы из карантина после подтверждения. Если при переносе была указана копия, проверяет её. Восстановление из карантина станет невозможно.",
        "Permanently deletes quarantined archives after confirmation. Checks any backup specified during transfer. In-app restoration will no longer be available."
      )
    case .restore:
      return (
        "Возвращает объект на исходное место. При конфликте имён не перезаписывает существующие данные — используйте «Вернуть в…».",
        "Restores the item to its original location. Never overwrites existing data; use Restore to… if the destination conflicts."
      )
    case .restoreElsewhere:
      return (
        "Позволяет выбрать другое место на том же диске, если исходный путь занят или недоступен. Существующие файлы не перезаписываются.",
        "Lets you choose another restore destination on the same disk if the original is occupied or unavailable. Existing files are not overwritten."
      )
    case .erase:
      return (
        "Безвозвратно удаляет этот объект из карантина после подтверждения. Восстановление из приложения станет невозможно.",
        "Permanently deletes this quarantined item after confirmation. It can no longer be restored through the app."
      )
    case .theme:
      return (
        "Системное оформление следует настройке macOS. Светлая и тёмная темы фиксируют выбранный вид приложения.",
        "System appearance follows macOS. Light and dark fix the app to the selected appearance."
      )
    case .language:
      return (
        "Переключает язык интерфейса и подсказок. Не переводит имена файлов и содержимое сессий.",
        "Changes interface and help language. Does not translate file names or session contents."
      )
    case .removeExclusion:
      return (
        "Убирает путь из исключений. Он снова сможет участвовать в последующих сканированиях и проверках очистки. Файлы не удаляются.",
        "Removes this path from exclusions so future scans and cleanup checks can consider it again. No files are deleted."
      )
    case .releases:
      return (
        "Открывает страницу готовых сборок в браузере. Эта версия не устанавливает обновление автоматически.",
        "Opens the release download page in your browser. This version does not install updates automatically."
      )
    case .advisor:
      return (
        "Обновить по снимку пересчитывает личные файлы. Обновить сводку также читает архивы Xcode, DerivedData и симуляторы. Дубликаты проверяются отдельно. Действия ничего не удаляют.",
        "Refresh from snapshot recalculates personal files. Refresh summary also reads Xcode archives, DerivedData and simulators. Duplicates are checked separately. Neither action deletes anything."
      )
    case .rule:
      return (
        "Фильтрует предложения: старые установщики в «Загрузках» или крупные давно не изменявшиеся личные файлы. Это кандидаты для просмотра, не доказанный мусор.",
        "Filters suggestions to old installers in Downloads or large, long-unmodified personal files. These are review candidates, not proven junk."
      )
    case .review:
      return (
        "Проверяет, что кандидат не изменился после сканирования, и показывает его в Finder. Ничего не удаляет.",
        "Checks that the candidate has not changed since scanning and reveals it in Finder. Does not delete anything."
      )
    case .duplicatesPage:
      return (
        "Открывает поиск точных копий. Запустите проверку в этом разделе и просмотрите пути перед выбором.",
        "Opens exact duplicate search. Run the check there and review paths before selecting copies."
      )
    case .up:
      return (
        "Переходит к родительской папке в сохранённой карте. Не запускает новый обход диска.",
        "Moves to the parent folder in the saved map without rescanning."
      )
    case .mapRoot:
      return (
        "Возвращает карту к выбранному корню сканирования.",
        "Returns the map to the selected scan root."
      )
    case .mapNode:
      return (
        "Нажмите папку, чтобы увидеть её состав; файл — чтобы показать его в Finder. Размеры взяты из снимка и могут устареть.",
        "Click a folder to explore its contents or a file to reveal it in Finder. Snapshot sizes may be outdated."
      )
    case .categories:
      return (
        "Показывает все категории найденного объёма. Полоса отражает состав данных, а не процент завершения сканирования.",
        "Shows all categories of discovered data. The bar represents data composition, not scan completion percentage."
      )
    case .categoryFiles:
      return (
        "Открывает найденные файлы этой категории. Кнопка доступна после остановки или завершения сканирования.",
        "Opens discovered files in this category. Available after scanning stops or finishes."
      )
    case .openSettings:
      return (
        "Открывает раздел полного доступа к диску в macOS. Разрешение включает пользователь; приложение не может выдать его себе.",
        "Opens macOS Full Disk Access settings. The user grants permission; the app cannot grant it to itself."
      )
    case .recheck:
      return (
        "Повторно проверяет доступ к трём защищённым папкам, не читая содержимое. Не меняет системное разрешение. После его выдачи может потребоваться перезапуск.",
        "Rechecks access to three protected folders without reading contents. Does not change permission. A restart may be needed after granting access."
      )
    case .accessDone:
      return (
        "Закрывает это окно. Если вы пришли сюда при запуске сканирования, продолжает обход доступных файлов; отказы появятся в отчёте.",
        "Closes this window. If opened while starting a scan, proceeds with accessible files; access failures appear in the report."
      )
    case .report:
      return (
        "Раскрывает подробности последней операции: что выполнено, пропущено или завершилось ошибкой.",
        "Expands the last operation’s details: completed, skipped and failed items."
      )
    case .disclosure:
      return (
        "Разворачивает подробности этого блока. Повторное нажатие скрывает их.",
        "Expands this section’s details. Click again to collapse."
      )
    case .help:
      return (
        "Открывает краткую инструкцию для текущего раздела. Подсказки отдельных действий доступны при наведении курсора.",
        "Opens a short guide for this section. Hover over individual controls for action-specific tips."
      )
    }
  }
}

private struct OxyHelpModifier: ViewModifier {
  @EnvironmentObject var vm: AppModel
  let topic: HelpTopic
  func body(content: Content) -> some View {
    let message = vm.t(topic.text.ru, topic.text.en)
    content.help(message).accessibilityHint(message)
  }
}

extension View {
  func oxyHelp(_ topic: HelpTopic) -> some View { modifier(OxyHelpModifier(topic: topic)) }
}

struct SectionHelpView: View {
  @EnvironmentObject var vm: AppModel
  @Environment(\.dismiss) private var dismiss
  let page: String
  let developerSection: String
  private var topics: [(String, String, HelpTopic)] {
    switch page {
    case "overview":
      return [
        ("1. Выберите диск", "1. Choose a disk", .volume),
        ("2. Запустите сканирование", "2. Start scanning", .scan),
        ("Доступ macOS", "macOS access", .access),
        ("Что означает полоса", "What the bar means", .categories),
      ]
    case "advisor":
      return [
        ("На чём основаны предложения", "How suggestions work", .rule),
        ("Обновление анализа", "Refresh analysis", .advisor),
        ("Сначала просмотрите файл", "Review the file first", .review),
        ("Исключения", "Exclusions", .protect),
      ]
    case "map":
      return [
        ("Навигация по карте", "Explore the map", .mapNode),
        ("Вернуться к началу", "Return to the root", .mapRoot),
        ("Перенос папки", "Moving a folder", .quarantine),
      ]
    case "files", "archives":
      return [
        ("Найдите нужные объекты", "Find items", .search),
        ("Размер и экономия", "Size and reclaimed space", .size),
        ("Возраст — не последнее использование", "Age is not last use", .age),
        ("Выберите строки и перенесите", "Select rows and move", .quarantine),
        ("Защита через контекстное меню", "Protect via the context menu", .protect),
      ]
    case "duplicates":
      return [
        ("1. Найдите точные копии", "1. Find exact duplicates", .duplicates),
        (
          "2. Проверьте пути и отметьте копии", "2. Review paths and select copies",
          .selectDuplicate
        ), ("3. Перенесите выбранное", "3. Move selected items", .quarantine),
      ]
    case "developer":
      switch developerSection {
      case "worktrees":
        return [("Проверка и удаление рабочих деревьев", "Inspecting and removing worktrees", .worktrees)]
      case "derived":
        return [
          ("1. Прочитайте список кэшей", "1. Read project caches", .derivedRead),
          ("2. Выберите нужное", "2. Select caches", .selectDerived),
          (
            "3. Очистите выбранные кэши", "3. Clean selected caches",
            .derivedDelete
          ),
        ]
      case "simulators":
        return [
          ("1. Обновите список", "1. Refresh inventory", .simRead),
          ("Устройство и его данные", "Device and its data", .selectDevice),
          ("Runtime — общая версия ОС", "Runtime — a shared OS version", .selectRuntime),
          ("2. Проверьте выбор и удалите", "2. Review selection and delete", .simDelete),
        ]
      default:
        return [
          ("1. Задайте лимит и защиту", "1. Set retention and protection", .retention),
          ("Символы отладки: dSYM и UUID", "Debug symbols: dSYM and UUID", .symbols),
          ("Копия — по желанию", "Backup is optional", .backupOption),
          ("2. Удалите сверх лимита", "2. Delete beyond the limit", .archiveDelete),
          ("Альтернатива: карантин", "Alternative: quarantine", .archiveBatch),
          ("Если выбрали карантин", "If you chose quarantine", .eraseArchives),
        ]
      }
    case "agents":
      return [
        ("1. Выберите агента и экспорт", "1. Choose an agent and export", .importSession),
        ("2. Подготовьте контекст локально", "2. Prepare context locally", .summarize),
        ("3. Проверьте результат", "3. Review the result", .editor),
        ("4. Перенесите в новый чат", "4. Move to a new chat", .copy),
      ]
    case "engine":
      return [
        ("1. Установите движок", "1. Install the engine", .installEngine),
        ("2. Запустите и проверьте", "2. Launch and check", .launchEngine),
        ("3. Скачайте модель", "3. Download a model", .pull),
        ("4. Выберите установленную модель", "4. Select an installed model", .model),
      ]
    case "quarantine":
      return [
        ("Карантин ещё занимает место", "Quarantine still occupies space", .quarantine),
        ("Вернуть объект", "Restore an item", .restore),
        ("Удалить окончательно", "Delete permanently", .erase),
        ("Прерванные операции", "Interrupted operations", .recover),
        ("Напоминания", "Reminders", .notify),
      ]
    case "history":
      return [("Если операция была прервана", "If an operation was interrupted", .recover)]
    default:
      return [
        ("Оформление", "Appearance", .theme), ("Язык", "Language", .language),
        ("Исключения", "Exclusions", .removeExclusion),
        ("Разрешения macOS", "macOS permissions", .access), ("Обновления", "Updates", .releases),
      ]
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label(vm.t("Как пользоваться", "How to use"), systemImage: "questionmark.circle").font(
          .title2.bold())
        Spacer()
        Button(vm.t("Готово", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          ForEach(Array(topics.enumerated()), id: \.offset) { _, item in
            VStack(alignment: .leading, spacing: 5) {
              Text(vm.t(item.0, item.1)).font(.headline)
              Text(vm.t(item.2.text.ru, item.2.text.en)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxHeight: 480)
      Text(
        vm.t(
          "Наведите курсор на кнопку или настройку, чтобы узнать подробности действия.",
          "Hover over a control to learn what it does.")
      )
      .font(.caption).foregroundStyle(.secondary)
    }.padding(22).frame(width: 490)
  }
}
