# Implementation status — 0.1.0 Preview

This milestone starts implementation of SPEC-RU.md. It does not claim full version-one acceptance.

| Specification area | Current state | Remaining |
|---|---|---|
| Native UI / RU+EN / themes | Implemented | Full VoiceOver audit; error localization; empty-state refinement |
| Scan / files / folder sizes | Implemented; manual roots, cancellation, exclusions, issue report | Treemap, date/type filters, incremental result streaming, large-volume benchmarks |
| Exact duplicates | Implemented; hash plus byte comparison; hard-link deduplication; keeper validation | APFS allocated-block accounting; large-run performance |
| Archives | Extension-based filtering | Versions, grouping, configurable retention |
| Xcode | DerivedData and archive inspection, read-only simctl inventory | Archive metadata/dSYM retention, active-build detection and supported runtime deletion |
| Projects | Generated-file classification; Git directories protected from movement | Safe generated-folder cleanup and worktree lifecycle checks |
| Quarantine | Individual files on the same volume; journal, restore, conflict refusal, integrity check, confirmed erase | Whole directories, cross-volume verified transfer, crash-injection testing and richer recovery states |
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
