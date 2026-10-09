# OxyMac Cleaner 0.4.13 Preview

- Refresh this app's macOS name/icon registration at launch; no permission reset.
- Avoid hashing every completed update backup during startup migration.
- Clear error guidance, expandable technical details, local copy and contextual navigation. No automatic retry of cleanup.
- Restore updater launch/rollback QA after its source relocation and run it in CI.

Validation: 190 tests passed locally; successful-update/failed-launch rollback fixtures passed; malformed-import UI checked. The legacy previous.app name and icon were repaired on the development Mac.

Ad-hoc updates may still require adding the installed app again in Full Disk Access and restarting it. Developer ID remains deferred; this release does not claim permission continuity.

[Acceptance details](ACCEPTANCE-0.4.13-RU.md).
