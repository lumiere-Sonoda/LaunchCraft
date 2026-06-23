# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**LaunchCraft** is a native SwiftUI macOS GUI for managing launchd (the system job scheduler). Users create, schedule, and run shell scripts without touching plist files—a free, open-source Lingon alternative. The app manages its own jobs only; it never touches LaunchAgents created by other applications.

### Key Facts

- **Language**: Swift 6.0 (SwiftUI、Swift 6 言語モード。既定 MainActor 分離 + Approachable Concurrency。モデル/サービス層は `nonisolated`)
- **Minimum OS**: macOS 26.5
- **Build System**: Xcode (single scheme: `AutoShell-execer`, configs: Debug/Release)
- **App Sandbox**: Disabled (required to control launchd)
- **Hardened Runtime**: Enabled (supports Developer ID + notarization)
- **No test suite currently**

---

## Build & Run

```bash
# Build and run in Debug mode (from Xcode)
⌘R  (or xcodebuild -scheme AutoShell-execer -configuration Debug build)

# Build for Release (notarization)
xcodebuild -scheme AutoShell-execer -configuration Release build
```

For notarization, see README.md for full steps. App requires Developer ID signing.

---

## Architecture

### Data Flow

```
User action (add/edit/delete job)
  ↓
JobStore.swift (state mutation + persist to JSON)
  ↓
~/Library/Application Support/LaunchCraft/jobs/*.json (source of truth)
  ↓
LaunchAgent.swift (generate plist)
  ↓
~/Library/LaunchAgents/com.launchcraft.<uuid>.plist
  ↓
LaunchctlService.swift (bootstrap/enable/disable/kickstart)
  ↓
macOS launchd
```

### Layer Structure

