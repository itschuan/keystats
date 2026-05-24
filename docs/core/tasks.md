# Core 开发任务

## P0

- 初始化 Swift Package 结构
- 定义 Core models：key event、key category、app context、stat bucket、daemon status
- 实现 `MigrationRunner`
- 实现 `DataStore` 初始化、迁移、连接管理
- 实现 SQLite WAL / busy timeout / foreign keys 设置
- 实现 `KeyClassifier`
- 实现 `KeyboardLayoutResolver`
- 实现 `AppContextProvider`，通过 `NSWorkspace` 获取前台应用
- 实现 `PermissionChecker`，检测 Input Monitoring / Accessibility 状态
- 实现 `KeyListener`，基于 `CGEventTap` 捕获键盘事件
- 实现 `EventTapSupervisor`，处理 event tap 失效和重建
- 实现 `StatsAggregator`
- 实现 `minute_stats` 聚合写入
- 实现 `key_usage_stats` 聚合写入
- 实现 detail 模式下 `key_events` 批量写入
- 实现 `daily_stats` 懒聚合
- 实现 `RetentionManager`，清理过期明细和聚合数据

## P1

- 实现会话检测：连续输入 vs 休息
- 实现应用统计查询
- 实现按键排行查询
- 实现 CSV / JSON 导出接口

## P2

- 支持自定义数据保留周期
- 支持排除应用
- 支持更多键盘布局展示标签

