# CLI 产品设计

## 定位

Keystats CLI 是首发开源版本，面向开发者和终端用户，用于验证核心能力并建立社区使用基础。

## 用户价值

- 查看今日键盘使用量
- 查看本周趋势
- 查看按键类别分布
- 查看应用维度统计
- 查看按键排行
- 以本地 daemon 方式长期记录

## 核心命令

| 命令 | 用途 |
|------|------|
| `keystats start` | 启动后台统计 |
| `keystats pause` | 暂停统计 |
| `keystats resume` | 恢复统计 |
| `keystats stop` | 停止后台统计 |
| `keystats status` | 查看 daemon 状态 |
| `keystats doctor` | 检查权限、数据库、LaunchAgent 状态 |
| `keystats today` | 查看今日概览 |
| `keystats week` | 查看本周趋势 |
| `keystats stats --period 7d` | 查看详细统计 |
| `keystats keys --period today` | 查看按键排行 |
| `keystats mode` | 查看当前统计模式 |
| `keystats mode detail` | 切换到按键明细模式 |
| `keystats clear` | 清除本地统计数据 |

## 首次使用流程

```bash
brew install keystats
keystats doctor
# 按提示授予 Input Monitoring 权限
keystats start
keystats today
```

## 隐私交互

- 默认使用数字统计模式
- 切换 detail 模式必须二次确认
- `clear` 删除数据前必须二次确认
- 权限不足时不展示误导性零数据，应展示权限状态