**Models/** (`Models/Job.swift`, `Models/JobBundle.swift`, `Models/Paths.swift`)
- `ShellJob`: Codable job definition (schedule, script, environment, options)
- `JobRuntimeState` / `JobRunInfo`: launchd status + last execution metadata
- `Paths`: centralized file path management (AppSupport, LaunchAgents, logs)

**Store/** (`Store/JobStore.swift`)
- Single `@MainActor @Observable final class JobStore`
- **Critical**: Uses `@Observable` macro (not `ObservableObject`), because project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` globally
- Owns the canonical job list (`jobs: [ShellJob]`) and runtime state (`states: [UUID: JobRuntimeState]`)
- Key methods: `load()` (read JSON), `saveAndSync(_:)` (persist + launchctl sync), `setEnabled(_:for:)` (toggle), `runNow(_:)` (two-path: launchctl kickstart for enabled, direct shell execution for disabled)
- `refreshAllStates()` polls launchd status via LaunchctlService

**Services/** (no singletons—all stateless)
- `LaunchctlService.swift`: wrapper over `launchctl` CLI (bootstrap, enable, disable, kickstart, list)
- `ShellRunner.swift`: executes shell commands with parallel stdout/stderr capture (avoids 64KB deadlock)
- `CronTranslator.swift`: converts cron expressions to launchd `StartCalendarInterval` arrays (handles cron OR semantics for day/weekday)
- `NextRunCalculator.swift`: computes next execution time for display (strict date matching vs. rounding)
- `LaunchAgent.swift`: generates plist XML from `ShellJob` (handles inline script generation)

**Views/**
- `ContentView.swift`: main window (sidebar job list + editor pane + terminal panel)
- `MenuBarMenuView.swift`: menu bar extra panel (2-pane design: full list with ▶ run + status toggle)
- `JobEditorView.swift`: form for job name, enabled, label, script (inline/file), schedule builder, env vars, working dir, etc.
- `ScheduleEditorView.swift`: launchd easy mode (interval/daily/weekly dropdowns)
- `CronBuilderView.swift`: cron expression text editor with validation
- `LogViewerView.swift`: stdout/stderr tabs with line numbers, file size, 2-second auto-refresh
- `TerminalPanelView.swift`: live output for test runs (feeds from `TerminalConsole`)

**AppDelegate.swift**
- Implements menu bar residency: .regular (Dock visible) while main window open, .accessory (Dock hidden) when closed
- Monitors `NSWindow.didBecomeKey` / `willClose` to toggle activation policy

**LaunchCraftApp.swift** (entry point)
- Creates shared `@State private var store = JobStore()` instance
- Injects into both `WindowGroup` (main) and `MenuBarExtra` scenes
- MenuBarExtra uses `.window` style (panel, not popover)

### Critical Implementation Details

**1. @Observable Requirement**
- All state classes must use `@MainActor @Observable final class` (no `@Published`, use `@ObservationIgnored` for internals)
- Views use `@State` + `.environment(store)` / `@Environment(JobStore.self)` + `@Bindable` for two-way binding
- No `@StateObject` / `@EnvironmentObject` / `@ObservedObject`

**2. MenuBarExtra Display**
- Menu bar panel's `ScrollView` must have a **fixed `height`**, not `maxHeight`, or it collapses (ideal scroll height is ~0)
- Solution: render full list if ≤6 jobs (natural height), use `ScrollView.frame(height: 320)` if >6 (avoids crushing)
- TimelineView periodic refresh (3s interval) ensures menu re-reads store updates that might be missed on first body evaluation

**3. Job Execution (Two Paths)**
- **Enabled job**: `launchctl kickstart -k gui/$UID/<label>` via LaunchctlService
- **Disabled job**: no plist registered, so kickstart fails → fall back to `runDirect` (ShellRunner.runCapture + append to log file)
- Enabled jobs always log to `~/Library/Application Support/LaunchCraft/logs/<job-id>.{stdout,stderr}`; disabled jobs append after direct execution

**4. Cron ↔ Launchd Conversion**
- Cron uses OR semantics for day-of-month vs. day-of-week; launchd uses AND (limitation documented in README)
- `CronTranslator` expands `*/5 * * * *` to 12 separate minute entries (launchd has no interval mode for <60s)
- `NextRunCalculator` uses `.strict` date matching (not `.nextTime` rounding) to align display with actual launchd behavior

**5. File Paths**
- All user data under `~/Library/Application Support/LaunchCraft/`
- All launchd plists under `~/Library/LaunchAgents/` with label prefix `com.launchcraft.<uuid>`
- Old projects may use `AutoShell-execer` in support dir; check `Paths.swift` for the canonical directory name

---

## Common Development Tasks

### Add a new job option (e.g., RunAtLoad, KeepAlive)
1. Add field to `ShellJob` (Models/Job.swift) — must be `Codable`
2. Update `LaunchAgent.writePlist()` to include it in generated XML
3. Add UI control to `JobEditorView` (Views/JobEditorView.swift)
4. If it affects "next run time", update `NextRunCalculator.nextRunLabel()`

### Modify schedule behavior
- **Launchd easy mode**: edit `ScheduleEditorView.swift` dropdowns
- **Cron mode**: edit `CronTranslator.swift` expansion logic (and add test cases if tests existed)
- Always test against actual `launchctl list` output after `saveAndSync()`

### Add menu bar feature
- Edit `MenuBarMenuView.swift` or `MenuBarJobRow` (the per-job row component)
- Remember: TimelineView periodic clause forces `.task` and read inside closure, not at body top level
- Test with both small (≤6) and large (>6) job counts to check ScrollView behavior

### Test a launchd interaction
- Use `LaunchctlService.list()` to inspect raw plist status
- Check actual files: `ls ~/Library/LaunchAgents/com.launchcraft.*.plist`
- Monitor logs in `~/Library/Application Support/LaunchCraft/logs/`
- Remember: disabled jobs have no plist; enabled jobs' actual behavior may lag UI state by ~1 second

---

## Key Constraints & Gotchas

1. **Sandbox disabled** — don't re-enable it; launchd control requires full file system access
2. **Type name collision** — use `ShellJob`, not `Job` (collides with Swift Concurrency's `_Concurrency.Job`)
3. **MenuBarExtra doesn't reliably re-read store changes** on first view appearance → use TimelineView periodic refresh as workaround
4. **launchctl command execution is blocking** → all LaunchctlService calls are `async` but block the actor thread; keep them out of hot paths
5. **Cron ↔ Launchd mismatch** on weekday+monthday logic (AND vs. OR); document to users if both are set
6. **Disabled jobs run directly with `await`** → long-running jobs freeze the UI slightly; consider spinning off background task if needed

---

## Notarization

See README.md for full notarization steps. Key points:
- Requires Developer ID signing (not local development signing)
- Must use `Release` configuration
- Hardened Runtime already enabled
- App Sandbox disabled (this is intentional and necessary)

---

## References

- **README.md**: Feature overview, UI diagrams, usage scenarios
- **README.ja.md**: Japanese localization of README
- **Xcode project settings**: Check Build Phases and Entitlements.plist for sandbox/hardening status
