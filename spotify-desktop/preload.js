const { contextBridge, ipcRenderer } = require('electron');

// Exposed on window.desktop in the renderer. Kept tiny and explicit so the
// renderer never gets direct access to Node or ipcRenderer.
contextBridge.exposeInMainWorld('desktop', {
  minimize: () => ipcRenderer.send('window:minimize'),
  toggleMaximize: () => ipcRenderer.send('window:toggle-maximize'),
  close: () => ipcRenderer.send('window:close'),
  onMaximizeChange: (cb) => ipcRenderer.on('window:maximized', (_e, isMax) => cb(isMax)),
  // tray <-> renderer: report what's playing, and receive mini-control commands
  updateNowPlaying: (info) => ipcRenderer.send('np:update', info),
  onTrayCommand: (cb) => ipcRenderer.on('tray:command', (_e, cmd) => cb(cmd))
});
