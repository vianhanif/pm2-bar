# PM2Bar

A lightweight macOS menu bar app that mirrors `pm2 list` output in the menu bar.

## What

PM2Bar is a native macOS status bar application that displays the real-time status of PM2-managed Node.js processes. Each running daemon appears as a row with its name, status indicator dot, CPU usage, and memory consumption. The app auto-refreshes every 2 seconds and shows an error indicator when any process has errored.

## Why

- **Always visible** — See all PM2 daemon statuses at a glance without opening a terminal
- **Zero friction** — No need to run `pm2 list` or SSH into servers to check process health
- **Instant alerts** — The menu bar icon turns red when any process enters an errored state
- **Lightweight** — Pure AppKit, no Electron bloat. Uses ~20MB RAM, spawns one `pm2 list` subprocess per refresh
- **Auto-start** — Toggle "Launch at Login" to have PM2Bar survive reboots alongside PM2's own `pm2 startup` persistence

## How

Built with AppKit `NSStatusBar` and `NSMenu` (no SwiftUI). Text renders at full contrast using `NSAttributedString` with explicit `NSColor.textColor` per item.

### Architecture

```
PM2BarApp → AppDelegate → PM2MenuBarDelegate → NSStatusBar
                                    ↓
                              PM2Model
                                    ↓
                          `pm2 list --no-color`
                                    ↓
                           Parse │-delimited table
                                    ↓
                         NSAttributedString rows
```

- **PM2MenuBarDelegate** — Sets up the `NSStatusItem`, creates `NSMenu`, rebuilds on every open via `menuWillOpen`
- **PM2Model** — Runs `pm2 list --no-color` every 2 seconds, parses the box-drawing table output, finds status by scanning for known state keywords
- **LoginItemManager** — Wraps `SMAppService.mainApp` for macOS 13+ login item registration

### Menu Structure

- Header: "PM2 Daemon Monitor" (bold)
- Process rows: `name ● [cpu% | mem]` — colored dot matches status
- Footer: timestamp ("Updated 1s ago")
- Actions: Refresh (⌘R), Launch at Login (toggle), Quit (⌘Q)

### Color Mapping

| Status | Color |
|--------|-------|
| online | Green |
| errored | Red (triggers menu bar icon warning) |
| stopped | Orange |
| paused | Yellow |

### Build

```bash
# Debug
swift build
swift run

# Release
swift build -c release

# Install to ~/Applications/
mkdir -p ~/Applications/PM2Bar.app/Contents/MacOS
cp .build/release/PM2Bar ~/Applications/PM2Bar.app/Contents/MacOS/PM2Bar
codesign -s - -f ~/Applications/PM2Bar.app

# Run
open ~/Applications/PM2Bar.app
```

### Requirements

- macOS 13+ (Ventura) — `SMAppService` API for login items
- Swift 5.9+ toolchain (ships with Xcode 15 or Command Line Tools)
- `pm2` installed and in PATH (or `~/.asdf/shims/pm2`)
