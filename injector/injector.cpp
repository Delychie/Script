// injector.cpp
//
// A simple Windows DLL injector.
//
// Technique: the classic CreateRemoteThread + LoadLibraryA approach.
//   1. Open a handle to the target process.
//   2. Allocate memory inside the target for the DLL path string.
//   3. Write the DLL path into that memory.
//   4. Create a remote thread whose entry point is LoadLibraryA,
//      passing the address of the path we just wrote.
//   5. The target process loads the DLL, running its DllMain.
//
// LoadLibraryA lives in kernel32.dll, which is mapped at the same base
// address in every process on a given boot, so the address we resolve
// locally is valid in the target process too.
//
// This is a standard, well-documented technique used for game modding,
// debugging, instrumentation, and testing. Only inject into processes you
// own or are authorized to modify.
//
// Build (see build.bat / README.md):
//   MSVC:  cl /EHsc /W4 injector.cpp
//   MinGW: g++ -std=c++17 -municode injector.cpp -o injector.exe
//
// Usage:
//   injector.exe <process.exe | pid> <path\to\payload.dll>
// Examples:
//   injector.exe notepad.exe C:\mods\hook.dll
//   injector.exe 1234 C:\mods\hook.dll

#include <windows.h>
#include <tlhelp32.h>

#include <cstdio>
#include <cstdlib>
#include <cwchar>

// Find a process id by executable name (e.g. L"notepad.exe"), case-insensitive.
// Returns 0 if not found.
static DWORD FindProcessId(const wchar_t* processName) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return 0;
    }

    PROCESSENTRY32W entry;
    entry.dwSize = sizeof(entry);

    DWORD pid = 0;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szExeFile, processName) == 0) {
                pid = entry.th32ProcessID;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return pid;
}

// Print a Win32 error code with a human-readable message.
static void PrintLastError(const char* what) {
    DWORD code = GetLastError();
    char* msg = nullptr;
    FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<char*>(&msg), 0, nullptr);
    fprintf(stderr, "[-] %s failed (error %lu): %s", what, code,
            msg ? msg : "unknown error\n");
    if (msg) {
        LocalFree(msg);
    }
}

// Inject dllPath into the process identified by pid.
// Returns true on success.
static bool InjectDll(DWORD pid, const char* dllPath) {
    // The path must be absolute; LoadLibrary resolves it inside the target,
    // whose working directory is unknown to us. Resolve to a full path here.
    char fullPath[MAX_PATH];
    if (GetFullPathNameA(dllPath, MAX_PATH, fullPath, nullptr) == 0) {
        PrintLastError("GetFullPathName");
        return false;
    }

    if (GetFileAttributesA(fullPath) == INVALID_FILE_ATTRIBUTES) {
        fprintf(stderr, "[-] DLL not found: %s\n", fullPath);
        return false;
    }

    // Rights we need: query/create-thread/memory-ops on the target.
    const DWORD access = PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
                         PROCESS_VM_OPERATION | PROCESS_VM_WRITE |
                         PROCESS_VM_READ;

    HANDLE process = OpenProcess(access, FALSE, pid);
    if (!process) {
        PrintLastError("OpenProcess");
        fprintf(stderr, "    (try running as Administrator, and match "
                        "32/64-bit of injector and target)\n");
        return false;
    }

    bool ok = false;
    LPVOID remoteMem = nullptr;

    do {
        const SIZE_T size = strlen(fullPath) + 1;

        // Allocate space in the target for the path string.
        remoteMem = VirtualAllocEx(process, nullptr, size, MEM_COMMIT | MEM_RESERVE,
                                   PAGE_READWRITE);
        if (!remoteMem) {
            PrintLastError("VirtualAllocEx");
            break;
        }

        // Copy the path into the target.
        if (!WriteProcessMemory(process, remoteMem, fullPath, size, nullptr)) {
            PrintLastError("WriteProcessMemory");
            break;
        }

        // Resolve LoadLibraryA. Its address in kernel32 matches in the target.
        HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
        if (!kernel32) {
            PrintLastError("GetModuleHandle(kernel32)");
            break;
        }
        FARPROC loadLibrary = GetProcAddress(kernel32, "LoadLibraryA");
        if (!loadLibrary) {
            PrintLastError("GetProcAddress(LoadLibraryA)");
            break;
        }

        // Run LoadLibraryA(fullPath) in the target process.
        HANDLE thread = CreateRemoteThread(
            process, nullptr, 0,
            reinterpret_cast<LPTHREAD_START_ROUTINE>(loadLibrary), remoteMem, 0,
            nullptr);
        if (!thread) {
            PrintLastError("CreateRemoteThread");
            break;
        }

        // Wait for LoadLibraryA to return.
        WaitForSingleObject(thread, INFINITE);

        // On 32-bit targets the exit code is the HMODULE of the loaded DLL,
        // so 0 means LoadLibrary failed inside the target. (On 64-bit the
        // exit code is truncated to 32 bits and is not reliable, so we only
        // treat an explicit 0 as failure.)
        DWORD exitCode = 0;
        GetExitCodeThread(thread, &exitCode);
        CloseHandle(thread);

        if (exitCode == 0) {
            fprintf(stderr, "[-] LoadLibrary returned 0 in the target; the "
                            "DLL failed to load (check bitness/dependencies).\n");
            break;
        }

        printf("[+] Injected %s into pid %lu\n", fullPath, pid);
        ok = true;
    } while (false);

    if (remoteMem) {
        VirtualFreeEx(process, remoteMem, 0, MEM_RELEASE);
    }
    CloseHandle(process);
    return ok;
}

int wmain(int argc, wchar_t* argv[]) {
    if (argc != 3) {
        fwprintf(stderr,
                 L"Simple DLL Injector\n"
                 L"Usage: %ls <process.exe | pid> <path\\to\\payload.dll>\n"
                 L"Examples:\n"
                 L"  %ls notepad.exe C:\\mods\\hook.dll\n"
                 L"  %ls 1234 C:\\mods\\hook.dll\n",
                 argv[0], argv[0], argv[0]);
        return 1;
    }

    // First argument: either a numeric pid or an executable name.
    DWORD pid = 0;
    wchar_t* end = nullptr;
    unsigned long parsed = wcstoul(argv[1], &end, 10);
    if (end && *end == L'\0' && parsed != 0) {
        pid = static_cast<DWORD>(parsed);
    } else {
        pid = FindProcessId(argv[1]);
        if (pid == 0) {
            fwprintf(stderr, L"[-] Process not found: %ls\n", argv[1]);
            return 1;
        }
        wprintf(L"[*] Found %ls with pid %lu\n", argv[1], pid);
    }

    // Convert the DLL path (wide) to a narrow ANSI string for LoadLibraryA.
    char dllPath[MAX_PATH];
    int written = WideCharToMultiByte(CP_ACP, 0, argv[2], -1, dllPath, MAX_PATH,
                                      nullptr, nullptr);
    if (written == 0) {
        fwprintf(stderr, L"[-] DLL path could not be converted / too long.\n");
        return 1;
    }

    return InjectDll(pid, dllPath) ? 0 : 1;
}
