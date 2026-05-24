# Lite 手工测试任务

- 首次启动 Lite，确认展示权限引导
- 未授权时确认不会展示误导性零数据
- 点击跳转系统设置，手动授予 Input Monitoring
- 授权后返回 App，确认开始统计
- 在多个 App 中输入，确认 Top Apps 更新
- 菜单栏计数随输入更新
- 最近 7 天趋势展示正常
- 切换统计模式，确认 detail 模式有二次确认
- 清除本地数据，确认有二次确认且 UI 刷新
- 撤销 Input Monitoring 权限，确认 UI 进入权限失败状态
- 重启 App，确认状态恢复正确
- 测试深色 / 浅色模式
- 测试长 App 名称显示
- 执行 App Sandbox + CGEventTap 可行性 Spike
- 准备并人工复核 App Review Notes 和隐私政策文案

