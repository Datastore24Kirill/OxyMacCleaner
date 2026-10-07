# 0.2.0 Preview

- Context handoff now uses source excerpts chosen by a local model, with validated source-line references. Generated claims are not copied into the handoff. Sensitive-data patterns are redacted before generation and from output. Review remains required; filtering and preservation of meaning are not guaranteed.
- Separate actions for a continuation handoff and a clean-task template. Both preserve the original and create a verified backup. Opening the new agent chat remains manual.
- Cursor file-based JSONL transcripts join Codex and Claude native import/catalog support. Cursor databases are not modified. Other agents use explicit exports.
- In-app updates check GitHub, display download progress, verify SHA-256, archive bounds, bundle identity and signature integrity, then install and restart. A retained previous app is restored if launch confirmation fails. Developer ID and continuity of macOS permissions remain unresolved.
- Large synthetic QA: 100,000 files scanned in 34.1 seconds; a 100 MB JSONL imported and backed up in 4.0 seconds. Peak RSS for the entire fixture process was 1.14 GB. Autorelease pools reduced memory from the earlier run, but performance work remains.

The 7B model's ordinary paraphrase failed a synthetic accuracy case. The grounded-excerpt path passed the two synthetic cases, which is limited evidence, not a guarantee. Existing histories are never automatically rewritten or deleted.
