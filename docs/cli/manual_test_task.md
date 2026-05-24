# CLI Manual Test Tasks

- Install through Homebrew and run `keystats doctor`
- Run `keystats start` without Input Monitoring permission and verify clear guidance is printed
- Grant permission and run `keystats start`, then verify the daemon is running
- Exit the current shell and verify the daemon is still running
- Log in again and verify LaunchAgent starts the daemon automatically
- Run `keystats pause`, type text, and verify statistics do not increase
- Run `keystats resume`, type text, and verify statistics resume
- Run `keystats stop` and verify the LaunchAgent is unloaded
- Run `keystats today` and verify today's statistics are reasonable
- Run `keystats week` and verify trend output is reasonable
- Type in multiple apps, then run `keystats stats` and verify app distribution
- Run `keystats keys --app "VS Code"` and verify key rankings
- Switch to detail mode and verify second confirmation exists
- Run `keystats clear --detail` and verify second confirmation before deletion
- Revoke Input Monitoring permission and verify `status` / `doctor` can detect the problem

