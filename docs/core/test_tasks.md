# Core Automated / Unit Test Tasks

## DataStore

- Test database initialization creates all tables
- Test `schema_migrations` records migration versions correctly
- Test WAL / busy timeout / foreign keys are configured
- Test `minute_stats` upsert does not duplicate the same bucket
- Test `key_usage_stats` upsert does not duplicate the same bucket
- Test normalized `unknown` app values avoid nullable unique index issues
- Test failed transactions do not partially write data

## Aggregator

- Test a single key event updates the minute bucket
- Test a single key event updates the key usage bucket
- Test different apps go into different buckets
- Test different hours go into different key usage buckets
- Test detail mode appends to the detail queue
- Test aggregate mode does not write `key_events`
- Test buckets are cleared after flush

## Key Classification

- Test letter, number, symbol, function key, and modifier key classification
- Test fallback behavior for unknown key codes
- Test `key_code` is used as the stable identity
- Test `key_name` is only a display label

## Retention

- Test `key_events` are cleaned after the default 7-day retention period
- Test aggregate data is retained for 90 days by default
- Test manually clearing detail data
- Test manually clearing all local data

## Analyzer

- Test today queries read from `minute_stats` / `key_usage_stats`
- Test week queries prefer `daily_stats`
- Test missing `daily_stats` can be rebuilt from fact tables
- Test top apps sorting
- Test top keys sorting

