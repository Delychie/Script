<div align="center">

# fsociety injector

**A Command Prompt-style Windows DLL injector.**
Black console · typed commands · one-line `LoadLibrary` injection · x64.

*hello, friend.*

</div>

---

## What it is

A DLL injector that looks and works like `cmd.exe`. No panels, no buttons —
a black console you drive by typing commands. Under the hood it's the classic,
fully documented **remote-thread `LoadLibrary`** technique: no anti-cheat
bypasses, no obfuscation, no detection evasion.

```
Microsoft Windows [Version 10.0.22631.4460]
(c) Microsoft Corporation. All rights reserved.

   com.fsociety // dll injector   v1.0  [x64]
  [+] hello, friend.
      to inject:  dll inject   then paste the dll path and the process path.
      type 'help' for all commands, 'list' to see running processes.

C:\fsociety>list

   PID     ARCH   PROCESS / PATH
   ------  -----  --------------------------------------------
   8241    x64    C:\Program Files (x86)\Roblox\Versions\...\RobloxPlayerBeta.exe
   1104    x64    C:\Windows\explorer.exe
   9012    x86    C:\Windows\SysWOW64\notepad.exe

C:\fsociety>dll inject
DLL path: C:\fsociety\bin\dely_payload.dll
Process path: C:\Program Files (x86)\Roblox\Versions\...\RobloxPlayerBeta.exe
  [*] injecting dely_payload.dll -> RobloxPlayerBeta.exe (8241)...
  [+] Injected dely_payload.dll into RobloxPlayerBeta (8241).

C:\fsociety>_
```

## Commands

| command        | what it does                                                    |
| -------------- | -------------------------------------------------------------- |
| `dll inject`   | inject a DLL — prompts for the DLL path, then the process path |
| `list` / `ls`  | enumerate running processes with their full exe paths          |
| `refresh`      | re-scan processes                                              |
| `cls`          | clear the screen                                               |
| `ver`          | version info                                                   |
| `help`         | list commands                                                  |
| `exit`         | close                                                          |

**Injecting:** type `dll inject`, paste the payload's `.dll` path when it asks,
then paste the target process's `.exe` path (copy it from `list`). The injector
finds the running process at that path and loads the DLL into it. You can also
do it in one line: `dll inject C:\path\payload.dll`, then paste the process path.

Status tags read like a console: `[+]` success (green), `[!]` warning
(yellow), `[x]` error (red), `[*]` progress (dim). Errors carry the real
Win32 reason, so a failed inject tells you *why*.

## Build

Requires the **.NET 8 SDK** and **Windows** (WPF is Windows-only).

```powershell
cd Injector
dotnet build -c Release
# or open Injector.sln in Visual Studio 2022 and press F5
```

Output: `Injector/bin/Release/net8.0-windows/FsocietyInjector.exe`. The
`requireAdministrator` manifest makes Windows prompt for elevation on launch.

## How injection works

Standard five-step remote-thread load (in [`Services/InjectionService.cs`](Services/InjectionService.cs)):

1. `OpenProcess` the target with the rights needed to write + spawn a thread.
2. `VirtualAllocEx` a page inside it and `WriteProcessMemory` the DLL path there.
3. `GetProcAddress` for `kernel32!LoadLibraryA` (same address across same-bitness
   processes, so ours doubles as the target's).
4. `CreateRemoteThread` at `LoadLibraryA` with the path page as its argument.
5. Wait, check the exit code, free the path page, close handles.

The P/Invoke signatures are in [`Native/Native.cs`](Native/Native.cs).

## Layout

```
Injector/
├─ Injector.sln
├─ FsocietyInjector.csproj  · net8.0-windows, WPF, x64
├─ app.manifest            · requireAdministrator + per-monitor DPI
├─ App.xaml(.cs)           · resources + global error handler
├─ MainWindow.xaml(.cs)    · the console window + command interpreter
├─ Theme/
│  ├─ Colors.xaml          · Command Prompt palette (conhost black)
│  └─ Styles.xaml          · window caption buttons
├─ Models/ProcessModel.cs
├─ Native/Native.cs        · kernel32 P/Invoke
└─ Services/
   ├─ ProcessService.cs    · enumerate + bitness
   └─ InjectionService.cs  · the inject itself
```

## Notes & limits

- **x64 only.** A 64-bit process needs a 64-bit DLL; that's what this build
  targets. `select` warns when you pick a 32-bit target.
- Some anti-cheats block `CreateRemoteThread` / handle opening; this tool makes
  no attempt to work around that — it just reports the Win32 error it got back.
- Standard developer/modding tool. Only inject DLLs you trust into processes
  you're allowed to modify.

<div align="center">

*our democracy has been hacked. — made for fsociety*

</div>
