<div align="center">

# fsociety injector

**A Command Prompt DLL injector.**
A real console app — the window *is* cmd. Typed commands · `LoadLibrary` · x64.

</div>

---

## What it is

A DLL injector that runs as a real **.NET console application**, so it lives in
an actual Command Prompt window — genuine cmd chrome, fonts, scrollbar,
right-click Mark/Copy/Paste, and line-editing/history. Double-click it and it
opens its own console; run it from an existing `cmd` and it uses that one.

Under the hood it's the classic, fully documented **remote-thread `LoadLibrary`**
technique — no anti-cheat bypasses, no obfuscation, no detection evasion.

```
Microsoft Windows [Version 10.0.22631.4460]
(c) Microsoft Corporation. All rights reserved.

C:\Windows\system32>list

   PID     ARCH   PROCESS / PATH
   ------  -----  --------------------------------------------
   8241    x64    C:\Program Files (x86)\Roblox\Versions\...\RobloxPlayerBeta.exe
   1104    x64    C:\Windows\explorer.exe
   9012    x86    C:\Windows\SysWOW64\notepad.exe

C:\Windows\system32>dll inject
DLL path: C:\payloads\dely_payload.dll
Process path: C:\Program Files (x86)\Roblox\Versions\...\RobloxPlayerBeta.exe
  [*] injecting dely_payload.dll -> RobloxPlayerBeta.exe (8241)...
  [+] Injected dely_payload.dll into RobloxPlayerBeta (8241).

C:\Windows\system32>_
```

The DLL path and process path are **remembered between runs** — the next time
you run `dll inject`, each prompt is pre-filled with your last choice, so you
can just press Enter to reuse it (or edit it). Stored in
`%APPDATA%\fsociety\injector.json`.

## Commands

The injector's own verbs:

| command        | what it does                                                    |
| -------------- | -------------------------------------------------------------- |
| `dll inject`   | inject a DLL — prompts for the DLL path, then the process path |
| `list` / `ls`  | enumerate running processes with their full exe paths          |
| `refresh`      | re-scan processes                                              |
| `help`         | list commands                                                  |
| `exit`         | close                                                          |

**Injecting:** type `dll inject`, paste the payload's `.dll` path, then paste
the target process's `.exe` path (copy one from `list`). The injector finds the
running process at that path and loads the DLL into it. One-liner also works:
`dll inject C:\path\payload.dll`, then paste the process path.

Status tags: `[+]` success (green), `[x]` error (red), `[*]` progress (grey).
Errors carry the real Win32 reason, so a failed inject tells you *why*.

### Real cmd built-ins

Because the window *is* a Command Prompt, the built-ins you reach for by habit
work like the real thing:

| command             | what it does                                                       |
| ------------------- | ----------------------------------------------------------------- |
| `color`             | set screen colours — `color 0a` (black bg, light-green fg), etc.   |
| `cls`               | clear the screen                                                   |
| `title`             | set the window title — `title fsociety`                            |
| `echo`              | print a message; `echo off` / `echo on` / `echo.`                 |
| `cd` / `chdir`      | change directory (drives the prompt); bare `cd` prints it         |
| `dir`               | list the current directory                                        |
| `prompt`            | change the prompt with `$`-codes — `prompt $P$G`, `prompt $T$G`   |
| `set`               | list, filter (`set PATH`), or assign (`set X=1`) env vars          |
| `date` / `time`     | show the date / time (`/t` for the value alone)                   |
| `ver`               | print the Windows version banner                                  |
| `whoami` / `hostname` | current user / machine name                                     |
| `pause`             | *Press any key to continue . . .*                                 |

`color` takes the real two-hex-nibble attribute (background nibble, then
foreground) from cmd's 16-colour table — so `0A` is the classic black-on-green,
`1F` is bright-white-on-blue, and same-fg-and-bg is refused just like cmd. Bare
`color` restores the default `07`. The prompt honours the usual `$P $G $T $D $N
$$` codes, and `cd` updates the `$P` part live.

## Build & run

Requires the **.NET 8 SDK** and **Windows**.

```powershell
cd Injector
dotnet build -c Release
.\bin\Release\net8.0-windows\FsocietyInjector.exe
```

Or open `Injector.sln` in Visual Studio 2022 and press F5. The
`requireAdministrator` manifest makes Windows prompt for elevation, and the
console's title bar then reads **Administrator: Command Prompt**.

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
├─ FsocietyInjector.csproj  · net8.0-windows, console (Exe), x64
├─ app.manifest            · requireAdministrator + per-monitor DPI
├─ Program.cs              · the console REPL + command interpreter
├─ Models/ProcessModel.cs
├─ Native/Native.cs        · kernel32 P/Invoke
└─ Services/
   ├─ ProcessService.cs    · enumerate + bitness + exe path
   └─ InjectionService.cs  · the inject itself
```

## Notes & limits

- **x64 only.** A 64-bit process needs a 64-bit DLL; that's what this build
  targets. `dll inject` refuses a 32-bit target with a clear message.
- Some anti-cheats block `CreateRemoteThread` / handle opening; this tool makes
  no attempt to work around that — it just reports the Win32 error it got back.
- Standard developer/modding tool. Only inject DLLs you trust into processes
  you're allowed to modify.
