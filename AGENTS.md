# Keystats Project Guide

## Project Overview

Keystats is a macOS keyboard usage statistics tool.

The project currently has two modules:

- `core`: shared Swift Package capabilities for keyboard listening, storage, aggregation, privacy modes, and analytics
- `lite`: standalone macOS menu bar app built on top of `core`

The repository contains the shared Core implementation and the Keystats Lite menu bar app.

## Current Structure

```text
.
├── AGENTS.md
├── Package.swift
├── Sources/
│   ├── CSQLite/
│   │   └── module.modulemap
│   ├── KeystatsCore/
│   │   ├── Analyzer.swift
│   │   ├── AppContextProvider.swift
│   │   ├── DateUtils.swift
│   │   ├── EventTapSupervisor.swift
│   │   ├── KeyClassifier.swift
│   │   ├── KeyListener.swift
│   │   ├── KeyboardLayoutResolver.swift
│   │   ├── Models.swift
│   │   ├── Period.swift
│   │   ├── PermissionChecker.swift
│   │   ├── RetentionManager.swift
│   │   ├── SQLiteDataStore.swift
│   │   └── StatsAggregator.swift
│   └── KeystatsLite/
│       └── KeystatsLiteApp.swift
├── Tests/
│   └── KeystatsCoreTests/
└── docs/
    ├── core/
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

Core should not contain Lite-specific UI behavior.

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
- Lite runs as a menu bar app and owns app lifecycle behavior.

## Working Guidelines

- Read the relevant module docs before changing behavior.
- Keep product, technical, development, automated test, and manual QA concerns in their matching files.
- Keep shared logic in Core and product-specific UI/lifecycle logic in Lite.
- If a task changes privacy behavior, update the relevant `product_design.md`, `tech_design.md`, and test task files.
- If a task changes data storage, update Core tech design, Core tasks, and Core tests.
- If a task changes App Store behavior, update Lite product design, Lite tech design, and Lite manual test tasks.
