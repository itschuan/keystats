# CLI Product Design

## Positioning

Keystats CLI is the first open-source release. It targets developers and terminal users, validates the core capabilities, and builds the initial community usage base.

## User Value

- View today's keyboard usage
- View weekly trends
- View key category distribution
- View app-level statistics
- View key rankings
- Record usage long term through a local daemon

## Core Commands

| Command | Purpose |
|---------|---------|
| `keystats start` | Start background statistics collection |
| `keystats pause` | Pause statistics collection |
| `keystats resume` | Resume statistics collection |
| `keystats stop` | Stop background statistics collection |
| `keystats status` | Show daemon status |
| `keystats doctor` | Check permissions, database, and LaunchAgent status |
| `keystats today` | Show today's overview |
| `keystats week` | Show weekly trends |
| `keystats stats --period 7d` | Show detailed statistics |
| `keystats keys --period today` | Show key rankings |
| `keystats mode` | Show the current statistics mode |
| `keystats mode detail` | Switch to key detail mode |
| `keystats clear` | Clear local statistics data |

## First-Run Flow

```bash
brew install keystats
keystats doctor
# Grant Input Monitoring permission as instructed
keystats start
keystats today
```

## Privacy Interactions

- Use aggregate statistics mode by default
- Require a second confirmation before switching to detail mode
- Require a second confirmation before deleting data with `clear`
- When permissions are missing, show permission status instead of misleading zero data

