# Lite Product Design

## Positioning

Keystats Lite is a standalone menu bar statistics tool for everyday Mac users. It provides a lightweight, low-interruption overview of keyboard usage.

## Core User Value

- View today's key count in the menu bar in real time
- Click the menu bar item to view today's overview
- View trends for the last 7 days
- View today's Top Apps
- Manage statistics mode and local data

## Feature List

| Feature | Priority | Description |
|---------|----------|-------------|
| Menu Bar icon | P0 | Display today's key count in real time |
| Click-to-expand panel | P0 | Show today's statistics |
| Today statistics | P0 | Total keys, active time, Top 3 apps |
| Permission guide | P0 | Guide users to grant Input Monitoring |
| Statistics mode switch | P0 | Support aggregate statistics mode / key detail mode |
| Data clearing | P0 | Clear local statistics data |
| Launch at login | P1 | Optional launch at login |
| Data retention | P1 | Show the last 7 days, retain aggregate data for 90 days, retain detail data for 7 days |

## UI Draft

```text
Menu Bar:
⌨️ 12,847

Panel:
Today
12,847 keys
4h 23m active
Top App: VS Code

Last 7 Days
Mon  ████████████ 12.8k
Tue  ██████████   11.2k
Wed  ████████████ 13.1k

Settings
```

## Permission Failure State

When permission is not granted, do not show misleading zero data. The UI should show:

- Permission status
- Why the permission is needed
- How to open System Settings and grant permission
- How to continue after granting permission

