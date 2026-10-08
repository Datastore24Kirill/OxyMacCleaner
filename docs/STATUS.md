# Implementation status — 0.4.0 Preview

This is an implementation milestone, not completion of the version-one specification. Historical release notes describe their release, not current capabilities.

| Area | Implemented | Remaining |
|---|---|---|
| UI | RU/EN interface, themes, contextual hints | Complete accessibility and error localization audit |
| Disk analysis | Disk/folder scans, cancellation, exclusions, streamed snapshots, partial crash recovery, map/categories; 1M-file fixture | Exact traversal resume, broader disk benchmarks |
| Duplicates | Hash + byte comparison, keeper validation, unique-inode logical/allocated estimates | Exact APFS reclaim is unknown; performance |
| Xcode archives | Retention, pins, optional backup/quarantine, direct delete, dSYM diagnostics | Broader race/failure verification |
| DerivedData / projects | Bounded project discovery, project mapping, cache allowlist, dependencies inventory, guarded worktree cleanup | Broader project-marker and dependency-manager coverage |
| Simulators | Standard/test devices, runtimes, activity guards, select available Shutdown devices matching search | Broader runtime-version QA |
| Quarantine | Same-volume initial quarantine, verified cross-volume relocation/restore, journal recovery, retained-copy inspection/revalidation, five-day reminder | Broader fault injection; old relocation copies require manual review |
| Agents | 11 discovery hints; exports; eight native file adapters and catalogs; two handoff actions | Other versioned native adapters; new chat remains manual |
| Context | Local 7B available; full-history paging/search, review markers, secret-pattern filtering, cited source excerpts; original and verified backup retained | Broader semantic benchmarks, cross-chunk conflict resolution; no lossless-summary claim |
| Updates | Download/progress, integrity checks, install, launch handshake and rollback | Developer ID, permission continuity, full permission continuity; older backups are managed explicitly |
| Permissions | In-process diagnostics, ad-hoc builds | Stable Developer ID signing deferred |

## Next work

1. Broader semantic conflict detection and real-history quality cases. Current review markers only flag selected words on the visible page; they do not resolve contradictory requirements.
2. Full real VoiceOver, keyboard-focus and RU/EN failure-message audit; current additions have accessible labels and cancellation.
3. More native agent formats, exact traversal resume and broader disk/failure benchmarks. APFS shared-block ownership remains unknown.
4. Developer ID signing remains deferred. No permission continuity claim for ad-hoc builds.

## Agent capability matrix

All 11 agents support **explicit text-export import**. Since 0.1.19, Codex and Claude Code also support selected native JSONL files (see AGENT-ADAPTERS-RU.md); metadata-only Codex/Claude session discovery is implemented since 0.1.20. The catalog identifies known default locations when present; absence does not mean an agent is not installed. Installation variants and IDE profiles need separate validation.

| Agent | Discovery hint | Import TXT/MD/JSON/JSONL | Rewrite existing chat | Automatic new chat |
|---|---|---|---|---|
| Codex | Yes; selected native JSONL supported since 0.1.19 | Yes | No | No |
| Claude Code | Yes; selected native JSONL supported since 0.1.19 | Yes | No | No |
| Cursor | Yes; file JSONL supported since 0.2.0 | Yes | No | No |
| GitHub Copilot | VS Code default | Yes | No | No |
| Gemini CLI | Yes | Yes | No | No |
| Windsurf | Yes | Yes | No | No |
| Cline | VS Code default | Yes | No | No |
| Roo Code | VS Code default | Yes | No | No |
| Aider | Home and selected-project hint; single-session Markdown reader | Yes | No | No |
| Continue | Yes | Yes | No | No |
| OpenCode | Yes | Yes | No | No |

## Verification

- Core tests cover scan cancellation/exclusion, symlink loops, hard links, exact duplicates, stale-file rejection, protection rules, quarantine restore conflicts, corrupt payload refusal, deletion of test fixtures, reminder timing, transcript backup and complete chunk coverage.
- Ollama protocol tests cover local-only selection, metadata validation before sending a prompt and empty-output rejection. These use a mocked protocol and are not proof of model quality.
- Local packaged UI: launched, manually scanned synthetic files and detected the expected duplicate pair.
- No user files or histories were cleaned during implementation.

## Historical milestones

The following sections record earlier releases; use the current table above for remaining work.

