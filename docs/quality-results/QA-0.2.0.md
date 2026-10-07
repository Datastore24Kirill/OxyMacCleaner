# QA 0.2.0 — 7 October 2026

- 139 Swift tests passed; 3 Python benchmark-runner tests passed.
- Synthetic updater helper: successful new-app launch retained previous.app; a failed new-app launch restored the previous app. The shell fixture replaced LaunchServices `open` with a no-op; it is not an end-to-end update test.
- Synthetic grounded 7B handoff: two cases, manually inspected. Source citations and test evidence retained; model-authored invented completion did not enter output. No promise of lossless compression.
- 100,000 synthetic files: scan 34.06 s. 100 MB native JSONL: import plus verified backup 4.01 s, original unchanged. Total fixture process peak RSS 1,142,210,560 bytes, including fixture generation and hashing; this is not isolated scanner memory.
- Previous unpooled fixture: scan 35.50 s, import/backup 4.15 s, peak RSS 2,390,032,384 bytes. Multiple autorelease pools changed, including fixture generation, so the improvement cannot all be attributed to the scanner.
- Unit tests include quarantine restore/corrupt payload/conflict and interrupted operation cases. No new user cleanup was performed as QA.
- Full VoiceOver audit, multi-million-file scale, certificate/permission continuity and broad agent version compatibility remain open.

## Packaged end-to-end checks

A private updater bootstrap with older version metadata downloaded the public 0.2.0 ZIP from GitHub and installed it. The new executable ran with the health-marker argument, wrote `healthy`, and the helper logged successful launch; `previous.app` remained available. The window restored the previous scan snapshot. No user cleanup ran.

The packaged app imported a synthetic Cursor JSONL with two messages and created a clean-context template with a verified backup. This does not test internal Cursor database mutation (not supported).

The packaged local 7B continuation action completed on the two-message Cursor fixture. Its result retained the original-deletion prohibition and the explicit statement that implementation/tests were not done. The source file and verified backup hashes matched.
