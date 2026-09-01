const { app, BrowserWindow, ipcMain, shell, Tray, Menu, nativeImage, globalShortcut, Notification } = require('electron');
const path = require('path');

let win = null;
let tray = null;
let isQuitting = false;    // true once the user really wants to exit (tray Quit / Cmd+Q)
let trayHintShown = false; // show the "still running in the tray" note only once

// current now-playing state, mirrored from the renderer for the tray menu
let np = { title: 'Nothing playing', artist: '', playing: false };

const ICON = path.join(__dirname, 'build', 'icon.png');
const TRAY_ICON = path.join(__dirname, 'build', 'tray.png');

function createWindow() {
  win = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 940,
    minHeight: 600,
    frame: false,            // frameless — the UI draws its own title bar + controls
    backgroundColor: '#000000',
    title: 'Spotify',
    icon: ICON,
    show: false,             // avoid a white flash; show once painted
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false
    }
  });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.once('ready-to-show', () => win.show());

  // Any real outbound link opens in the user's browser rather than a new app window.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });

  const notifyMaxState = () => {
    if (win && !win.isDestroyed()) win.webContents.send('window:maximized', win.isMaximized());
  };
  win.on('maximize', notifyMaxState);
  win.on('unmaximize', notifyMaxState);
  win.on('closed', () => { win = null; });

  // Minimize-to-tray: the close button hides the window instead of quitting.
  win.on('close', (e) => {
    if (isQuitting) return;              // real quit — let it through
    e.preventDefault();
    win.hide();
    if (!trayHintShown) {
      trayHintShown = true;
      if (Notification.isSupported()) {
        new Notification({
          title: 'Still playing',
          body: 'Spotify keeps running in the tray. Right-click the tray icon for controls, or Quit to exit.',
          icon: ICON
        }).show();
      }
    }
  });
}

// ---- system tray with mini playback controls ----
function tell(cmd) {
  if (win && !win.isDestroyed()) win.webContents.send('tray:command', cmd);
}

function showWindow() {
  if (!win) { createWindow(); return; }
  if (win.isMinimized()) win.restore();
  win.show();
  win.focus();
}

function buildTrayMenu() {
  const nowLine = np.artist ? `${np.title} — ${np.artist}` : np.title;
  return Menu.buildFromTemplate([
    { label: nowLine, enabled: false },
    { type: 'separator' },
    { label: np.playing ? 'Pause' : 'Play', click: () => tell('playpause') },
    { label: 'Previous', click: () => tell('prev') },
    { label: 'Next', click: () => tell('next') },
    { type: 'separator' },
    { label: 'Show Spotify', click: showWindow },
    { label: 'Quit', click: () => { isQuitting = true; app.quit(); } }
  ]);
}

function refreshTray() {
  if (!tray) return;
  tray.setToolTip(np.artist ? `${np.title} · ${np.artist}` : 'Spotify');
  tray.setContextMenu(buildTrayMenu());
}

function createTray() {
  let img = nativeImage.createFromPath(TRAY_ICON);
  if (process.platform === 'darwin') img = img.resize({ width: 18, height: 18 });
  tray = new Tray(img.isEmpty() ? nativeImage.createFromPath(ICON) : img);
  tray.setToolTip('Spotify');
  tray.setContextMenu(buildTrayMenu());
  tray.on('click', showWindow);          // left-click opens the app (Win/Linux)
  tray.on('double-click', showWindow);
}

// ---- window-control IPC from the renderer's custom title bar ----
ipcMain.on('window:minimize', () => win && win.minimize());
ipcMain.on('window:toggle-maximize', () => {
  if (!win) return;
  win.isMaximized() ? win.unmaximize() : win.maximize();
});
ipcMain.on('window:close', () => win && win.close());

// ---- now-playing updates from the renderer, used by the tray ----
ipcMain.on('np:update', (_e, data) => {
  np = Object.assign(np, data || {});
  refreshTray();
});

// Hardware / keyboard media keys → same commands the tray and UI use.
function registerMediaKeys() {
  const map = {
    'MediaPlayPause': 'playpause',
    'MediaNextTrack': 'next',
    'MediaPreviousTrack': 'prev',
    'MediaStop': 'playpause'
  };
  for (const [accel, cmd] of Object.entries(map)) {
    try { globalShortcut.register(accel, () => tell(cmd)); } catch (_) { /* key unavailable on this OS */ }
  }
}

app.whenReady().then(() => {
  createWindow();
  createTray();
  registerMediaKeys();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
    else showWindow();
  });
});

// Cmd+Q / app.quit() from anywhere should exit for real, not hide to tray.
app.on('before-quit', () => { isQuitting = true; });
app.on('will-quit', () => { globalShortcut.unregisterAll(); });

app.on('window-all-closed', () => {
  // With minimize-to-tray the window is hidden, not closed, so this normally
  // won't fire; keep the standard behavior for an actual quit.
  if (process.platform !== 'darwin') app.quit();
});