## 0.1.1 update

Approved neon logo is now used by the packaged app, sidebar and README. Startup-disk selection is the default, with local mounted-volume discovery, usage bar and optional folder selection. The startup namespace skips `/System/Volumes`, `/Volumes`, `/dev` and other nested mounts to avoid duplicate traversal. Volume capacity is reported by macOS and may be shared in an APFS container. No whole-disk user-data scan was run during implementation; selection and boundary policy were tested without cleaning data.

## 0.1.2 update

Icon Composer asset and compiled Assets.car remove legacy icon framing. Scan progress uses throttled real filesystem snapshots, terminal snapshots are always emitted, and stale UI callbacks cannot overwrite completion. Animated radar honours Reduce Motion; byte composition is explicitly distinct from completion percentage. 21 tests pass locally; live scan and cancellation checked in the installed app.

## 0.1.3 update

Added a disk-access guide on first launch and each new version, read-only in-process directory probes with limited/available/unconfirmed outcomes, recheck on app activation, and exact-copy recovery guidance. No TCC mutation or automatic permission grant. Distribution remains ad-hoc signed; permission continuity is unresolved until a stable signing identity is used. Package script accepts OXYMAC_SIGNING_IDENTITY for future Developer ID builds without weakening designated requirements. 25 local tests pass.

## 0.1.4 update

15 path/extension-based categories with container precedence (known game libraries, app bundles, caches, app data and development outputs). Top-five size legend with remainder and full category breakdown, localized labels and file filter. 28 tests pass including container precedence, uppercase extensions and fallback classification. No content-based photo detection or exhaustive game catalog is claimed. Version 0.1.4 installed locally; access guide verified in the running app and correctly reports restricted access. No permission granted automatically.

## 0.1.5 update

Successful disk-access checks now show a compact confirmation without recovery controls. Startup and scan skip the guide when access probes succeed. Restricted and unknown states retain recovery instructions. 28 local tests passed. Installed 0.1.5; macOS denied protected-directory access after replacing the ad-hoc signed app, so success UI is not claimed as manually validated with renewed permission.

## 0.1.6 update

Atomic local binary-plist snapshots preserve completed and cancelled scan reports, roots, progress and timestamp. Snapshot permissions are 0600 under a 0700 directory. Restored files retain original identities for pre-action revalidation. Disk index and persistence execute outside the main actor. Added proportional treemap and immediate-child navigation without nested double counting, plus size and modification-age filters. 32 tests pass, including snapshot round-trip/corruption/privacy, stale-file validation and map area/boundary checks. Installed UI verified with synthetic fixture, folder navigation and relaunch restoring the same result. Intelligent cleanup remains a documented roadmap in SMART-CLEANUP-PLAN-RU.md; directory quarantine remains next.

## 0.1.7 update

Ordinary-directory quarantine via disk-map list context menu. Tree manifests include empty directories, content hashes and identity metadata; protected descendants, exclusions, Git projects, links, cloud data and broad user/system roots are blocked. Same-volume exclusive rename; post-move verification; directory restore and alternate destination; journal reconciliation for prepared/restoring operations. Recovery tests simulate interrupted journal commits after transfer/restore. No automatic active-process detection or cross-volume directory transfer is claimed. 41 local tests pass. User scan remains running in 0.1.6; local update is deferred until it completes.

## 0.1.8 update

Review-only cleanup advisor with two deterministic local rules: old installers in the user's Downloads (90 days), and large unmodified files in personal folders (500 MB, 180 days). Protected data, known dependencies, app/photo-library packages and hard links are excluded; overlapping rules emit one candidate. Refresh runs off the main actor with generation guards. Candidate reveal validates original file identity; exclusions persist. 45 tests pass locally, including threshold boundaries, rule precedence, path scope and deduplication. Combined 0.1.7/0.1.8 installed locally with backup of app and 55 MB saved scan; original partial scan restored with 237450 files. No real cleanup performed.

## 0.1.9 update

Read-only Xcode archive inventory parses bounded Info.plist metadata and enumerates local contents for logical size and dSYM package count. Retention groups by Bundle ID/team; latest N plus additional pinned archives; missing team/date/version/build, unsupported metadata and traversal issues require manual review. Pins and limit persist in preferences; results remain in memory and are re-read on demand. Search, review filter, Finder reveal and cancellation included. No deletion, symbol UUID validation, archive backup or automatic release identification. 50 local tests pass. Installed 0.1.9 with app and scan backup; previous 237450-file partial scan restored. Installed UI read 98 real Xcode archives and displayed metadata, dSYM counts and retention labels; no archive changed. Protected-directory probes still report denied after ad-hoc update; permission continuity remains unresolved.

