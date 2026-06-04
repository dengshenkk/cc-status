# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Build & Run

```bash
# Compile
swiftc \
  Sources/CCStatus/main.swift \
  Sources/CCStatus/AppDelegate.swift \
  Sources/CCStatus/SessionMonitor.swift \
  Sources/CCStatus/StatusLightView.swift \
  Sources/CCStatus/StatusLightWindow.swift \
  Sources/CCStatus/MenuBarIcon.swift \
  -o cc-status \
  -framework AppKit \
  -framework Foundation \
  -framework ServiceManagement \
  -swift-version 5

# Run (background)
nohup ./cc-status > /dev/null 2>&1 &

# Kill running instance
pkill -f './cc-status' 2>/dev/null; pkill -f 'CCStatus' 2>/dev/null

# Package DMG
pkill -f './cc-status' 2>/dev/null
rm -rf CCStatus.app CC-Status.dmg
mkdir -p CCStatus.app/Contents/MacOS
cp cc-status CCStatus.app/Contents/MacOS/
cp Sources/CCStatus/Info.plist CCStatus.app/Contents/
codesign --force --deep --sign - CCStatus.app
hdiutil create -volname "CC Status" -srcfolder CCStatus.app -ov -format UDZO CC-Status.dmg
```

No Xcode project — uses raw `swiftc` compilation. CI is in `.github/workflows/release.yml`.

## Architecture

Native Swift macOS menu bar app (no Electron, no Xcode). 6 source files under `Sources/CCStatus/`:

```
main.swift → AppDelegate → SessionMonitor (reads ~/.claude/sessions/*.json)
                         → MenuBarIcon (menu bar colored dot)
                         → StatusLightWindow → StatusLightView (floating N-light panel)
```

**Data flow**: 10fps timer in `AppDelegate.tick()` polls `SessionMonitor.updateState()` → returns `[SessionInfo]` array → passed to both `StatusLightWindow.updateSessions()` and `MenuBarIcon.updateState()` (via `SessionMonitor.aggregateState()`).

**Session detection**: Reads JSON files from `~/.claude/sessions/`, validates PID alive via `kill(pid, 0)`, then confirms process is Claude Code via two-stage check:
1. `proc_pidpath` — checks if executable path contains `/claude`
2. `ps -o command=` — checks full command line for `claude-code` / `@anthropic-ai/claude-code` (covers Node.js installations)

Only `kind=interactive` sessions shown (filters out `kind=bg` background agents).

**Window sizing**: `StatusLightWindow.sizeForSessions()` computes exact size from `lightView.circleSize`, `spacing`, `padding` constants — no hardcoded heights, guaranteed to match what `StatusLightView.lightCenters()` renders.

**Click-to-focus**: `StatusLightView` handles `mouseDown`, gets session TTY via `/usr/sbin/lsof`, walks process tree via `/bin/ps` to find terminal app (iTerm2/Terminal.app/etc), then uses AppleScript with TTY matching to select the specific window.

## Key Design Decisions

- `LSUIElement: true` in Info.plist — no Dock icon, menu bar only
- Floating window uses `.borderless` + `.floating` level + `isMovableByWindowBackground`
- Blink animation at 0.5s interval (independent timers in MenuBarIcon and StatusLightView)
- `SessionInfo` uses `Equatable` for dirty-checking to avoid redundant redraws
- Window constants (`circleSize`, `spacing`, `padding`) are defined on `StatusLightView` and referenced by `StatusLightWindow` to keep sizing in sync
- AppleScript runs on main thread (`DispatchQueue.main.async`) for reliable iTerm2/Terminal communication

## Session JSON format (Claude Code)

```json
{
  "sessionId": "abc123",
  "pid": 12345,
  "status": "busy",      // "busy" | "idle" | "waiting"
  "kind": "interactive", // "interactive" | "bg"
  "cwd": "/Users/..."
}
```

## Release

Push to `release/vX.Y.Z` branch triggers GitHub Actions → builds on macOS → creates DMG → publishes GitHub Release.
