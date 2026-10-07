# 0.2.2 Preview

Update downloads now process bytes off the UI actor and only send progress snapshots to the interface. This avoids one UI-actor transition per byte. Download limits, redirect restrictions, SHA-256 checks and rollback remain intact.

Also simplifies simulator labels for the GitHub runner compiler and makes CI collect the current version's archive. Includes the 0.2.0 context features and 0.2.1 UI refinements.
