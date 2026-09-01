// gui.cpp
//
// A dark, modern Win32 GUI DLL injector.
//
//   * Browse for a DLL with a file dialog.
//   * See a live, searchable list of running processes.
//   * Pick one and inject with a click.
//
// Injection uses the classic CreateRemoteThread + LoadLibraryA technique
// (same as the console injector.cpp). Only inject into processes you own or
// are authorized to modify.
//
// Build (see build.bat / README.md):
//   MSVC:  cl /EHsc /O2 gui.cpp resource.res /Fe:injector-gui.exe user32.lib gdi32.lib comctl32.lib comdlg32.lib
//   MinGW: windres resource.rc -O coff -o resource.res
//          g++ -std=c++17 -municode -O2 gui.cpp resource.res -o injector-gui.exe -mwindows -lcomctl32 -lcomdlg32 -lgdi32

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <tlhelp32.h>
#include <uxtheme.h>

#include <algorithm>
#include <cstring>
#include <cwctype>
#include <string>
#include <vector>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "comdlg32.lib")
#pragma comment(lib, "uxtheme.lib")

// ---------------------------------------------------------------------------
// Palette (dark theme)
// ---------------------------------------------------------------------------
static const COLORREF kBg          = RGB(24, 24, 27);    // window background
static const COLORREF kPanel       = RGB(39, 39, 42);    // fields / list body
static const COLORREF kPanelHover  = RGB(52, 52, 57);
static const COLORREF kBorder      = RGB(63, 63, 70);
static const COLORREF kText        = RGB(228, 228, 231);
static const COLORREF kMuted       = RGB(150, 150, 158);
static const COLORREF kAccent      = RGB(99, 102, 241);  // indigo
static const COLORREF kAccentHover = RGB(120, 123, 247);
static const COLORREF kAccentDown  = RGB(80, 83, 210);
static const COLORREF kRowAlt      = RGB(32, 32, 35);
static const COLORREF kSelBg       = RGB(55, 58, 120);   // muted accent

// ---------------------------------------------------------------------------
// Control ids
// ---------------------------------------------------------------------------
enum {
    ID_DLL_EDIT = 1001,
    ID_BROWSE,
    ID_SEARCH,
    ID_REFRESH,
    ID_LIST,
    ID_INJECT,
};

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
static HFONT   g_fontTitle   = nullptr;
static HFONT   g_fontBody    = nullptr;
static HFONT   g_fontSmall   = nullptr;
static HBRUSH  g_brushBg     = nullptr;
static HBRUSH  g_brushPanel  = nullptr;

static HWND    g_hDllEdit    = nullptr;
static HWND    g_hSearch     = nullptr;
static HWND    g_hList       = nullptr;
static std::wstring g_status = L"Pick a DLL and a process, then Inject.";
static bool    g_statusErr   = false;

struct ProcInfo {
    DWORD        pid;
    std::wstring name;
};
static std::vector<ProcInfo> g_procs;   // all processes, from last refresh

// ---------------------------------------------------------------------------
// Injection (self-contained; mirrors injector.cpp)
// ---------------------------------------------------------------------------
static std::wstring InjectDll(DWORD pid, const std::wstring& dllPathW) {
    wchar_t fullW[MAX_PATH];
    if (GetFullPathNameW(dllPathW.c_str(), MAX_PATH, fullW, nullptr) == 0) {
        return L"Could not resolve DLL path.";
    }
    if (GetFileAttributesW(fullW) == INVALID_FILE_ATTRIBUTES) {
        return L"DLL not found on disk.";
    }

    char fullA[MAX_PATH];
    if (WideCharToMultiByte(CP_ACP, 0, fullW, -1, fullA, MAX_PATH, nullptr,
                            nullptr) == 0) {
        return L"DLL path could not be converted / too long.";
    }

    const DWORD access = PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
                         PROCESS_VM_OPERATION | PROCESS_VM_WRITE |
                         PROCESS_VM_READ;
    HANDLE proc = OpenProcess(access, FALSE, pid);
    if (!proc) {
        return L"OpenProcess failed. Run as Administrator and match "
               L"32/64-bit of the injector and target.";
    }

    std::wstring err;
    LPVOID mem = nullptr;
    do {
        const SIZE_T size = strlen(fullA) + 1;
        mem = VirtualAllocEx(proc, nullptr, size, MEM_COMMIT | MEM_RESERVE,
                             PAGE_READWRITE);
        if (!mem) { err = L"VirtualAllocEx failed."; break; }

        if (!WriteProcessMemory(proc, mem, fullA, size, nullptr)) {
            err = L"WriteProcessMemory failed."; break;
        }

        HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
        FARPROC loadLib = k32 ? GetProcAddress(k32, "LoadLibraryA") : nullptr;
        if (!loadLib) { err = L"Could not resolve LoadLibraryA."; break; }

        HANDLE thread = CreateRemoteThread(
            proc, nullptr, 0,
            reinterpret_cast<LPTHREAD_START_ROUTINE>(loadLib), mem, 0, nullptr);
        if (!thread) { err = L"CreateRemoteThread failed."; break; }

        WaitForSingleObject(thread, INFINITE);
        DWORD exitCode = 0;
        GetExitCodeThread(thread, &exitCode);
        CloseHandle(thread);

        if (exitCode == 0) {
            err = L"LoadLibrary returned 0 in the target (bitness mismatch or "
                  L"missing dependency).";
            break;
        }
    } while (false);

    if (mem) VirtualFreeEx(proc, mem, 0, MEM_RELEASE);
    CloseHandle(proc);
    return err;  // empty string == success
}

