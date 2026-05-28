# Core Development Tasks

## P0

- Initialize the Swift Package structure
- Define Core models: key event, key category, app context, stat bucket, listener status
- Implement `MigrationRunner`
- Implement `DataStore` initialization, migration, and connection management
- Configure SQLite WAL / busy timeout / foreign keys
- Implement `KeyClassifier`
- Implement `KeyboardLayoutResolver`
- Implement `AppContextProvider` using `NSWorkspace` for foreground app detection
- Implement `PermissionChecker` for Input Monitoring / Accessibility status
- Implement `KeyListener` using `CGEventTap`
- Implement `EventTapSupervisor` to handle event tap invalidation and rebuilding
- Implement `StatsAggregator`
- Implement `minute_stats` aggregate writes
- Implement `key_usage_stats` aggregate writes
- Implement batched `key_events` writes in detail mode
- Implement lazy `daily_stats` aggregation
- Implement `RetentionManager` for expired detail and aggregate data cleanup

## P1

- Implement session detection: continuous typing vs breaks
- Implement app statistics queries
- Implement key ranking queries
- Implement CSV / JSON export interfaces

## P2

- Support custom data retention periods
- Support excluded apps
- Support more keyboard layout display labels
