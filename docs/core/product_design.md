# Core Product Design

## Positioning

Core is Keystats' shared capability layer. It is provided as a Swift Package for Keystats Lite. It is not directly exposed to end users, but it defines the product's statistics capabilities, privacy boundaries, and data reliability.

## Core Goals

- Listen to global keyboard events on macOS
- Store aggregate statistics by default, not key sequences that could reconstruct input content
- Support statistics by time, app, key category, and individual key
- Provide the data foundation for key rankings and future keyboard heatmaps
- Store all data locally, with no server upload

## Statistics Modes

| Mode | Default State | Stored Data | Use Case |
|------|---------------|-------------|----------|
| Aggregate statistics mode | Enabled by default | Aggregated counts by time, app, key category, and individual key | Daily use with the lowest privacy risk |
| Key detail mode | Manually enabled by the user | Per-key event details, including key code, key name, modifiers, and foreground app | Deep analysis, debugging, personal research |

## Privacy Principles

- The default mode records aggregate counts for individual keys, but not key order
- The default mode does not store a per-event timeline
- Key detail mode must be explicitly enabled by the user and confirmed a second time
- Detail data is retained for 7 days by default and can be manually cleared
- Aggregate data is retained for 90 days by default
- Data is stored locally only

## App-Level Statistics

Core records foreground app context:

- `app_bundle_id`
- `app_name`

When the foreground app cannot be identified:

- `app_bundle_id = unknown`
- `app_name = Unknown`

## Key Rankings And Heatmaps

In the default aggregate statistics mode, Core stores per-key aggregate data for:

- Global key rankings
- App-filtered key rankings
- Time-range-filtered key rankings
- Future keyboard heatmaps

Heatmaps use hardware `key_code` as the primary identity. `key_name` is only a display label, which prevents input method or keyboard layout changes from breaking historical aggregation.
