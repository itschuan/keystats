# Core Technical Design

## Modules

```text
KeystatsCore
├── KeyListener
├── PermissionChecker
├── AppContextProvider
├── KeyboardLayoutResolver
├── KeyClassifier
├── StatsAggregator
├── DataStore
├── MigrationRunner
├── RetentionManager
├── EventTapSupervisor
├── Analyzer
└── Models
```

## Data Flow

```text
Keyboard event
  -> KeyListener
  -> PermissionChecker
  -> AppContextProvider
  -> KeyboardLayoutResolver
  -> KeyClassifier
  -> StatsAggregator
  -> minute_stats flush every minute
  -> key_usage_stats upsert
  -> daily_stats generated lazily
```

Key detail mode additionally appends events to an in-memory detail queue and batch-writes them to `key_events` during flush.

## Permissions

Global keyboard listening through `CGEventTap` requires Input Monitoring permission.

Core requirements:

- Check permissions before starting listening
- Check permissions again after the daemon starts
- Disable the event tap if permissions are revoked at runtime
- Enter the `permission_required` state when listening is not allowed

Accessibility is not required for the first version. It is reserved for future window-context enhancements.

## Foreground App Detection

The first version uses `NSWorkspace` to read the foreground app name and bundle id.

On failure, Core writes:

- `app_bundle_id = unknown`
- `app_name = Unknown`

## SQLite Schema

```sql
CREATE TABLE schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at DATETIME NOT NULL
);

CREATE TABLE minute_stats (
    id INTEGER PRIMARY KEY,
    minute DATETIME NOT NULL,
    app_bundle_id TEXT NOT NULL DEFAULT 'unknown',
    app_name TEXT NOT NULL DEFAULT 'Unknown',
    total_keys INTEGER DEFAULT 0,
    letters INTEGER DEFAULT 0,
    numbers INTEGER DEFAULT 0,
    symbols INTEGER DEFAULT 0,
    function_keys INTEGER DEFAULT 0,
    modifier_keys INTEGER DEFAULT 0
);

CREATE INDEX idx_minute_stats_minute ON minute_stats(minute);
CREATE INDEX idx_minute_stats_app ON minute_stats(app_bundle_id, minute);
CREATE UNIQUE INDEX idx_minute_stats_bucket ON minute_stats(minute, app_bundle_id);

CREATE TABLE key_usage_stats (
    id INTEGER PRIMARY KEY,
    date TEXT NOT NULL,
    hour INTEGER NOT NULL,
    app_bundle_id TEXT NOT NULL DEFAULT 'unknown',
    app_name TEXT NOT NULL DEFAULT 'Unknown',
    key_code INTEGER NOT NULL,
    key_name TEXT NOT NULL,
    key_category TEXT NOT NULL,
    count INTEGER DEFAULT 0
);

CREATE INDEX idx_key_usage_date ON key_usage_stats(date);
CREATE INDEX idx_key_usage_key ON key_usage_stats(key_code, date);
CREATE INDEX idx_key_usage_app ON key_usage_stats(app_bundle_id, date);
CREATE UNIQUE INDEX idx_key_usage_bucket ON key_usage_stats(date, hour, app_bundle_id, key_code);

CREATE TABLE key_events (
    id INTEGER PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    key_code INTEGER NOT NULL,
    key_name TEXT NOT NULL,
    key_category TEXT NOT NULL,
    app_bundle_id TEXT NOT NULL DEFAULT 'unknown',
    app_name TEXT NOT NULL DEFAULT 'Unknown',
    modifiers INTEGER DEFAULT 0
);

CREATE INDEX idx_key_events_timestamp ON key_events(timestamp);
CREATE INDEX idx_key_events_app ON key_events(app_bundle_id, timestamp);

CREATE TABLE daily_stats (
    date TEXT PRIMARY KEY,
    total_keys INTEGER,
    letters INTEGER,
    numbers INTEGER,
    symbols INTEGER,
    function_keys INTEGER,
    top_apps TEXT,
    peak_hour INTEGER,
    active_minutes INTEGER
);
```

## SQLite Runtime Settings

```sql
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA foreign_keys = ON;
```

Write strategy:

- The daemon is the only writer
- A single-writer queue serializes all writes
- `minute_stats` and `key_usage_stats` use `INSERT ... ON CONFLICT ... DO UPDATE`
- Flush operations run inside transactions
- CLI and Lite use read-only connections for queries

## Aggregation Strategy

- Every key event enters in-memory aggregation in real time
- Data is flushed to SQLite every minute by default
- `minute_stats` and `key_usage_stats` are aggregate fact tables
- `daily_stats` is a query cache and can be rebuilt from aggregate fact tables
- On startup, the daemon backfills missing `daily_stats` records for the last 7 days

