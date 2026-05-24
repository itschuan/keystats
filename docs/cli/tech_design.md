# CLI Technical Design

## Architecture

```text
keystats CLI
├── Commands
│   ├── StartCommand
│   ├── StopCommand
│   ├── PauseCommand
│   ├── ResumeCommand
│   ├── StatusCommand
│   ├── DoctorCommand
│   ├── TodayCommand
│   ├── WeekCommand
│   ├── StatsCommand
│   └── KeysCommand
└── Daemon
    ├── DaemonRunner
    ├── LaunchAgentPlistBuilder
    ├── LaunchAgentManager
    ├── IPCServer
    ├── IPCClient
    └── DaemonControlClient
```

## Daemon Lifecycle

The CLI daemon is managed by a user-level `launchd` LaunchAgent.

| Configuration | Value |
|---------------|-------|
| Label | `com.keystats.daemon` |
| ProgramArguments | Absolute path arguments for `keystats daemon run` |
| RunAtLoad | `true` |
| KeepAlive | `true` |
| StandardOutPath | `~/.keystats/keystats.log` |
| StandardErrorPath | `~/.keystats/keystats.log` |

The app does not run automatically after installation. The first `keystats start` command installs and loads the LaunchAgent. After that, the LaunchAgent continues running after user login until `keystats stop` unloads it.

## Daemon States

| State | Meaning |
|-------|---------|
| `stopped` | Not running |
| `running` | Listening and collecting statistics |
| `paused` | Process is running, but the event tap is disabled |
| `permission_required` | Permission is missing, so listening cannot start |
| `error` | Runtime error; requires `doctor` diagnostics |

## IPC

The first version uses a Unix domain socket.

Path:

```text
~/.keystats/daemon.sock
```

`status` can fall back to checking:

- LaunchAgent status
- pid file
- `daemon.state.json`
- latest database write time

## File Layout

```text
~/.keystats/
├── keystats.db
├── keystats.log
├── config.yaml
├── daemon.sock
├── daemon.pid
└── daemon.state.json
```

## Permissions

- The CLI runs a preflight check before `start`
- The daemon must check permissions again after startup
- If permission is revoked at runtime, the daemon disables the event tap and enters `permission_required`
- `doctor` outputs actionable recovery steps for the user

