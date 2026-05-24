# Core 手工测试任务

- 在 macOS 13+ 真机上验证 `CGEventTap` 能捕获全局键盘事件
- 撤销 Input Monitoring 权限后验证 event tap 停用
- 重新授权后验证监听可恢复
- 切换键盘布局后验证 `key_code` 统计连续，`key_name` 仅展示变化
- 在 VS Code、Terminal、Safari 间切换，验证前台 App 识别正确
- 无法识别前台 App 时，验证写入 `unknown` / `Unknown`
- 高频输入 5 分钟，观察 CPU、内存和 SQLite 写入是否稳定
- 强制终止进程后重启，验证未 flush 数据处理和 daily 聚合补偿
- 开启 detail 模式后验证隐私提示和二次确认流程
- 等待或模拟过期时间，验证明细数据清理

