# Simple DLL Injector (Windows)

A minimal, well-commented Windows DLL injector using the classic
`CreateRemoteThread` + `LoadLibraryA` technique. Useful for game modding,
debugging, instrumentation, and learning how Windows process/memory APIs work.

> **Use responsibly.** Only inject into processes you own or are explicitly
> authorized to modify. Injecting into software you don't control may violate
> its terms of service or anti-cheat/anti-tamper policies. This is provided for
> education and legitimate development/testing.

## Files

| File             | Purpose                                                    |
| ---------------- | ---------------------------------------------------------- |
| `injector.cpp`   | The injector. Takes a target and a DLL path.               |
| `sample_dll.cpp` | A test payload DLL that pops a message box when loaded.    |
| `build.bat`      | Builds both with MSVC or MinGW, whichever is on PATH.      |

## How it works

1. **Find the target** — by process name (`notepad.exe`) or numeric PID.
2. **`OpenProcess`** — get a handle with rights to allocate memory and create a thread.
3. **`VirtualAllocEx`** — reserve memory *inside the target* for the DLL path string.
4. **`WriteProcessMemory`** — copy the full DLL path into that memory.
5. **`GetProcAddress(LoadLibraryA)`** — resolve `LoadLibraryA` in `kernel32.dll`
   (mapped at the same address in every process this boot).
6. **`CreateRemoteThread`** — start a thread in the target whose entry point is
   `LoadLibraryA`, passing our path. The target loads the DLL and runs its `DllMain`.

## Build

You need either the Visual Studio C++ tools (MSVC) or MinGW-w64.

**With MSVC** — open a *Developer Command Prompt for VS* and run:

```bat
build.bat
```

Or manually:

```bat
cl /EHsc /W4 injector.cpp
cl /LD /EHsc sample_dll.cpp /Fe:sample.dll
```

**With MinGW-w64:**

```sh
g++ -std=c++17 -municode -O2 injector.cpp -o injector.exe
g++ -shared -O2 sample_dll.cpp -o sample.dll
```

> **Bitness must match.** A 64-bit injector can only inject into 64-bit
> processes, and a 32-bit injector only into 32-bit processes. Use the x64
> Developer Command Prompt for 64-bit targets, the x86 one for 32-bit targets.

## Usage

```
injector.exe <process.exe | pid> <path\to\payload.dll>
```

Examples:

```bat
REM Test it: launch Notepad, then inject the sample DLL
start notepad.exe
injector.exe notepad.exe sample.dll

REM Or target by PID
injector.exe 1234 C:\mods\hook.dll
```

If it worked with the sample DLL, a "DLL injected successfully!" message box
appears from inside the target process.

## Troubleshooting

- **`OpenProcess failed (error 5: Access denied)`** — run the injector as
  Administrator, and make sure the injector and target are the same bitness.
- **`LoadLibrary returned 0 in the target`** — usually a bitness mismatch
  between the DLL and the target, or the DLL has unmet dependencies. Rebuild
  the DLL for the correct architecture.
- **`DLL not found`** — pass a path that exists; the injector resolves it to an
  absolute path before injecting.
- **Antivirus flags it** — `CreateRemoteThread` injection is a common malware
  pattern, so AV/EDR may warn. Expected for this technique; add an exclusion in
  your own dev environment if needed.

## Writing your own payload

Replace the body of `DllMain` in `sample_dll.cpp`. Keep `DllMain` itself light —
don't call much from inside it (loader-lock rules). For real work, spin up your
own thread from `DLL_PROCESS_ATTACH`:

```cpp
case DLL_PROCESS_ATTACH:
    DisableThreadLibraryCalls(hModule);
    CreateThread(nullptr, 0, MyWorker, nullptr, 0, nullptr);
    break;
```
