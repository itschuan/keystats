# Core 技术方案

## 模块组成

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

## 数据流

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

按键明细模式会额外将事件加入内存明细队列，并随 flush 批量写入 `key_events`。

## 权限

`CGEventTap` 监听全局键盘事件需要 Input Monitoring 权限。

Core 要求：

- 启动监听前检查权限
- daemon 启动后再次检查权限
- 运行中权限被撤销时停用 event tap
- 状态进入 `permission_required`

Accessibility 首版不是必需权限，仅作为后续增强窗口上下文的能力。

## 前台应用识别

首版通过 `NSWorkspace` 获取前台应用名称和 bundle id。

失败时统一写入：

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

## SQLite 运行参数

```sql
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA foreign_keys = ON;
```

写入策略：

- daemon 是唯一写入者
- 单写者队列串行执行写入
- `minute_stats` 和 `key_usage_stats` 使用 `INSERT ... ON CONFLICT ... DO UPDATE`
- flush 使用事务
- CLI / Lite 查询使用只读连接

## 聚合策略

- 每次按键实时进入内存聚合
- 默认每分钟 flush 到 SQLite
- `minute_stats` 和 `key_usage_stats` 是聚合事实表
- `daily_stats` 是查询加速表，可从聚合事实表重建
- daemon 启动时补齐最近 7 天缺失的 `daily_stats`

