# CLI 手工测试任务

- 通过 Homebrew 安装后运行 `keystats doctor`
- 未授权 Input Monitoring 时运行 `keystats start`，确认输出清晰引导
- 授权后运行 `keystats start`，确认 daemon 正常运行
- 退出当前 shell 后确认 daemon 仍在运行
- 重新登录后确认 LaunchAgent 自动拉起 daemon
- 运行 `keystats pause` 后输入内容，确认统计不增长
- 运行 `keystats resume` 后输入内容，确认统计恢复
- 运行 `keystats stop` 后确认 LaunchAgent 被卸载
- 运行 `keystats today` 检查今日统计合理
- 运行 `keystats week` 检查趋势输出合理
- 在多个 App 中输入，运行 `keystats stats` 检查 App 分布
- 运行 `keystats keys --app "VS Code"` 检查按键排行
- 切换 detail 模式，确认有二次确认
- 运行 `keystats clear --detail`，确认删除前有二次确认
- 撤销 Input Monitoring 权限后确认 `status` / `doctor` 能识别问题