// ---------------------------------------------------------------------------
// Process enumeration + list population
// ---------------------------------------------------------------------------
static void RefreshProcesses() {
    g_procs.clear();
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32W e;
        e.dwSize = sizeof(e);
        if (Process32FirstW(snap, &e)) {
            do {
                if (e.th32ProcessID == 0) continue;
                g_procs.push_back({e.th32ProcessID, e.szExeFile});
            } while (Process32NextW(snap, &e));
        }
        CloseHandle(snap);
    }
    std::sort(g_procs.begin(), g_procs.end(),
              [](const ProcInfo& a, const ProcInfo& b) {
                  int c = _wcsicmp(a.name.c_str(), b.name.c_str());
                  return c ? c < 0 : a.pid < b.pid;
              });
}

static std::wstring ToLower(std::wstring s) {
    std::transform(s.begin(), s.end(), s.begin(), ::towlower);
    return s;
}

static void PopulateList() {
    wchar_t filterRaw[128] = {0};
    GetWindowTextW(g_hSearch, filterRaw, 128);
    std::wstring filter = ToLower(filterRaw);

    SendMessageW(g_hList, WM_SETREDRAW, FALSE, 0);
    ListView_DeleteAllItems(g_hList);

    int row = 0;
    for (const auto& p : g_procs) {
        if (!filter.empty()) {
            std::wstring low = ToLower(p.name);
            wchar_t pidStr[16];
            wsprintfW(pidStr, L"%lu", p.pid);
            if (low.find(filter) == std::wstring::npos &&
                std::wstring(pidStr).find(filter) == std::wstring::npos) {
                continue;
            }
        }
        LVITEMW it = {};
        it.mask = LVIF_TEXT | LVIF_PARAM;
        it.iItem = row;
        it.pszText = const_cast<wchar_t*>(p.name.c_str());
        it.lParam = static_cast<LPARAM>(p.pid);
        int idx = ListView_InsertItem(g_hList, &it);

        wchar_t pidStr[16];
        wsprintfW(pidStr, L"%lu", p.pid);
        ListView_SetItemText(g_hList, idx, 1, pidStr);
        row++;
    }

    SendMessageW(g_hList, WM_SETREDRAW, TRUE, 0);
    InvalidateRect(g_hList, nullptr, TRUE);
}

static DWORD GetSelectedPid() {
    int sel = ListView_GetNextItem(g_hList, -1, LVNI_SELECTED);
    if (sel < 0) return 0;
    LVITEMW it = {};
    it.mask = LVIF_PARAM;
    it.iItem = sel;
    ListView_GetItem(g_hList, &it);
    return static_cast<DWORD>(it.lParam);
}

static void SetStatus(const std::wstring& msg, bool err) {
    g_status = msg;
    g_statusErr = err;
    // Redraw just the status strip.
    HWND parent = GetParent(g_hList);
    RECT rc;
    GetClientRect(parent, &rc);
    RECT strip = {0, rc.bottom - 34, rc.right, rc.bottom};
    InvalidateRect(parent, &strip, TRUE);
}

// ---------------------------------------------------------------------------
// Owner-drawn buttons (flat, rounded, with hover)
// ---------------------------------------------------------------------------
struct BtnState { bool hover = false; bool accent = false; };

