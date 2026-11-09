// Local Trainer windowed-mode overlay: reads ONLY the selected local snapshot.
// No networking, injection, memory reading, process execution, or persistence.
#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commdlg.h>
#include <algorithm>
#include <cmath>
#include <sstream>
#include <string>
#include <vector>
#include "snapshot.hpp"
static std::wstring g_path;
static HWND g_overlay = nullptr;
static Snapshot g_snapshot;

static bool read_snapshot(Snapshot &snapshot) {
    HANDLE file = CreateFileW(g_path.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    FILETIME updated{}, now{};
    bool valid_time = GetFileTime(file, nullptr, nullptr, &updated) != 0;
    GetSystemTimeAsFileTime(&now);
    ULARGE_INTEGER a{}, b{}; a.LowPart = updated.dwLowDateTime; a.HighPart = updated.dwHighDateTime;
    b.LowPart = now.dwLowDateTime; b.HighPart = now.dwHighDateTime;
    char buffer[16385]{};
    DWORD read = 0;
    bool ok = valid_time && b.QuadPart >= a.QuadPart && b.QuadPart - a.QuadPart < 20000000ULL
        && ReadFile(file, buffer, 16384, &read, nullptr) && read > 0 && read < 16384;
    CloseHandle(file);
    if (!ok) return false;
    return parse_snapshot(std::string(buffer, read), snapshot);
}

static void paint(HWND hwnd) {
    PAINTSTRUCT ps{}; HDC screen = BeginPaint(hwnd, &ps);
    RECT rect{}; GetClientRect(hwnd, &rect);
    int width = rect.right, height = rect.bottom;
    if (width <= 0 || height <= 0) { EndPaint(hwnd, &ps); return; }
    HDC dc = CreateCompatibleDC(screen);
    HBITMAP bmp = CreateCompatibleBitmap(screen, width, height);
    HGDIOBJ old_bmp = SelectObject(dc, bmp);
    FillRect(dc, &rect, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    SetBkMode(dc, TRANSPARENT);
    for (const Player &p : g_snapshot.players) {
        Point2 head{}, foot{};
        Vec3 h{p.origin.x, p.origin.y, p.origin.z + p.top};
        Vec3 f{p.origin.x, p.origin.y, p.origin.z + p.bottom};
        if (!project(g_snapshot.camera, h, width, height, head)
            || !project(g_snapshot.camera, f, width, height, foot)) continue;
        double size = std::abs(foot.y - head.y);
        if (size < 2 || size > height * 3.0 || head.x < -width || head.x > width * 2.0) continue;
        int boxh = static_cast<int>(size);
        int boxw = std::max(5, boxh / 2);
        int center = static_cast<int>((head.x + foot.x) * 0.5);
        int top = static_cast<int>(std::min(head.y, foot.y));
        RECT box{center - boxw / 2, top, center + boxw / 2, top + boxh};
        COLORREF color = p.team == 1 ? RGB(0, 255, 0) : RGB(255, 40, 40);
        HBRUSH brush = CreateSolidBrush(color);
        FrameRect(dc, &box, brush); DeleteObject(brush);
        SetTextColor(dc, color);
        const wchar_t *label = p.team == 1 ? L"FRIEND" : L"ENEMY";
        TextOutW(dc, box.left, std::max(0L, box.top - 16), label, lstrlenW(label));
    }
    BitBlt(screen, 0, 0, width, height, dc, 0, 0, SRCCOPY);
    SelectObject(dc, old_bmp); DeleteObject(bmp); DeleteDC(dc);
    EndPaint(hwnd, &ps);
}

static void tick(HWND hwnd) {
    HWND game = FindWindowW(L"Valve001", nullptr);
    Snapshot current;
    if (!game || IsIconic(game) || GetForegroundWindow() != game || !read_snapshot(current)) {
        ShowWindow(hwnd, SW_HIDE); return;
    }
    RECT r{}; POINT point{0, 0};
    if (!GetClientRect(game, &r) || !ClientToScreen(game, &point) || r.right <= 0 || r.bottom <= 0) {
        ShowWindow(hwnd, SW_HIDE); return;
    }
    g_snapshot = std::move(current);
    SetWindowPos(hwnd, HWND_TOPMOST, point.x, point.y, r.right, r.bottom,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(hwnd, nullptr, FALSE);
}

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_TIMER: tick(hwnd); return 0;
        case WM_PAINT: paint(hwnd); return 0;
        case WM_NCHITTEST: return HTTRANSPARENT;
        case WM_HOTKEY: if (wp == 1) { DestroyWindow(hwnd); return 0; } break;
        case WM_DESTROY: UnregisterHotKey(hwnd, 1); KillTimer(hwnd, 1); PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    SetProcessDPIAware();
    wchar_t path[MAX_PATH] = L"lt_local_snapshot.txt";
    OPENFILENAMEW dialog{};
    dialog.lStructSize = sizeof(dialog); dialog.lpstrFile = path; dialog.nMaxFile = MAX_PATH;
    dialog.lpstrTitle = L"Select lt_local_snapshot.txt in cstrike\\addons\\amxmodx\\data";
    dialog.lpstrFilter = L"Trainer snapshot (*.txt)\0*.txt\0\0";
    dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
    if (!GetOpenFileNameW(&dialog)) return 0;
    g_path = path;
    WNDCLASSW wc{}; wc.lpfnWndProc = window_proc; wc.hInstance = instance;
    wc.lpszClassName = L"LocalTrainerOverlay"; wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    if (!RegisterClassW(&wc)) return 1;
    g_overlay = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        wc.lpszClassName, L"Local Trainer Overlay", WS_POPUP,
        0, 0, 1, 1, nullptr, nullptr, instance, nullptr);
    if (!g_overlay || !SetLayeredWindowAttributes(g_overlay, RGB(0, 0, 0), 0, LWA_COLORKEY)) return 1;
    if (!RegisterHotKey(g_overlay, 1, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_F12))
        MessageBoxW(nullptr, L"Exit hotkey unavailable. Close Local Trainer Overlay using Task Manager.", L"Local Trainer", MB_OK | MB_ICONWARNING);
    SetTimer(g_overlay, 1, 50, nullptr);
    MSG msg{}; while (GetMessageW(&msg, nullptr, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    return 0;
}
