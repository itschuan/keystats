# Lite Technical Design

## Architecture

```text
Keystats Lite
├── SwiftUI App
├── MenuBarExtra
├── TodayPanel
├── SettingsView
├── PermissionGuideView
└── KeystatsCore dependency
```

## Technology Choices

- SwiftUI
- MenuBarExtra
- SQLite via KeystatsCore
- Input Monitoring permission
- `NSWorkspace` foreground app detection

## App Store Preflight Spike

Before Phase 2 starts, verify:

- Whether App Sandbox + `CGEventTap` can run
- Whether the Input Monitoring permission guide is acceptable
- App Store review risk
- SQLite local storage path
- Launch-at-login approach

If the spike fails, the release channel or architecture must be adjusted.

## Permission Handling

- Show a permission guide on first launch
- Provide an entry point to System Settings
- After authorization, return to the app and continue listening
- If permission is revoked at runtime, show a permission failure state

## Data Access

Lite queries through KeystatsCore:

- Today's total keys
- Today's active time
- Today's Top Apps
- Last 7 days trend
- Current statistics mode

Lite does not directly manipulate the SQLite schema.

## Settings

- Statistics mode
- Launch at login
- Clear local data
- Data retention explanation
- Privacy explanation

