# Implementation status — 0.1.8 Preview

This milestone starts implementation of SPEC-RU.md. It does not claim full version-one acceptance.

| Specification area | Current state | Remaining |
|---|---|---|
| Native UI / RU+EN / themes | Implemented | Full VoiceOver audit; error localization; empty-state refinement |
| Scan / files / folder sizes | Implemented; disk/folder roots, cancellation, exclusions, issue report, saved snapshots, navigable treemap, category/size/modified-age filters | Incremental file-list streaming, crash checkpoints during scan, large-volume benchmarks |
| Exact duplicates | Implemented; hash plus byte comparison; hard-link deduplication; keeper validation | APFS allocated-block accounting; large-run performance |
| Archives | Extension-based filtering | Versions, grouping, configurable retention |
| Xcode | DerivedData and archive inspection, read-only simctl inventory | Archive metadata/dSYM retention, active-build detection and supported runtime deletion |
| Projects | Generated-file classification; Git directories protected from movement | Safe generated-folder cleanup and worktree lifecycle checks |
| Quarantine | Files and ordinary directories on the same volume; tree integrity, journal recovery, conflict refusal, confirmed erase | Cross-volume verified transfer, active-app detection, filesystem fault injection and richer recovery states |
| Notifications | Repeating five-day notification while nonempty; in-app reminder | Long-duration OS delivery validation; refreshed notification count after inventory changes |
| Agents | Discovery hints for 11 products; generic export import per agent | Versioned native adapters and supported automatic handoff paths |
| Context | Verified backup, line-numbered chunks, local generation, editable result, copy/export | Real-model semantic benchmarks, conflict reconciliation across chunks, citations validator, model-specific token budgeting |
| Ollama setup | Official app download, hash/code-signature/Gatekeeper validation, launch, model pull progress | Live clean-machine installation QA, model management/deletion UI, tested hardware recommendations |
| Updates | GitHub Releases link | Signed update metadata, auto-install, launch health check and rollback |
| Distribution | Ready-to-run arm64 app, checksums, source, CI | Developer ID signing/notarization, Intel (outside initial scope) |

## Agent capability matrix

All 11 agents currently use the same **explicit text-export import**, not automatic internal-history parsing. The catalog identifies known default locations when present; absence does not mean an agent is not installed. Installation variants and IDE profiles need separate validation.

| Agent | Discovery hint | Import TXT/MD/JSON/JSONL | Rewrite existing chat | Automatic new chat |
|---|---|---|---|---|
| Codex | Yes | Yes | No | No |
| Claude Code | Yes | Yes | No | No |
| Cursor | Yes | Yes | No | No |
| GitHub Copilot | VS Code default | Yes | No | No |
| Gemini CLI | Yes | Yes | No | No |
| Windsurf | Yes | Yes | No | No |
| Cline | VS Code default | Yes | No | No |
| Roo Code | VS Code default | Yes | No | No |
| Aider | Home hint only; project histories require import | Yes | No | No |
| Continue | Yes | Yes | No | No |
| OpenCode | Yes | Yes | No | No |

## Verification

- Core tests cover scan cancellation/exclusion, symlink loops, hard links, exact duplicates, stale-file rejection, protection rules, quarantine restore conflicts, corrupt payload refusal, deletion of test fixtures, reminder timing, transcript backup and complete chunk coverage.
- Ollama protocol tests cover local-only selection, metadata validation before sending a prompt and empty-output rejection. These use a mocked protocol and are not proof of model quality.
- Local packaged UI: launched, manually scanned synthetic files and detected the expected duplicate pair.
- No user files or histories were cleaned during implementation.

## Next milestones

1. Directory quarantine, recovery after interruption, active-work detection and Xcode metadata.
2. Versioned read-only session adapters, starting with Codex and Claude Code; real local-model fixtures.
3. Complete UI/accessibility and large-scan performance verification.
4. Automatic update installation with rollback; signed distribution when a certificate is available.

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
