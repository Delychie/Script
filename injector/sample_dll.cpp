// sample_dll.cpp
//
// A minimal payload DLL for testing the injector. When loaded into a target
// process it pops a message box, so you get visual confirmation that
// injection worked. Replace DllMain's body with your own logic.
//
// Build (see build.bat / README.md):
//   MSVC:  cl /LD /EHsc sample_dll.cpp /Fe:sample.dll
//   MinGW: g++ -shared -o sample.dll sample_dll.cpp

#include <windows.h>

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID reserved) {
    switch (reason) {
        case DLL_PROCESS_ATTACH:
            // Keep DllMain light: real work should happen on its own thread.
            // A MessageBox is fine here just as a visible proof of injection.
            DisableThreadLibraryCalls(hModule);
            MessageBoxW(nullptr, L"DLL injected successfully!",
                        L"Sample Payload", MB_OK | MB_ICONINFORMATION);
            break;
        case DLL_PROCESS_DETACH:
            break;
    }
    return TRUE;
}