Next: verify dSYM UUID associations and backup requirements before enabling archive quarantine; then DerivedData and simulator lifecycle policies. Agent-specific session adapters and automatic app updates remain planned.

Apple reference: [Locating a missing debug symbol file](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file). Released archives and matching symbols should be retained for crash diagnosis.

## 0.1.10 update

Bounded native Mach-O header/load-command reader supports thin and universal 32/64-bit headers with both byte orders; binary UUID/CPU pairs are compared against MH_DSYM slices. Main executable path is checked; malformed/missing metadata, traversal failures and missing matches block transfer. UUID matching does not validate DWARF completeness. Full archive backups compare SHA-256 manifests and source stability; existing destinations are never replaced. Archive quarantine is a separate narrow API requiring a verified backup plan, stale-source revalidation and source age >24h, with pins/retention/exclusion protection and same-volume verified rename. Generic package protections remain in place. Existing directory journal restoration/recovery is reused. Archive backup path is journaled and its content revalidated before permanent deletion; missing backups do not prevent restoration. Active builds are not automatically detected; UI asks users to close Xcode/builds. Cross-volume backups are allowed, cross-volume quarantine is not. System copy cancellation may be delayed. Paged archive UI shows 10 items.

61 local tests pass, including native parser malformed bounds/endian/fat headers, mismatched or fake dSYMs, escaping application metadata, backup overwrite/cancellation, source freshness, backup mutation, exclusions/pins/retention and quarantine/restore round-trip. Only synthetic test archives were copied or moved.

Next: DerivedData association and active-build exclusion, followed by supported simulator lifecycle operations. Agent adapters, richer cleanup rules and automatic updates remain open.

