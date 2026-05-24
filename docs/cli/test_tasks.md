# CLI 自动化 / 单元测试任务

## Commands

- 测试 `start` 生成正确 LaunchAgent plist
- 测试 `start` 在已运行时返回当前状态
- 测试 `stop` 卸载 LaunchAgent
- 测试 `pause` 通过 IPC 发送暂停指令
- 测试 `resume` 通过 IPC 发送恢复指令
- 测试 `status` 能读取 daemon 状态
- 测试 IPC 不可用时 `status` fallback
- 测试 `doctor` 输出权限、数据库、LaunchAgent 状态
- 测试 `clear` 需要确认
- 测试 `mode detail` 需要确认或 `--confirm`

## Query Commands

- 测试 `today` 输出总按键、活跃时间、峰值小时、Top App
- 测试 `week` 输出每日趋势
- 测试 `stats --period 7d` 输出应用分布和按键类别分布
- 测试 `keys --period today` 输出按键排行
- 测试 `keys --app` 按应用过滤
- 测试 `keys --app-bundle-id` 按 bundle id 过滤
- 测试 `keys --category` 按键类别过滤
- 测试 `keys --limit` 限制输出数量

## Daemon

- 测试 daemon 启动后检查权限
- 测试权限不足时进入 `permission_required`
- 测试暂停时停用 event tap
- 测试恢复时重建 event tap
- 测试 stop 前 flush 当前 bucket
- 测试异常退出后状态文件可辅助诊断

