# OxyMac Cleaner 0.4.12 Preview

- Faster file navigation: background indexing, cached filtering, incremental lists, cancellable searches.
- Protected files hidden by default; optional read-only review.
- Visual task shortcuts, grouped sidebar, simpler archive controls.
- Friendly Xcode cache names and clear cleanup consequences.
- Less repeated simulator and local-engine polling.

Validation: 187 tests passed; arm64 Release build and signature integrity verified; local navigation through all sections and Xcode tools checked without deleting user data.

Known issue: macOS may retain the legacy `previous.app` privacy label despite the correct bundle name and icon. Local access check succeeds; the system label is not yet fixed. Developer ID signing remains deferred.

[Detailed UX scenarios](UX-AUDIT-0.4.12-RU.md).