References: [Apple build UUID guidance](https://developer.apple.com/documentation/technotes/tn3178-checking-for-and-resolving-build-uuid-problems), [symbol file lookup](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file).

Installed 0.1.10 after backing up the app and saved scan. UI restored the 237450-file partial scan, user's retention limit and pins; inventory read 98 archives. On-demand verification of a real archive matched 4/4 binaries. No real archive copied, moved or deleted. Protected-directory probes still return denied after the ad-hoc update; this release does not fix permission continuity.

## 0.1.11 update

Three Xcode tabs. Archive pin renamed Keep protected with explanatory copy, beyond-limit totals and batch workflow: fresh inventory, full backups, verified plans, separate transfer confirmation, revalidated retention and per-item results. Batch archive erasure remains a separately confirmed quarantine operation with verified backups. No same-disk-space-saving claim for backups/quarantine.

Simulator device/runtime inventory parsed from simctl JSON. Manual selection, unavailable-device and unused-90-day-runtime selection helpers. Exact UUID deletion with injected/testable command runner, re-read state, booted/transitional device guards, associated-runtime use guards, Xcode/build-process check and post-command verification. Unsupported/privilege/timeout errors reported; no elevation or system-directory removal. Asynchronous runtime deletion is reported as pending rather than successful. Native simulator device deletion is irreversible and explicitly described in confirmation.

DerivedData project association from info.plist; allowlisted Intermediates.noindex, Index.noindex and Logs only. Conservative process checks before preview and immediately before rename, 10-minute modification guard, protected-content/exclusion checks, manifest revalidation and existing quarantine recovery/restore. SourcePackages/products/shared unknown caches excluded. Does not provide an atomic lock against new builds; user must keep Xcode/build tools stopped. Symlinks/hard links/cloud objects remain unsupported for directory transfer. Manifest relative paths now normalize Foundation's /var and /private/var variants.

70 local tests pass, including injected simctl deletion commands, booted/unknown/alias guards, runtime pending/unsupported/protected states, active-build guard, DerivedData allowlist/project mapping and synthetic quarantine/restore. Destructive operations tested only on UUID-scoped fixtures; real simulator commands used only for help and inventory.

Next: broader developer cache rules and process association, agent-specific session adapters, intelligent cleanup coverage and automatic updates. Developer ID remains deferred.

Installed 0.1.11 with app and scan backup. Live read-only UI verification found 29 devices and 6 runtime images; booted devices and their runtimes were disabled. Default DerivedData contains no eligible project cache directories on this Mac (only project metadata and shared SDK caches); the completed empty state reports this explicitly. Existing retention preference and protected archives are retained. No real cleanup was performed. Full-disk access probes still reported denied after the initial ad-hoc replacement.

## 0.1.12 update

Added a shared bilingual help catalog across controls in all app sections, with native hover tooltips and accessibility hints. A contextual “How to use” popover explains each screen and each developer tab. Archive actions now read “Check debug symbols” and “Back up archive…”; an inline disclosure explains dSYM/UUID scope, full-copy disk cost and the backup → quarantine → permanent-deletion sequence. Help distinguishes read-only actions, selection, confirmation, irreversible simulator removal, modification age vs. last use, and logical size vs. reclaimed space. Disk-map tile rendering was extracted into a separate ViewBuilder to keep Swift type checking bounded. Core cleanup logic is unchanged. Debug build and 70 existing tests pass.

Installed 0.1.12 build 13 with a backup of the previous app and saved scan. Live UI checks verified archive button names and help, the inline symbol/backup explanation, contextual archive and DerivedData guides, simulator action help, and immediate Russian/English tooltip localization (restored Russian afterwards). Saved scan and retention/protected-archive preferences were retained. Only read-only archive inventory was run; no user cleanup occurred. Full-disk access probes still report denied after the ad-hoc update.

## 0.1.13 update

Archive retention cleanup now offers direct permanent deletion after verified full backups, with quarantine retained as an explicit alternative. The shared batch workflow rereads retention before each archive, displays a separate destructive confirmation, revalidates source/backup manifests and checks Xcode/build activity before direct removal. No quarantine payload is created by direct deletion; recovery is manual from the retained backup, whose path is logged. Exclusions, pins, retained archives, symlink replacement, project ancestry and backups inside quarantine block deletion. Cancellation is between archives; partial removal failures explicitly identify the retained backup, and inventory is refreshed afterwards.

77 local tests pass (7 new direct-deletion safety cases), including backup preservation/no quarantine creation, pins/retention/exclusions, cancellation, build activity before and after validation, changed/missing copies, changed source, project ancestry, quarantine placement and source symlink replacement. Only UUID-scoped synthetic archives were deleted during tests. The quarantine audit is recorded in QUARANTINE-POLICY-RU.md: simulators already bypass quarantine; ordinary files and duplicates keep it; DerivedData direct deletion remains a possible follow-up, not a shipped feature.

Installed 0.1.13 build 14, preserving the previous app and scan. Live UI verification confirmed separate direct-delete/quarantine actions, 98 read-only archive inventory entries, preserved keep=1 and protected archives, and the new direct-delete action opening the backup-folder picker. The picker was cancelled without choosing a destination; real archive deletion was not run. Existing full-disk access probe denial persists with the ad-hoc update.

## 0.1.14 update

Simplified the archive workflow to one confirmation, optional verified backup (off by default) and optional quarantine. Symbol matching is diagnostic only, not a cleanup prerequisite. A ten-minute write guard replaces the 24-hour wait. Quarantine no longer requires a redundant full copy. New optional archive metadata on quarantine entries distinguishes archives without copies while preserving compatibility with old entries; old specified backups remain validated before erase. If a requested copy fails, its archive is not deleted.

Added direct cleanup for selected allowlisted DerivedData indexes/intermediates/logs, preserving process, exclusion, quiet-time and manifest checks. Quarantine remains in More. Developer inventories load on first entry; refresh remains available. Per-archive diagnostics and quarantine service actions moved into menus. Agent folder scanning and model refresh labels now name their actual actions. All screens reviewed in QUARANTINE-POLICY-RU.md; personal files/duplicates retain quarantine, and original agent histories remain unchanged.

83 tests pass, including no-backup/no-dSYM archive deletion, no-backup quarantine restore/erase, legacy metadata decoding, ten-minute boundary behavior and direct cache deletion protection. Destructive tests use unique synthetic fixtures only.

Live UI verification with two synthetic archives lacking dSYM confirmed that backup-off reaches a single named Delete/Cancel confirmation without a folder chooser; backup-on opens the optional destination chooser. Both were cancelled and both synthetic archives remained intact. The fixture was removed after closing the app. DerivedData inventory loaded automatically and its direct cleanup/More actions rendered correctly. Menus were constrained to compact width. Inventory auto-loading waits for an existing operation such as saved-snapshot restoration and attempts once per presentation to prevent error retry loops. Installed 0.1.14 build 15 with backups of previous app/scan; the saved user scan and retention preferences are retained. No real user data was cleaned; existing full-disk access denial after ad-hoc replacement remains unresolved.


## 0.1.15 — аудит безопасности, 2026-10-06

Проверены публичные правила MacPaw и рекомендации Apple по архивам. Закрыта общая очистка файлов пользовательской Library; добавлена защита фототек, dSYM, пакетов проектов, ключей и ресурсов проектов без Git. Правила регистра унифицированы. Специальные операции архивов и DerivedData сохранены без обязательной копии. 87 тестов прошли. Подробности и границы: [SAFETY-POLICY-RU.md](SAFETY-POLICY-RU.md).

## 0.1.16 — единая сводка возможностей очистки

Added read-only summary cards for archive retention, allowlisted quiet DerivedData, unavailable shutdown devices/90-day-unused removable runtimes, and completed exact-duplicate comparisons. Pins/exclusions/partial inventory/unknown size are respected; no aggregate savings figure across overlapping categories. Explicit three-stage developer inventory refresh supports cooperative cancellation; simctl read commands finish before cancellation is observed. Duplicate hashing remains a separate explicit action. Navigation opens the exact developer tab, with no automatic selection/deletion. Each source has its own timestamp, unknown/empty/error status and limitations; prior failures are cleared on successful refresh. Personal-file suggestions remain below the cards. 91 tests passed including retention exclusions, incomplete inventory, duplicate preserved-copy estimation, cache quiet period and simulator busy/unknown-size cases.

Installed 0.1.16 build 17 with app/snapshot backup. Live UI refreshed all three developer inventories read-only: 94 excess archives (15.41 GB), no eligible DerivedData, two old removable runtimes (16.97 GB); duplicate status correctly remains uninspected. Verified exact DerivedData and simulator tab navigation with zero selected objects, disabled booted devices and preservation of archive keep=1/pins and saved partial scan. Visual review confirmed readable two-column cards. The app is left on the summary. No user data deleted. Existing Full Disk Access probe denial persists after ad-hoc update.

## 0.1.17 — рабочие деревья Git, 2026-10-07

Added repository selection, native Git worktree inventory, branch/HEAD, linked-tree size/change time, blocking reasons and a summary card. Main, locked, prunable, dirty/untracked/ignored, special-index/submodule, unpublished-to-local-remote-ref, recent (<30 days), open-file or unverifiable trees are protected. Canonical paths, system locations, common Git directory and registration backlinks are validated. Single-item removal uses git worktree remove without force/prune/branch deletion, with a full manifest and repeated registration/status/exclusion/activity checks after confirmation. Commands are bounded, shell-free, disable fsmonitor/hooks and ignore inherited GIT_* variables. Cooperative cancellation occurs between commands. lsof visibility cannot certify an inactive agent task; confirmation explicitly requires ending related work. Remote refs are checked locally without fetch.

100 tests passed, including actual deletion of a disposable linked tree with branch/main preservation, dirty and ignored files, local commits, special flags, locks, cancellation, exclusions, changed data/registration, activity/error responses and NUL paths. Installed build 18 with app/snapshot backup. Live UI verified primary/dirty blocking, a clean 45-day fixture candidate, exact removal confirmation and cancellation preserving both files. Fixture removed afterwards; app left inspecting the real OxyMacCleaner primary checkout (protected). No real user worktree deleted. Saved scan remains intact; ad-hoc Full Disk Access denial remains unresolved. Repository auto-discovery, direct agent-task state integration and generated project dependencies remain next stages. See WORKTREES-RU.md.

## 0.1.18 — project data

Implemented a bounded catalog of generated data and dependencies, narrow Next.js/Rust cache cleanup with repeatable safety checks, and read-only dependency inventory. 107 core tests pass. See PROJECT-DATA-RU.md. Custom build paths and recursive project discovery remain out of scope.

Packaged 0.1.18 launched locally; saved scan restored. Project-data UI displayed this repository’s SwiftPM size with cleanup disabled as intended. Full Disk Access probe still reports denial after ad-hoc update; permissions were not changed.

## 0.1.19 — first native history readers

Codex/Claude Code JSONL recognition with source-line references and complete record retention. Import runs off the UI thread. Original files remain unchanged; backups represent the loaded bytes. Other agents retain generic export import. Native branch reconstruction, automatic session discovery and real-model quality validation remain pending.

112 core tests passed. Installed packaged 0.1.19 and imported a synthetic Codex history through the UI: one message and two retained records. No model selected locally, so generation was not exercised. Real user histories were not processed or modified.

## 0.1.20 — session file discovery

Bounded metadata-only discovery of Codex/Claude JSONL files, sorted dates, sizes, path filtering and paginated rendering. Native validation runs only on selection. Missing access and limits report incomplete results. No history writes or model calls during discovery.

116 core tests passed. Packaged 0.1.20 installed, saved scan restored, catalog and name filtering verified in the UI. Only metadata inspected; no real session content loaded or changed. Large histories above 30 MB remain blocked for import pending streaming support. Full Disk Access probe still denied; no permission changes made.

## 0.1.21 — bounded streaming history import

Native JSONL above 30 MB uses a private disk snapshot and bounded line/chunk readers, up to 1 GB. Cancellation and byte progress are wired into import and backup. Local generation consumes chunks incrementally, with an explicit 8 MB output ceiling. Real-model quality and long-run throughput remain unverified.

121 core tests passed, including >30 MB native import, snapshot lifetime, unchanged verified backups after source mutation, malformed/oversize lines, cancellation and UTF-8 boundaries. Installed 0.1.21 and imported a synthetic 30.1 MB file through UI. Real histories and permissions unchanged; Full Disk Access probe still denies access. Model generation was not exercised.

## Local-model quality benchmark preparation

Added two synthetic scenarios and a local-only runner using the application system prompt. Three audit-rule tests pass. Reports explicitly require human semantic review. No actual model results yet: Ollama/model absent, internal disk space insufficient; user will free space before installation. See CONTEXT-QUALITY-RU.md. Application remains 0.1.21; no new binary required for benchmark-only changes.

## 0.1.22 — archive cleanup feedback

Logs confirmed attempted cleanup blocked by Xcode/swift-frontend, not stale inventory. Added early activity preflight, actual completion/error counts, zero-success error alert and visible developer operation report. Existing deletion guards unchanged. 121 tests pass; no real archives deleted. Context optimize/reset/delete product boundaries recorded in CONTEXT-ACTIONS-RU.md.

07.10.2026: локально установлены Ollama 0.40.0 и qwen2.5:3b; приложение видит движок и модель. Первый реальный синтетический benchmark не прошёл критерии качества (повтор искусственных секретов, неоднозначный пересказ запретов); подробности в CONTEXT-QUALITY-RU.md. Пользовательские истории не изменялись. Установка 0.1.22 и запуск проверены; проверка полного доступа к диску показывает отказ, настройки разрешений не сбрасывались.

## 0.1.23 — архивы при открытом Xcode

Общая блокировка Xcode/компиляторов заменена отдельной политикой архивов: ждём только xcodebuild. Проверки возраста, неизменности, исключений и retention сохранены. 122 теста прошли.

## 0.1.24 — тестовые симуляторы

Добавлена отдельная вкладка XCTestDevices: список simctl, состояния, измерение размеров, выборочное подтверждённое удаление. Запущенные устройства и активные инструменты блокируют удаление. Пользовательские данные при проверке не удалялись.

## 0.1.25 — test-device empty state and discovery

A missing XCTestDevices directory is a valid empty inventory; invalid files, symlinks and access errors remain errors. The test-device screen loads once on entry, keeps its inventory and measured sizes across navigation, and has a dedicated card in cleanup opportunities. It does not select or delete devices automatically.

Simulator batch feedback: preflight before confirmation, actual deletion/error counts, error alert and retained failed selections. Logs showed active xctest/xcodebuild during the user attempts (including concurrent Cleaner verification). Global activity guard remains conservative; filter was not responsible.

## 0.1.26 — scoped simulator activity

Explicit xcodebuild destination UUID association replaces the blanket guard for standard simulator devices/runtimes. Related xctest descendants are associated through process ancestry; unknown destinations and GUI Xcode remain fail-closed. Runtime protection includes XCTestDevices and rejects unmapped active destinations. No process is stopped, and no user devices were deleted in verification. Checks are not an atomic lock against starting new work.

## 0.1.27 — filtered simulator selection

Available shut-down devices can be selected across all filtered pages, replacing old device selection. Missing-runtime selection moved to More and respects search. Separate device/runtime counters explain scope. Cleanup logic unchanged.

## 0.3.0 — пять направлений, 07.10.2026

Implemented FTS metadata traversal, batched atomic scan snapshots with legacy binary-plist loading, and append-only crash journals. Recovery restores partial results and offers a fresh traversal; it does not resume exactly at the interrupted directory. Metadata remains in RAM. A corrupted completed snapshot is rejected.

Measured on this Mac using disposable synthetic fixtures: 1,000,000 physical files scanned in 159.09 s, peak process RSS 869,072,896 bytes, compared with 248.14 s / 5,671,190,528 bytes before the traversal change. Both include synthetic 100 MB history import/backup in the same process; fixture creation is excluded from scan duration. Different filesystem cache states make this a local comparison, not a universal speed guarantee. Separate million-record metadata test: save 2.80 s, load+index 22.42 s, peak RSS 1,303,625,728 bytes while retaining original and restored reports. This does not measure the full live UI scan pipeline.

Added Gemini CLI, Continue, Cline and Roo Code readers with structure validation and retained unknown fields; eight native file adapters total. Added bounded source/output comparison and reference-only local-model selection. Short and five-part synthetic 7B cases passed; manual semantic review remains required.

Added verified relocation of existing quarantine payloads to another volume, conflict-safe restoration, and explicit management of completed updater backups with newest protected. Real APFS image cross-volume copy/restore passed using only an owned fixture. Interrupted copy may leave extra copies; no automated pruning of uncertain leftovers. Initial quarantine still requires same-volume placement.

Added localized common-error explanations, lifecycle labels, keyboard section commands and accessibility labels for new views. 145 Swift tests passed, plus three Python audit tests. Full VoiceOver end-to-end coverage and signed distribution remain open. No real user archives, simulator devices, histories or quarantine payloads were removed during development.

Installed final 0.3.0 build 32 locally with 0.2.2 rollback copy retained. UI verified: legacy user scan restored (237,450 files), Cmd+, settings and Cmd+4 agents, Russian/English navigation, light/dark rendering, synthetic Gemini import (2 messages + metadata), source/result comparison, and four completed updater copies with 0.2.2 protected. The backup expander was replaced with an explicit accessible button after UI testing. No copies were deleted. Theme restored to System and language to Russian. Full Disk Access probe reports denial after this ad-hoc binary replacement; no TCC reset or permission bypass performed. End-to-end VoiceOver speech, complete English localization of old status/template strings, and native history branch reconstruction remain limitations.

Abrupt child-process exit test recovered exactly 256 synchronized records of 300 and correctly marked the result partial; 44 unflushed records were absent. The test used synthetic metadata only.


## 0.3.1 — Ollama lifecycle and rollback names

Ollama status checks run automatically on engine entry, app activation and completion of an operation. A bounded local tags check distinguishes reachable service from an installed app that needs launching. Existing 3B/7B models show Installed/Selected and cannot trigger a redundant pull. Model download has an immediate waiting state, per-file byte/fraction progress, cancellation and terminal-success validation. Missing service disables download. No existing model was removed to test downloading.

Updater copies now preserve the application filename under rollback/OxyMac Cleaner.app, with compatible inventory and migration of validated completed legacy capsules. No TCC database editing, permission reset or weakened signature requirements. macOS may retain a cached old permission label; this is not a stable-signing substitute.

147 core tests passed, including pull progress/error/incomplete stream and old/new backup layouts. Real helper tests passed successful launch and failed-launch rollback on disposable shell app stubs. Follow-up from the UX specification: translated update statuses and clean-context template into English. Complete VoiceOver coverage and all historical diagnostic strings remain unfinished.

Final packaged 0.3.1 installed locally. Live UI automatically detected running Ollama and both installed models; install/launch/download buttons were absent. Switching 7B→3B→7B selected instantly without download or confirmation. Left 7B selected. Existing scan restored; validated legacy backup directories migrated with original bundle names. Full Disk Access probe still reports denial after replacing the ad-hoc binary; no permissions were reset. Byte-progress and incomplete-stream logic were tested with synthetic protocol responses; no model was removed or needlessly downloaded for UI testing.
