# PillFloat

A lightweight macOS menu bar utility that lets you reposition the [Wispr Flow](https://wispr.com) dictation pill anywhere on your screen.

Wispr Flow's dictation indicator (the "pill") is pinned to the bottom-center of your screen during voice input. This works fine most of the time, but it can overlap with other UI elements — browser tabs, terminal prompts, video calls, presentation controls, etc. PillFloat lets you move it out of the way.

## Features

- **Preset positions** — Default (native), Top Center, Top Left, Top Right, Bottom Center, Bottom Left, Bottom Right
- **Drag to move** — Click and drag the pill directly on screen to reposition it
- **Visual position picker** — A minimap of your screen where you drag a pill indicator to set a custom position
- **Settings window** — All options in one place, shown on first launch
- **Launch at Login** — Start automatically when you log in
- **Update checker** — Checks GitHub for new releases (daily auto-check, toggle on/off)

## Installation

### Homebrew (recommended)

```bash
brew tap OrangeAKA/tap
brew install --cask pillfloat
```

### Build from source

Requires macOS 13+ and Xcode Command Line Tools.

```bash
git clone https://github.com/OrangeAKA/pillfloat.git
cd pillfloat
make install
```

This builds the app and copies it to `/Applications`. You can then find "PillFloat" in Spotlight.

To uninstall:

```bash
make uninstall
```

### Manual build (no install)

```bash
swift build -c release
# Binary at .build/release/PillFloat
# Or build the .app bundle:
make app
# App at build/PillFloat.app
```

### First Launch — Gatekeeper Warning

On first launch, macOS may show a warning about an "unidentified developer." This is because the app is not signed with an Apple Developer certificate.

To bypass this (one-time only):
1. Right-click (or Control-click) the app in Finder
2. Select "Open"
3. Click "Open" in the dialog

After this, the app will open normally in the future.

### Accessibility Permission

On first launch, macOS will prompt you to grant Accessibility access. Go to **System Settings → Privacy & Security → Accessibility** and enable the app.

This permission is required because PillFloat uses the macOS Accessibility API to detect and reposition the dictation pill window.

## Usage

1. Launch the app — a settings window opens on first launch, and an icon appears in the menu bar
2. Pick a preset position, drag the pill on the minimap, or just drag the pill directly on screen
3. The position persists across dictation sessions and app restarts

### Settings Window

The settings window shows on first launch and can be opened anytime from the menu bar (click icon → "Settings..." or ⌘,).

It includes:
- **Preset grid** — Default (native position) + 6 position buttons
- **Custom position minimap** — drag the pill indicator and click "Save Custom Position"
- **Enabled** — toggle the tool on/off
- **Launch at Login** — start automatically on login
- **Check for Updates Automatically** — daily check against GitHub releases
- **Check for Updates** — manual check button
- **Status** — shows whether the target app is currently running

### Menu Bar

Click the menu bar icon for quick access to:
- Position presets (with checkmarks showing active selection)
- "Settings..." to open the full window
- "Enabled" toggle
- "Quit"

When an update is available, a notification appears at the top of the menu.

### Drag to Move

During dictation, click directly on the pill and drag it anywhere on screen. When you release, the position saves automatically.

## Caveats & Known Limitations

### Top positions don't reach the very top of the screen

Wispr Flow renders the pill inside a larger transparent window (~440×300px). The actual visible pill is only a small element (~70px) at the **bottom** of this window — the rest is invisible space used for animations and state transitions.

When you select a "top" position (Top Left, Top Center, Top Right), PillFloat tries to move the window upward so only the visible pill peeks onto the screen. However, **macOS prevents windows from being positioned above the screen edge**, so the 300px window gets pinned at the top, and the visible pill ends up roughly in the upper quarter of the screen (~230px below the menu bar) rather than flush against it.

This affects all top positions equally. There is no workaround without modifying Wispr Flow itself — the transparent window size is controlled by the app and cannot be changed externally.

**Bottom positions work precisely** because the visible pill is already at the window's bottom edge — no offset needed.

**Tip:** Use the drag feature to place the pill exactly where you want within the achievable range. Drag gives you the most precise control over placement.

### Brief flicker during repositioning

Wispr Flow resets the pill position every ~400ms. PillFloat overrides it every 150ms (and instantly via Accessibility observer callbacks). You may occasionally see the pill briefly flash to its default position before snapping back to your chosen position.

### Background Activity

The app appears in **System Settings → General → Login Items & Background Activity**. This is normal behavior for menu bar utilities on macOS. The app runs silently in the background with minimal resource usage (~0.1% CPU, only active while the target app is running).

### App updates

PillFloat identifies the pill window by its title ("Status") and falls back to matching by size. If Wispr Flow changes these properties in an update, PillFloat may stop detecting the pill until updated.

### Update checker

The app can check GitHub for new releases. This is an opt-in feature (enabled by default, can be toggled off in Settings). It makes a single HTTPS request to the GitHub API — no telemetry, no tracking, no data collection.

## How It's Built

- **Swift** with Swift Package Manager — no external dependencies
- **AppKit** for the menu bar UI and settings window
- **ApplicationServices** (Accessibility API) for window detection and repositioning
- **ServiceManagement** for Launch at Login
- **NSEvent global monitor** for drag-to-move
- **URLSession** for GitHub release checking

### Architecture

| File | Purpose |
|---|---|
| `main.swift` | App entry point, accessory mode (no dock icon) |
| `AppDelegate.swift` | Menu bar, settings window lifecycle, update notifications |
| `PillWatcher.swift` | Core: find pill via AX, reposition on timer + observer, drag handling |
| `PreferredPosition.swift` | Position presets, custom absolute coords, UserDefaults persistence |
| `SettingsWindow.swift` | Settings UI with presets, minimap, toggles, update banner |
| `ScreenUtility.swift` | Screen geometry, AppKit-to-CG coordinate conversion |
| `UpdateChecker.swift` | GitHub release API, version comparison, auto-check scheduling |

## Requirements

- macOS 13 (Ventura) or later
- [Wispr Flow](https://wispr.com) installed
- Accessibility permission granted

## License

MIT
