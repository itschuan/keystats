# Lite 技术方案

## 架构

```text
Keystats Lite
├── SwiftUI App
├── MenuBarExtra
├── TodayPanel
├── SettingsView
├── PermissionGuideView
└── KeystatsCore dependency
```

## 技术选型

- SwiftUI
- MenuBarExtra
- SQLite via KeystatsCore
- Input Monitoring 权限
- `NSWorkspace` 前台应用识别

## App Store 前置 Spike

Phase 2 开始前必须验证：

- App Sandbox + `CGEventTap` 是否可运行
- Input Monitoring 权限引导是否可接受
- App Store 审核风险
- SQLite 本地存储路径
- 开机启动方案

如果 Spike 失败，需要调整发布渠道或架构。

## 权限处理

- 首次启动展示权限引导页
- 提供跳转系统设置入口
- 授权完成后回到 App 继续启动监听
- 运行中权限撤销时显示权限失败状态

## 数据访问

Lite 通过 KeystatsCore 查询：

- 今日总按键
- 今日活跃时间
- 今日 Top Apps
- 最近 7 天趋势
- 当前统计模式

Lite 不直接操作 SQLite schema。

## 设置项

- 统计模式
- 开机自启
- 清除本地数据
- 数据保留说明
- 隐私说明

