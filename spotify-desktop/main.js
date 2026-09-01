const { app, BrowserWindow, ipcMain, shell, Tray, Menu, nativeImage } = require('electron');
const path = require('path');

let win = null;
let tray = null;

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
    { label: 'Quit', click: () => { app.quit(); } }
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

app.whenReady().then(() => {
  createWindow();
  createTray();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