static LRESULT CALLBACK ButtonProc(HWND hWnd, UINT msg, WPARAM wp, LPARAM lp,
                                   UINT_PTR, DWORD_PTR ref) {
    BtnState* st = reinterpret_cast<BtnState*>(ref);
    switch (msg) {
        case WM_MOUSEMOVE:
            if (!st->hover) {
                st->hover = true;
                TRACKMOUSEEVENT tme = {sizeof(tme), TME_LEAVE, hWnd, 0};
                TrackMouseEvent(&tme);
                InvalidateRect(hWnd, nullptr, FALSE);
            }
            break;
        case WM_MOUSELEAVE:
            st->hover = false;
            InvalidateRect(hWnd, nullptr, FALSE);
            break;
        case WM_NCDESTROY:
            RemoveWindowSubclass(hWnd, ButtonProc, 0);
            delete st;
            break;
    }
    return DefSubclassProc(hWnd, msg, wp, lp);
}

static void MakeButton(HWND hBtn, bool accent) {
    BtnState* st = new BtnState();
    st->accent = accent;
    SetWindowSubclass(hBtn, ButtonProc, 0, reinterpret_cast<DWORD_PTR>(st));
}

static void DrawButton(LPDRAWITEMSTRUCT dis) {
    DWORD_PTR ref = 0;
    GetWindowSubclass(dis->hwndItem, ButtonProc, 0, &ref);
    BtnState* st = reinterpret_cast<BtnState*>(ref);

    const bool pressed = (dis->itemState & ODS_SELECTED) != 0;
    const bool hover   = st && st->hover;
    const bool accent  = st && st->accent;

    COLORREF fill, textColor;
    if (accent) {
        fill = pressed ? kAccentDown : (hover ? kAccentHover : kAccent);
        textColor = RGB(255, 255, 255);
    } else {
        fill = pressed ? kBorder : (hover ? kPanelHover : kPanel);
        textColor = kText;
    }

    RECT rc = dis->rcItem;
    HDC dc = dis->hDC;

    // Rounded fill.
    HBRUSH br = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, 1, accent ? fill : kBorder);
    HBRUSH oldBr = (HBRUSH)SelectObject(dc, br);
    HPEN oldPen = (HPEN)SelectObject(dc, pen);
    RoundRect(dc, rc.left, rc.top, rc.right, rc.bottom, 10, 10);
    SelectObject(dc, oldBr);
    SelectObject(dc, oldPen);
    DeleteObject(br);
    DeleteObject(pen);

    // Label.
    wchar_t text[64];
    GetWindowTextW(dis->hwndItem, text, 64);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, textColor);
    SelectObject(dc, g_fontBody);
    DrawTextW(dc, text, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

// ---------------------------------------------------------------------------
// Helpers to draw labels / borders in WM_PAINT
// ---------------------------------------------------------------------------
static void DrawLabel(HDC dc, int x, int y, const wchar_t* text, HFONT font,
                      COLORREF color) {
    SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, color);
    TextOutW(dc, x, y, text, (int)wcslen(text));
}

static void FrameField(HDC dc, RECT rc) {
    HPEN pen = CreatePen(PS_SOLID, 1, kBorder);
    HBRUSH oldBr = (HBRUSH)SelectObject(dc, GetStockObject(NULL_BRUSH));
    HPEN oldPen = (HPEN)SelectObject(dc, pen);
    RoundRect(dc, rc.left, rc.top, rc.right, rc.bottom, 8, 8);
    SelectObject(dc, oldBr);
    SelectObject(dc, oldPen);
    DeleteObject(pen);
}

// ---------------------------------------------------------------------------
// Browse for a DLL
// ---------------------------------------------------------------------------
static void BrowseForDll(HWND hWnd) {
    wchar_t file[MAX_PATH] = {0};
    OPENFILENAMEW ofn = {};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = hWnd;
    ofn.lpstrFilter = L"DLL files (*.dll)\0*.dll\0All files (*.*)\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = L"Select a DLL to inject";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_EXPLORER;
    if (GetOpenFileNameW(&ofn)) {
        SetWindowTextW(g_hDllEdit, file);
    }
}

static void DoInject(HWND hWnd) {
    wchar_t dll[MAX_PATH] = {0};
    GetWindowTextW(g_hDllEdit, dll, MAX_PATH);
    if (dll[0] == L'\0') {
        SetStatus(L"Choose a DLL first (use Browse).", true);
        return;
    }
    DWORD pid = GetSelectedPid();
    if (pid == 0) {
        SetStatus(L"Select a process from the list.", true);
        return;
    }
    std::wstring err = InjectDll(pid, dll);
    if (err.empty()) {
        SetStatus(L"Injected into PID " + std::to_wstring(pid) + L".", false);
    } else {
        SetStatus(err, true);
    }
}

