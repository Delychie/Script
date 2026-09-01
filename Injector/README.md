<div align="center">

# 🐾 mrrpbot society injector

**A clean, modern Windows DLL injector.**
Neon-night WPF UI · one-click `LoadLibrary` injection · x64.

</div>

---

## What it is

A polished desktop injector for loading a DLL into a running process — the
companion tool for the scripts in this repo. It uses the classic, fully
documented **remote-thread `LoadLibrary`** technique: no anti-cheat bypasses,
no obfuscation, no detection evasion — just the standard injection recipe with
a nice face on it.

<div align="center">

```
┌──────────────────────────────────────────────────────────────┐
│  🐾 mrrpbot society          DLL INJECTOR              — ✕     │
│ ─────────────────────────────────────────────────────────────│
│                                                                │
│  TARGET PROCESS      12 running     PAYLOAD DLL                │
│  ┌───────────────────────────┐    ┌──────────────────┐ ┌────┐ │
│  │ 🔎 Search processes…      │    │ C:\…\payload.dll │ │ …  │ │
│  ├───────────────────────────┤    └──────────────────┘ └────┘ │
│  │ • RobloxPlayerBeta   x64  │                                 │
│  │   RobloxPlayerBeta · 8241 │      ╔══════════════════════╗   │
│  │ • notepad            x64  │      ║      ⚡ INJECT        ║   │
│  │ • explorer           x64  │      ╚══════════════════════╝   │
│  └───────────────────────────┘    ACTIVITY                     │
│                                   ┌──────────────────────────┐ │
│                                   │ 12:04:11 ✓ Injected …    │ │
│  ● ready              mrrpbot society · v1.0 · x64            │ │
└──────────────────────────────────────────────────────────────┘
```

</div>

## Features

- **Live process picker** — searchable, auto-sorted (Roblox floats to the top),
  each row tagged with its architecture (`x64` / `x86`).
- **Architecture guard** — warns you before you try to inject into a 32-bit
  target from this 64-bit build (that can never work).
- **One-click inject** with a readable activity log — every step reports a real
  Win32 reason on failure instead of a bare "failed".
- **Custom neon-night chrome** — borderless rounded window, society
  violet→pink gradient, vector mrrpbot mascot (no external image needed).
- **Runs elevated** — the manifest requests administrator so `OpenProcess` /
  `CreateRemoteThread` don't die with "Access is denied".

## Build

Requires the **.NET 8 SDK** and **Windows** (WPF is Windows-only).

```powershell
cd Injector
dotnet build -c Release
# or open MrrpInjector.sln in Visual Studio 2022 and press F5
```

The output lands in `Injector/bin/Release/net8.0-windows/MrrpInjector.exe`.

> Building from source? Just run it — the `requireAdministrator` manifest makes
> Windows prompt for elevation automatically.

## Use

1. Launch **MrrpInjector.exe** (accept the UAC prompt).
2. Pick the target in the left list (type to filter).
3. **Browse…** to the `.dll` you want to load.
4. Hit **INJECT**. Watch the activity log for the result.

## How injection works

Standard five-step remote-thread load:

1. `OpenProcess` the target with the rights needed to write + spawn a thread.
2. `VirtualAllocEx` a page inside it and `WriteProcessMemory` the DLL path there.
3. `GetProcAddress` for `kernel32!LoadLibraryA` (same address across same-bitness
   processes, so ours doubles as the target's).
4. `CreateRemoteThread` at `LoadLibraryA` with the path page as its argument —
   the target loads the DLL on its own thread.
5. Wait, check the exit code, free the path page, close handles.

All of this lives in [`Services/InjectionService.cs`](Services/InjectionService.cs);
the P/Invoke signatures are in [`Native/Native.cs`](Native/Native.cs).

## Layout

```
Injector/
├─ MrrpInjector.sln
├─ MrrpInjector.csproj      · net8.0-windows, WPF, x64
├─ app.manifest            · requireAdministrator + per-monitor DPI
├─ App.xaml(.cs)           · resources + global error handler
├─ MainWindow.xaml(.cs)    · the UI + wiring
├─ Theme/
│  ├─ Colors.xaml          · society palette
│  └─ Styles.xaml          · buttons, inputs, list, cards
├─ Assets/
│  └─ Mascot.xaml          · vector mrrpbot mascot (DrawingImage)
├─ Models/ProcessModel.cs
├─ Native/Native.cs        · kernel32 P/Invoke
└─ Services/
   ├─ ProcessService.cs    · enumerate + bitness
   └─ InjectionService.cs  · the inject itself
```

## Notes & limits

- **x64 only.** A 64-bit process needs a 64-bit DLL; that's what this build
  targets. Injecting into 32-bit targets would need a separate x86 build.
- Some anti-cheats block `CreateRemoteThread` / handle opening; this tool makes
  no attempt to work around that — it just reports the Win32 error it got back.
- This is a standard developer/modding tool. Only inject DLLs you trust into
  processes you're allowed to modify.

<div align="center">

*mrrp :3 — made for the mrrpbot society*

</div>
