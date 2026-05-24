# CLI 开发任务

## P0

- 初始化 CLI target
- 接入命令行参数解析
- 实现 `keystats daemon run`
- 实现 `LaunchAgentPlistBuilder`
- 实现 `LaunchAgentManager`
- 实现 `keystats start`
- 实现 `keystats stop`
- 实现 Unix domain socket IPC server
- 实现 Unix domain socket IPC client
- 实现 `keystats pause`
- 实现 `keystats resume`
- 实现 `keystats status`
- 实现 `keystats doctor`
- 实现 `keystats today`
- 实现 `keystats week`
- 实现 `keystats stats`
- 实现 `keystats keys`
- 实现 `keystats mode`
- 实现 `keystats clear`
- 输出权限不足时的引导文案
- 编写 README 首次使用和权限说明

## P1

- 支持 `keys --app`
- 支持 `keys --app-bundle-id`
- 支持 `keys --category`
- 支持 `keys --limit`
- 支持 `stats --period`
- 支持导出 CSV / JSON
- 支持排除应用配置

## P2

- 支持自定义数据目录
- 支持 debug 日志级别
- 支持自定义数据保留周期

