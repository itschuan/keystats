# Changelog

📅 2026-05-29

🐛 Bug Fixes
`00ada49` `fix(lite)` Reduce verbose debug logging while keeping duplicate process cleanup diagnostics — itschuan
`e7969eb` `fix(lite)` Remove legacy bundled CLI executables on startup to stop old background writers from respawning — itschuan
`3dbd70e` `fix(lite)` Add a single-instance lock and terminate old Keystats app or CLI processes to prevent duplicate database writes — itschuan
`74a917c` `fix(lite)` Remove HID/AppKit fallback listeners to avoid multi-channel duplicate counting — itschuan
`3fe33e1` `fix(lite)` Stabilize Lite background tracking, fix local-day stats, improve permission diagnostics, and remove the deprecated CLI — itschuan

✨ Features
`74a917c` `feat(lite)` Show the app version and Git short SHA in the menu panel — itschuan

📝 Documentation
`74a917c` `docs` Add the changelog and require future user-facing changes to update release notes — itschuan

📅 2026-05-28

🐛 Bug Fixes
`484baeb` `fix(core,lite)` Fix local-day aggregation offsets and add Lite diagnostics logging — itschuan

📅 2026-05-26

🐛 Bug Fixes
`460ac3e` `fix(lite)` Fix duplicate-looking Top 10 Keys rows by aggregating across apps correctly — itschuan

📝 Documentation
`0cdca9f` `docs` Add the project README — itschuan

✨ Features
`c626141` `feat(lite)` Add the Keystats Lite menu bar app — itschuan

📅 2026-05-25

📝 Documentation
`cadb065` `docs` Translate module documentation to English — itschuan
`81a5d81` `docs` Organize the project documentation structure — itschuan

✨ Features
`1708884` `feat(core,cli)` Implement the Core engine and early CLI foundation — itschuan
