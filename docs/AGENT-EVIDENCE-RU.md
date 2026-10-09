# Матрица проверенных форматов — 0.4.14

Поддержка определяется структурой файла, а не названием установленной версии. Версия программы, создавшей историю, в проверенных фикстурах не зафиксирована: не заявляем поддержку всех её релизов. Тесты ниже выполняются через `swift test` в CI.

| Агент | Проверенный формат | Доказательство |
|---|---|---|
| Codex | JSONL: session_meta + response_item/message; неизвестные записи сохраняются | NativeHistoryTests |
| Claude Code | JSONL: sessionId, user/assistant, message; ветки и инструменты сохраняются | NativeHistoryTests |
| Cursor | JSONL: role + message.content, метаданные turn_ended | CursorTurnTests; локальные истории пользователя |
| Gemini CLI | JSON messages; JSONL с sessionId/$set без применения патчей | NextMilestoneTests |
| Continue | JSON history/message | NextMilestoneTests |
| Cline | api_conversation_history.json, массив role/content | NextMilestoneTests |
| Roo Code | api_conversation_history.json, массив role/content | NextMilestoneTests |
| OpenCode | JSON export с сообщениями и parts одной сессии | ResilienceMilestoneTests |
| Aider | Markdown с единственным маркером начала сессии | CompletionMilestoneTests |
| GitHub Copilot, Windsurf | Универсальный текстовый экспорт; нативной базы нет | Общий Transcript.load, ограничения UTF-8/размера/расширения |

Для всех: исходник не переписывается. Нативные JSONL — до 1 GB; JSON/Markdown и универсальный импорт — до 30 MB. Неизвестная структура отклоняется. Открытая база IDE не редактируется; новый чат пользователь создаёт самостоятельно.

## Как расширять поддержку

1. Записать версию производителя и способ экспорта.
2. Сохранить обезличенный минимальный пример, сохранив неизвестные поля, роли, ветки и инструменты.
3. Добавить проверки отказа для смешанных сессий и повреждённых записей.
4. Проверить неизменность исходника и точность резервной копии.
5. Отдельно оценить смысл итогового контекста; успешный импорт не доказывает качественный пересказ.

Истории пользователя и результаты локальной модели не включаются в публичный репозиторий.
