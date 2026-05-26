# Keystats

Keystats is a local-first macOS keyboard usage statistics tool.

It records aggregate keyboard activity on your Mac and shows lightweight usage stats such as today's total key count, top keys, top apps, and recent trends. Data is stored locally in SQLite under `~/.keystats`.

## Products

### Keystats Lite

Keystats Lite is the current primary user-facing app.

- macOS menu bar app
- Real-time total key count in the menu bar
- Today overview
- Last 7 days trend
- Top apps
- Top 10 keys
- Aggregate/detail mode switch
- Local data clearing
- Input Monitoring permission guide

### Keystats CLI

The CLI still exists as a Swift Package executable named `keystats`.

It is useful for development, diagnostics, and command-line access to the same local data store. The CLI is not the main end-user experience right now; Keystats Lite is.

## Privacy

Keystats is designed to be local-only.

- Default mode is aggregate mode.
- Aggregate mode stores counts, not key order.
- Detail mode is opt-in and stores individual key events locally.
- No network service is used for analytics.
- Data lives under `~/.keystats`.

Keystats requires macOS Input Monitoring permission because global keyboard event counting depends on `CGEventTap`.

## Requirements

- macOS 13 or later
- Xcode / Swift 5.9 or later

## Build

Build the menu bar app executable:

```bash
swift build -c release --product KeystatsLite
```

Build the CLI:

```bash
swift build -c release --product keystats
```

Run tests:

```bash
swift test
```

## Run

Run Keystats Lite from SwiftPM:

```bash
.build/release/KeystatsLite
```

Run the CLI:

```bash
.build/release/keystats help
.build/release/keystats today
.build/release/keystats keys --period today --limit 10
```

## Packaging A Local App

This repository currently uses a simple local `.app` bundle for testing Keystats Lite outside SwiftPM. The app must be signed for local macOS use, and a proper public release should use Developer ID signing and notarization.

Because this is an Input Monitoring app, macOS may require the user to explicitly allow it in:

```text
System Settings > Privacy & Security > Input Monitoring
```

If the app is not listed automatically, add the `.app` bundle manually with the `+` button.

## Project Structure

```text
Sources/
  KeystatsCore/   Shared keyboard listening, storage, aggregation, and analytics
  KeystatsLite/   SwiftUI menu bar app
  keystats/       Command-line interface
Tests/
  KeystatsCoreTests/
  KeystatsCLITests/
docs/
  core/
  lite/
  cli/
```

## Notes

The CLI documentation is still kept because the CLI target still exists. If the CLI is removed in a future product decision, `docs/cli` should be removed or folded into developer documentation at the same time.
