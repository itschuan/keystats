# Core 自动化 / 单元测试任务

## DataStore

- 测试数据库初始化会创建所有表
- 测试 `schema_migrations` 正确记录迁移版本
- 测试 WAL / busy timeout / foreign keys 被设置
- 测试 `minute_stats` upsert 不重复插入同一 bucket
- 测试 `key_usage_stats` upsert 不重复插入同一 bucket
- 测试 `unknown` app 归一化后不会产生 nullable unique index 问题
- 测试事务失败时不会部分写入

## Aggregator

- 测试单次按键会更新分钟 bucket
- 测试单次按键会更新 key usage bucket
- 测试不同 App 会进入不同 bucket
- 测试不同小时会进入不同 key usage bucket
- 测试 detail 模式会进入明细队列
- 测试 aggregate 模式不会写入 `key_events`
- 测试 flush 后内存 bucket 被清空

## Key Classification

- 测试字母、数字、符号、功能键、修饰键分类
- 测试未知 key code 的 fallback
- 测试 `key_code` 作为稳定主键
- 测试 `key_name` 仅作为展示标签

## Retention

- 测试 `key_events` 默认 7 天过期清理
- 测试聚合数据默认 90 天保留
- 测试手动清除 detail 数据
- 测试手动清除全部本地数据

## Analyzer

- 测试 today 查询从 `minute_stats` / `key_usage_stats` 读取
- 测试 week 查询优先读取 `daily_stats`
- 测试 `daily_stats` 缺失时从事实表重建
- 测试 top apps 排序
- 测试 top keys 排序

