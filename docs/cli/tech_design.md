# CLI 技术方案

## 架构

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

## Daemon 生命周期

CLI daemon 使用当前用户级 `launchd` LaunchAgent 管理。

| 配置项 | 值 |
|--------|----|
| Label | `com.keystats.daemon` |
| ProgramArguments | `keystats daemon run` 的绝对路径参数 |
| RunAtLoad | `true` |
| KeepAlive | `true` |
| StandardOutPath | `~/.keystats/keystats.log` |
| StandardErrorPath | `~/.keystats/keystats.log` |

安装后不会自动运行。用户第一次执行 `keystats start` 时才安装并加载 LaunchAgent；之后该 LaunchAgent 会在用户登录时继续运行，直到 `keystats stop` 卸载。

## Daemon 状态

| 状态 | 含义 |
|------|------|
| `stopped` | 未运行 |
| `running` | 正在监听和统计 |
| `paused` | 进程运行，但 event tap 停用 |
| `permission_required` | 权限不足，无法监听 |
| `error` | 运行异常，需要 `doctor` 诊断 |

## IPC

首版使用 Unix domain socket。

路径：

```text
~/.keystats/daemon.sock
```

`status` 可回退检查：

- LaunchAgent 状态
- pid 文件
- `daemon.state.json`
- 数据库最近写入时间

## 文件布局

```text
~/.keystats/
├── keystats.db
├── keystats.log
├── config.yaml
├── daemon.sock
├── daemon.pid
└── daemon.state.json
```

## 权限

- `start` 前 CLI 做 preflight
- daemon 启动后必须再次检查权限
- 运行中权限撤销时，daemon 停用 event tap 并进入 `permission_required`
- `doctor` 负责输出用户可执行的修复步骤

