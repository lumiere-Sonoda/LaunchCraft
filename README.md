# LaunchCraft

> A native SwiftUI GUI for macOS launchd. Schedule shell scripts without touching a plist — free, open-source Lingon alternative.

![macOS](https://img.shields.io/badge/macOS-26.5%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Who is this for?

- You always look up `crontab` syntax before writing it
- You used Lingon but moved on after it went paid
- You find launchd plist files tedious to write by hand
- You want to manage background scripts without leaving a GUI

---

## UI Overview

```
┌─────────────────────────────────────────────────────────┐
│  LaunchCraft                        + ↺ ⌨  …           │
├──────────────────┬──────────────────────────────────────┤
│  Jobs (3)        │  Git pull                            │
│                  │                                      │
│  ● Git pull      │  Basic                               │
│    Daily 09:00   │    Name ──────────────────────────   │
│    Next: 09:00   │    Enabled  ✓                        │
│                  │    Label  com.launchcraft.xxxxxx      │
│  ● Log cleanup   │    Last run  06/22 09:00  ✓ Success  │
│    Every 30 min  │                                      │
│    Next: in      │  Script                              │
│      12 min      │    Inline  │  File                   │
│                  │    ┌────────────────────────────┐   │
│  ○ Backup        │    │ #!/bin/zsh                 │   │
│    Sun 03:00     │    │ git -C ~/project pull      │   │
│    Disabled      │    └────────────────────────────┘   │
│                  │                                      │
│  + Add job       │  Schedule  launchd / cron            │
│                  │                                      │
│                  │  [ Test run ] [ Run now ]            │
│                  │  [ View logs ] [  Save & Register ▶ ]│
├──────────────────┴──────────────────────────────────────┤
│ ⌨  Test run: Git pull                                   │
│  $ /bin/zsh /tmp/launchcraft-test-xxxx.sh               │
│  Already up to date.                                    │
│  ― Exit code 0 ―                                        │
└─────────────────────────────────────────────────────────┘
```

---

## Features

### Scheduling (two modes)

**launchd easy mode** (default) — just pick from dropdowns.

| Setting | Result |
|---|---|
| Every 30 minutes | `StartInterval = 1800` |
| Daily at 09:00 | `StartCalendarInterval = {Hour=9, Minute=0}` |
| Mon/Wed/Fri at 09:00 | 3-entry array |
| 1st of month at 03:00 | `{Day=1, Hour=3, Minute=0}` |

**cron mode** — write the expression you already know; LaunchCraft converts it to launchd automatically.

```
*/5 * * * *   →  {Minute:0}, {Minute:5}, …, {Minute:55}  × 12 entries
0 9 * * 1-5   →  weekdays 9:00 × 5 entries
* * * * *     →  StartInterval = 60 (every minute)
```

### Scripts
- **Inline editor** — write code directly in the app
- **File picker** — point to an existing `.sh` (or any script)
- Interpreter selector (zsh / bash / python3 / ruby / perl …)
- Environment variables, working directory, arguments
- PATH automatically includes `/opt/homebrew/bin`

### Running & Logs
- **Test run** — run the current script live without saving; output streams to the bottom console
- **Run now** — trigger a registered job immediately via `launchctl kickstart`
- **Log viewer** — stdout / stderr tabs, line numbers, file size, 2-second auto-refresh, log clear
- **Execution history** — last run timestamp and exit code (success / failure) shown in the editor
- **Next run time** — sidebar shows "Next: 09:00" or "in 12 min" in real time
- **plist preview** — inspect the generated launchd XML without leaving the app

### Job management
- **Import / Export** — save and restore jobs as JSON (great for backups and machine migration)
- Enable / disable with one click
- RunAtLoad and KeepAlive options
- Deleting a job cleans up its plist, script, and logs

---

## How it works

LaunchCraft only manages jobs it created. It never touches other LaunchAgents.

```
~/Library/Application Support/LaunchCraft/
├── jobs/     ← job settings as JSON (source of truth)
├── scripts/  ← inline scripts written as .sh files
└── logs/     ← stdout / stderr logs

~/Library/LaunchAgents/
└── com.launchcraft.<uuid>.plist  ← launchd definition generated from JSON
```

| Action | launchctl command |
|---|---|
| Save & Register | `bootstrap gui/$UID <plist>` |
| Enable / Disable | `enable / disable gui/$UID/<label>` |
| Run now | `kickstart -k gui/$UID/<label>` |
| Delete | `bootout gui/$UID/<label>` |

---

## Build & Run

```sh
git clone https://github.com/lumiere-Sonoda/LaunchCraft.git
open LaunchCraft/AutoShell-execer.xcodeproj
# Press ⌘R in Xcode
```

**Requirements:** macOS 26.5+ / Xcode 26.5+

> **App Sandbox is disabled** (required for launchd control).  
> Hardened Runtime is enabled, so Developer ID distribution + notarization is fully supported.

<details>
<summary>Notarization steps</summary>

```sh
# 1) Store your App-specific password once
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "your@appleid.com" --team-id "XXXXXXXXXX" \
  --password "xxxx-xxxx-xxxx-xxxx"

# 2) Archive → export → zip
xcodebuild -project AutoShell-execer.xcodeproj -scheme AutoShell-execer \
  -configuration Release -archivePath build/LaunchCraft.xcarchive archive
xcodebuild -exportArchive -archivePath build/LaunchCraft.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist
ditto -c -k --keepParent "build/export/AutoShell-execer.app" "build/LaunchCraft.zip"

# 3) Submit and staple
xcrun notarytool submit "build/LaunchCraft.zip" --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "build/export/AutoShell-execer.app"
```

`ExportOptions.plist`:
```xml
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>XXXXXXXXXX</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
```
</details>

---

## Known limitations

- Extended cron syntax (`L`, `W`, `#`) is not supported
- Combining day-of-month and day-of-week uses AND semantics in launchd (vs. OR in cron)
- Importing LaunchAgents created by other apps is not supported (by design — LaunchCraft only manages its own jobs)

---

## License

MIT