// ---------------------------------------------------------------------------
// Window procedure
// ---------------------------------------------------------------------------
static LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CREATE: {
            HINSTANCE inst = ((LPCREATESTRUCT)lp)->hInstance;

            g_hDllEdit = CreateWindowExW(
                0, L"EDIT", L"",
                WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                26, 116, 496, 30, hWnd, (HMENU)ID_DLL_EDIT, inst, nullptr);
            SendMessageW(g_hDllEdit, EM_SETCUEBANNER, TRUE,
                         (LPARAM)L"Path to .dll  (or click Browse)");

            HWND browse = CreateWindowExW(
                0, L"BUTTON", L"Browse",
                WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                536, 114, 140, 34, hWnd, (HMENU)ID_BROWSE, inst, nullptr);
            MakeButton(browse, false);

            g_hSearch = CreateWindowExW(
                0, L"EDIT", L"",
                WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                26, 196, 496, 30, hWnd, (HMENU)ID_SEARCH, inst, nullptr);
            SendMessageW(g_hSearch, EM_SETCUEBANNER, TRUE,
                         (LPARAM)L"Filter processes by name or PID");

            HWND refresh = CreateWindowExW(
                0, L"BUTTON", L"Refresh",
                WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                536, 194, 140, 34, hWnd, (HMENU)ID_REFRESH, inst, nullptr);
            MakeButton(refresh, false);

            g_hList = CreateWindowExW(
                0, WC_LISTVIEWW, L"",
                WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL |
                    LVS_SHOWSELALWAYS,
                26, 240, 650, 250, hWnd, (HMENU)ID_LIST, inst, nullptr);
            ListView_SetExtendedListViewStyle(
                g_hList, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
            ListView_SetBkColor(g_hList, kPanel);
            ListView_SetTextBkColor(g_hList, kPanel);
            ListView_SetTextColor(g_hList, kText);
            SetWindowTheme(g_hList, L"DarkMode_Explorer", nullptr);
            SendMessageW(g_hList, WM_SETFONT, (WPARAM)g_fontBody, TRUE);

            LVCOLUMNW col = {};
            col.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
            col.pszText = const_cast<wchar_t*>(L"Process");
            col.cx = 470;
            col.iSubItem = 0;
            ListView_InsertColumn(g_hList, 0, &col);
            col.pszText = const_cast<wchar_t*>(L"PID");
            col.cx = 160;
            col.iSubItem = 1;
            ListView_InsertColumn(g_hList, 1, &col);

            HWND inject = CreateWindowExW(
                0, L"BUTTON", L"Inject DLL",
                WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                26, 502, 650, 42, hWnd, (HMENU)ID_INJECT, inst, nullptr);
            MakeButton(inject, true);

            // Body font on edits.
            SendMessageW(g_hDllEdit, WM_SETFONT, (WPARAM)g_fontBody, TRUE);
            SendMessageW(g_hSearch, WM_SETFONT, (WPARAM)g_fontBody, TRUE);

            RefreshProcesses();
            PopulateList();
            return 0;
        }

        case WM_CTLCOLOREDIT: {
            HDC dc = (HDC)wp;
            SetTextColor(dc, kText);
            SetBkColor(dc, kPanel);
            return (LRESULT)g_brushPanel;
        }
        case WM_CTLCOLORSTATIC: {
            HDC dc = (HDC)wp;
            SetTextColor(dc, kText);
            SetBkColor(dc, kBg);
            return (LRESULT)g_brushBg;
        }

        case WM_DRAWITEM: {
            LPDRAWITEMSTRUCT dis = (LPDRAWITEMSTRUCT)lp;
            if (dis->CtlType == ODT_BUTTON) {
                DrawButton(dis);
                return TRUE;
            }
            break;
        }

        case WM_NOTIFY: {
            LPNMHDR nh = (LPNMHDR)lp;
            if (nh->idFrom == ID_LIST) {
                if (nh->code == NM_CUSTOMDRAW) {
                    LPNMLVCUSTOMDRAW cd = (LPNMLVCUSTOMDRAW)lp;
                    switch (cd->nmcd.dwDrawStage) {
                        case CDDS_PREPAINT:
                            return CDRF_NOTIFYITEMDRAW;
                        case CDDS_ITEMPREPAINT: {
                            bool sel = ListView_GetItemState(
                                           g_hList, (int)cd->nmcd.dwItemSpec,
                                           LVIS_SELECTED) != 0;
                            if (sel) {
                                cd->clrTextBk = kSelBg;
                                cd->clrText = RGB(255, 255, 255);
                            } else {
                                cd->clrTextBk = (cd->nmcd.dwItemSpec & 1)
                                                    ? kRowAlt
                                                    : kPanel;
                                cd->clrText = kText;
                            }
                            return CDRF_DODEFAULT;
                        }
                    }
                    return CDRF_DODEFAULT;
                }
                if (nh->code == NM_DBLCLK) {
                    DoInject(hWnd);
                    return 0;
                }
            }
            break;
        }

        case WM_COMMAND: {
            int id = LOWORD(wp);
            int code = HIWORD(wp);
            if (id == ID_BROWSE)  { BrowseForDll(hWnd); return 0; }
            if (id == ID_REFRESH) { RefreshProcesses(); PopulateList();
                                    SetStatus(L"Process list refreshed.", false);
                                    return 0; }
            if (id == ID_INJECT)  { DoInject(hWnd); return 0; }
            if (id == ID_SEARCH && code == EN_CHANGE) { PopulateList(); return 0; }
            break;
        }

        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC dc = BeginPaint(hWnd, &ps);
            RECT client;
            GetClientRect(hWnd, &client);

            FillRect(dc, &client, g_brushBg);

            DrawLabel(dc, 26, 22, L"DLL Injector", g_fontTitle, kText);
            DrawLabel(dc, 28, 58,
                      L"Select a DLL and a target process to inject into.",
                      g_fontSmall, kMuted);

            DrawLabel(dc, 26, 96, L"DLL", g_fontSmall, kMuted);
            DrawLabel(dc, 26, 176, L"PROCESS", g_fontSmall, kMuted);

            // Field borders.
            FrameField(dc, {26, 116, 522, 146});   // dll edit
            FrameField(dc, {26, 196, 522, 226});   // search edit
            FrameField(dc, {26, 240, 676, 490});   // list

            // Status strip.
            RECT strip = {0, client.bottom - 34, client.right, client.bottom};
            HBRUSH sb = CreateSolidBrush(kPanel);
            FillRect(dc, &strip, sb);
            DeleteObject(sb);
            DrawLabel(dc, 26, client.bottom - 25, g_status.c_str(), g_fontSmall,
                      g_statusErr ? RGB(248, 113, 113) : kMuted);

            EndPaint(hWnd, &ps);
            return 0;
        }

        case WM_ERASEBKGND:
            return 1;  // handled in WM_PAINT

        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hWnd, msg, wp, lp);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int show) {
    SetProcessDPIAware();

    INITCOMMONCONTROLSEX icc = {sizeof(icc), ICC_LISTVIEW_CLASSES |
                                             ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&icc);

    // Fonts.
    auto makeFont = [](int size, int weight) {
        return CreateFontW(-size, 0, 0, 0, weight, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    };
    g_fontTitle = makeFont(26, FW_SEMIBOLD);
    g_fontBody  = makeFont(16, FW_NORMAL);
    g_fontSmall = makeFont(13, FW_NORMAL);

    g_brushBg    = CreateSolidBrush(kBg);
    g_brushPanel = CreateSolidBrush(kPanel);

    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = g_brushBg;
    wc.lpszClassName = L"DllInjectorWindow";
    RegisterClassW(&wc);

    // Fixed-size window (no thick frame / maximize) for a clean layout.
    DWORD style = (WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX) |
                  WS_VISIBLE;

    RECT r = {0, 0, 702, 574};
    AdjustWindowRect(&r, style, FALSE);
    HWND hWnd = CreateWindowExW(
        0, wc.lpszClassName, L"DLL Injector", style,
        CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left, r.bottom - r.top,
        nullptr, nullptr, inst, nullptr);
    if (!hWnd) return 1;

    ShowWindow(hWnd, show);
    UpdateWindow(hWnd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        if (msg.message == WM_KEYDOWN && msg.wParam == VK_RETURN) {
            DoInject(hWnd);
            continue;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    DeleteObject(g_fontTitle);
    DeleteObject(g_fontBody);
    DeleteObject(g_fontSmall);
    DeleteObject(g_brushBg);
    DeleteObject(g_brushPanel);
    return 0;
}
