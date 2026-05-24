# Keystats Project Guide

## Project Overview

Keystats is a macOS keyboard usage statistics tool.

The project currently has three planned modules:

- `core`: shared Swift Package capabilities for keyboard listening, storage, aggregation, privacy modes, and analytics
- `cli`: open-source command line product built on top of `core`
- `lite`: standalone macOS menu bar app built on top of `core`

The current repository is documentation-first. Implementation files have not been scaffolded yet.

## Current Structure

```text
.
├── AGENTS.md
└── docs/
    ├── core/
    │   ├── product_design.md
    │   ├── tech_design.md
    │   ├── tasks.md
    │   ├── test_tasks.md
    │   └── manual_test_task.md
    ├── cli/
    │   ├── product_design.md
    │   ├── tech_design.md
    │   ├── tasks.md
    │   ├── test_tasks.md
    │   └── manual_test_task.md
    └── lite/
        ├── product_design.md
        ├── tech_design.md
        ├── tasks.md
        ├── test_tasks.md
        └── manual_test_task.md
```

## Documentation Convention

Each module under `docs/` follows the same document layout:

| File | Purpose |
|------|---------|
| `product_design.md` | Product goals, user value, feature behavior, UX and privacy expectations |
| `tech_design.md` | Architecture, technical decisions, data flow, storage, permissions, and implementation constraints |
| `tasks.md` | Development tasks split by priority |
| `test_tasks.md` | Automated and unit test tasks |
| `manual_test_task.md` | Manual QA tasks that require a human or real macOS environment |

## Module Responsibilities

### Core

`docs/core/` describes the shared engine.

Core owns:

- `CGEventTap` keyboard listening
- Input Monitoring / Accessibility permission checks
- foreground app detection through `NSWorkspace`
- keyboard layout display labels
- key classification
- SQLite schema and migrations
- minute-level aggregation
- key usage aggregation for rankings and future heatmaps
- detail mode event storage
- data retention and cleanup
- analytics query primitives

Core should not contain CLI-specific command behavior or Lite-specific UI behavior.

### CLI

`docs/cli/` describes the first shipping product.

CLI owns:

- command-line interface
- daemon lifecycle commands
- user-level `launchd` LaunchAgent management
- Unix domain socket IPC
- `doctor`, `status`, `clear`, `mode`, `today`, `week`, `stats`, and `keys` commands
- terminal output and permission guidance
- README and installation instructions

CLI should depend on Core for listening, storage, aggregation, and analytics.

### Lite

`docs/lite/` describes the planned macOS menu bar app.

Lite owns:

- SwiftUI app target
- `MenuBarExtra`
- today panel
- settings UI
- permission guide UI
- empty and permission-failure states
- App Store readiness work
- App Sandbox / Input Monitoring / `CGEventTap` feasibility spike

Lite should depend on Core and should not duplicate Core storage or analytics logic.

## Important Product Decisions

- Default mode is aggregate statistics mode.
- Detail mode is opt-in and requires explicit confirmation.
- Default mode records per-key aggregate counts but not key order.
- Heatmap data uses hardware `key_code` as the stable identity.
- `key_name` is only a display label and may vary by keyboard layout.
- All data is local-only.
- Detail event data defaults to 7-day retention.
- Aggregate data defaults to 90-day retention.

## Important Technical Decisions

- Core is a Swift Package.
- Keyboard listening uses `CGEventTap`.
- Foreground app detection starts with `NSWorkspace`.
- SQLite is the local datastore.
- SQLite should use WAL mode, busy timeout, and serialized writes.
- `minute_stats` and `key_usage_stats` are aggregate fact tables.
- `daily_stats` is a rebuildable query cache.
- CLI daemon is managed by a user-level LaunchAgent.
- CLI IPC uses Unix domain socket.

## Working Guidelines

- Read the relevant module docs before changing behavior.
- Keep product, technical, development, automated test, and manual QA concerns in their matching files.
- When implementation begins, keep shared logic in Core and product-specific logic in CLI or Lite.
- If a task changes privacy behavior, update the relevant `product_design.md`, `tech_design.md`, and test task files.
- If a task changes data storage, update Core tech design, Core tasks, and Core tests.
- If a task changes daemon lifecycle, update CLI tech design and CLI test tasks.
- If a task changes App Store behavior, update Lite product design, Lite tech design, and Lite manual test tasks.

