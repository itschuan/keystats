# CLI Automated / Unit Test Tasks

## Commands

- Test `start` generates the correct LaunchAgent plist
- Test `start` returns the current status when already running
- Test `stop` unloads the LaunchAgent
- Test `pause` sends a pause command through IPC
- Test `resume` sends a resume command through IPC
- Test `status` can read daemon state
- Test `status` fallback when IPC is unavailable
- Test `doctor` outputs permission, database, and LaunchAgent status
- Test `clear` requires confirmation
- Test `mode detail` requires confirmation or `--confirm`

## Query Commands

- Test `today` outputs total keys, active time, peak hour, and Top App
- Test `week` outputs daily trends
- Test `stats --period 7d` outputs app distribution and key category distribution
- Test `keys --period today` outputs key rankings
- Test `keys --app` filters by app
- Test `keys --app-bundle-id` filters by bundle id
- Test `keys --category` filters by key category
- Test `keys --limit` limits the number of results

## Daemon

- Test daemon checks permissions after startup
- Test missing permission enters `permission_required`
- Test pause disables the event tap
- Test resume rebuilds the event tap
- Test stop flushes the current bucket before exiting
- Test state files help diagnostics after abnormal exit

