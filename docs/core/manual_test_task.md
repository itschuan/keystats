# Core Manual Test Tasks

- Verify on a real macOS 13+ machine that `CGEventTap` can capture global keyboard events
- Revoke Input Monitoring permission and verify the event tap is disabled
- Re-authorize and verify listening can recover
- Change keyboard layouts and verify `key_code` statistics remain continuous while `key_name` only changes as a display label
- Switch between VS Code, Terminal, and Safari, then verify foreground app detection is correct
- When the foreground app cannot be identified, verify `unknown` / `Unknown` is written
- Type heavily for 5 minutes and observe CPU, memory, and SQLite write stability
- Force-kill the process and restart it, then verify unflushed data handling and daily aggregation backfill
- Enable detail mode and verify the privacy warning and second confirmation
- Wait for or simulate expiration time and verify detail data cleanup

