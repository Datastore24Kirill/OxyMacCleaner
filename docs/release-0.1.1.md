# OxyMac Cleaner 0.1.1 — Preview

- Approved neon brand icon in Dock/Finder, sidebar and README.
- Disk-first scanning: startup volume selected by default; choose other mounted local volumes and see used/available/total capacity.
- Specific-folder selection remains optional.
- Disconnected volumes are rejected before scan. Startup scanning skips other mounted volumes and duplicate APFS system namespaces.
- Permission failures remain visible in the report. Full Disk Access settings are accessible from the scan panel; no permissions are silently changed.

19 automated tests passed locally. No automatic cleanup. Existing preview limitations still apply (see docs/STATUS.md). macOS 14+ Apple Silicon; ad-hoc signed, not notarized.
