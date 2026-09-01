# Spotify Desktop Clone (Electron)

A faithful, fully-interactive clone of the **Spotify desktop app** interface,
packaged as a real desktop application with [Electron]. It runs in its own
frameless window with custom minimize / maximize / close controls — just like
the real PC app.

> ⚠️ This is an **educational UI mockup**. It has no real audio playback and is
> not affiliated with or connected to Spotify. Track, artist, and album names
> are fictional; the progress bar and lyrics timing are simulated.

## Features

- Three-pane desktop shell: left rail (Home / Search + Your Library), scrolling
  content area, and a Now-Playing panel.
- Bottom playback bar with working **play/pause, next/previous, shuffle,
  repeat, seek, volume, mute, and like**. Spacebar toggles play; `Ctrl+←/→`
  skip tracks.
- **Search** with live filtering plus a "Browse all" category grid.
- **Playlist / album / artist views** with a full track table; the page tints
  to match the cover art.
- **Synced lyrics panel** that highlights and auto-scrolls the active line.
- Custom Windows-style title bar with a draggable region and working window
  controls (wired through a secure `contextBridge` preload).
- Custom app icon and a **system tray** with a mini-controls menu
  (now-playing, Play/Pause, Previous, Next, Show, Quit).
- **Minimize to tray**: closing the window hides it to the tray and keeps
  playing; use the tray's **Quit** (or `Ctrl/Cmd+Q`) to exit for real.
- **Media-key support**: the keyboard's Play/Pause, Next, and Previous keys
  control playback even when the window isn't focused.

## Requirements

- [Node.js] 18 or newer (includes `npm`).

## Run it (development)

```bash
cd spotify-desktop
npm install      # downloads Electron the first time (~100 MB)
npm start        # launches the desktop app
```

## Build an installer

`electron-builder` is already configured. From the `spotify-desktop` folder:

```bash
npm run dist     # builds an installer for your current OS into ./dist
npm run pack     # builds an unpacked app into ./dist (faster, for testing)
```

| Platform | Output              |
|----------|---------------------|
| Windows  | NSIS installer `.exe` |
| macOS    | `.dmg`              |
| Linux    | `.AppImage`         |

To cross-build a Windows installer from macOS or Linux you'll need the
extra toolchain electron-builder documents (e.g. Wine); building on the
target OS is simplest.

## Project layout

```
spotify-desktop/
├── main.js            # Electron main process (window + IPC)
├── preload.js         # secure bridge exposing window.desktop
├── renderer/
│   └── index.html     # the entire UI (HTML + CSS + JS, no build step)
├── package.json
└── README.md
```

The renderer is a single self-contained HTML file, so you can also just open
`renderer/index.html` in a browser — the window controls hide themselves when
the desktop API isn't present.

[Electron]: https://www.electronjs.org/
[Node.js]: https://nodejs.org/
