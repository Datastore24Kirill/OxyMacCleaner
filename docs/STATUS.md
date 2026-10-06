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
