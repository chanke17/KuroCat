#define NOMINMAX
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <shellapi.h>
#include <commdlg.h>
#include <objidl.h>
#include <gdiplus.h>
#include <string>
#include <cmath>
#include <algorithm>
#include "KeyMap.hpp"
#include "InputEngine.hpp"
#include "CatPhysics.hpp"
#include "CatRenderer.hpp"

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "comdlg32.lib")

namespace {

constexpr UINT WM_TRAYICON = WM_APP + 1;
constexpr UINT WM_WAKE_EXISTING = WM_APP + 2;
constexpr UINT_PTR TIMER_RENDER = 1;
constexpr int HOTKEY_CLICKTHROUGH_ID = 101;
UINT g_msgTaskbarCreated = 0;

enum MenuCmd : UINT {
    CMD_TOGGLE_VISIBLE = 1001,
    CMD_TOGGLE_CLICKTHROUGH,
    CMD_TOGGLE_TOPMOST,
    CMD_TOGGLE_AUTOSTART,
    CMD_TOGGLE_BADGES,
    CMD_TOGGLE_FOOT,
    CMD_TOGGLE_PET,
    CMD_BREED_BASE = 1100,       // 1100..1109 (10 Breed Presets)
    CMD_PATTERN_BASE = 1120,     // 1120..1125 (6 Fur Patterns)
    CMD_FUR_SHORT = 1130,
    CMD_FUR_MEDIUM,
    CMD_FUR_LONG,
    CMD_PICK_PRIMARY = 1140,
    CMD_PICK_SECONDARY,
    CMD_PICK_TERTIARY,
    CMD_PICK_EYE,
    CMD_KB_MILK = 1200,
    CMD_KB_HACKER,
    CMD_KB_RETRO,
    CMD_EYE_LIME = 1210,
    CMD_EYE_BLUE,
    CMD_EYE_AMBER,
    CMD_EYE_CYAN,
    CMD_TIE_TOGGLE = 1220,
    CMD_TIE_STYLE_NECK,
    CMD_TIE_STYLE_BOW,
    CMD_TIE_COLOR_BASE = 1230,   // 1230..1235
    CMD_TIE_PAT_BASE = 1240,     // 1240..1243
    CMD_TIRED_AUTO = 1250,
    CMD_TIRED_ON,
    CMD_TIRED_OFF,
    CMD_LANG_AUTO = 1260,
    CMD_LANG_EN,
    CMD_LANG_ZH,
    CMD_SCALE_65 = 1300,
    CMD_SCALE_85,
    CMD_SCALE_100,
    CMD_SCALE_125,
    CMD_SCALE_150,
    CMD_DEMO_BURST,
    CMD_RESET_POS,
    CMD_QUIT
};

bool pickWinColor(HWND owner, RGBColor& inOut) {
    static COLORREF cust[16] = {};
    CHOOSECOLORW cc = {};
    cc.lStructSize = sizeof(cc);
    cc.hwndOwner = owner;
    cc.lpCustColors = cust;
    cc.rgbResult = RGB(inOut.r, inOut.g, inOut.b);
    cc.Flags = CC_FULLOPEN | CC_RGBINIT;
    if (ChooseColorW(&cc)) {
        inOut.r = GetRValue(cc.rgbResult);
        inOut.g = GetGValue(cc.rgbResult);
        inOut.b = GetBValue(cc.rgbResult);
        return true;
    }
    return false;
}

struct AppState {
    HWND hwnd = nullptr;
    HWND menuOwnerHwnd = nullptr; // Non-NOACTIVATE helper window so TrackPopupMenu from tray NEVER fails!
    HICON trayIcon = nullptr;
    NOTIFYICONDATAW nid = {};

    CatSettings settings;
    InputEngine input;
    CatPhysics physics;

    bool isVisible = true;
    bool isDragging = false;
    POINT dragStartCursor = {};
    POINT dragStartWinOrigin = {};
    bool hasLastHover = false;
    Pt lastHoverCanvas = {};

    // Reusable 32-bit premultiplied DIB backing buffer
    HDC memDC = nullptr;
    HBITMAP dibBmp = nullptr;
    HBITMAP oldBmp = nullptr;
    void* dibBits = nullptr;
    int bufW = 0;
    int bufH = 0;

    double lastTickTime = 0.0;
    bool demoActive = false;
    double demoStartTime = 0.0;
    int demoStepIdx = 0;

    void destroyBuffer() {
        if (memDC && oldBmp) SelectObject(memDC, oldBmp);
        if (dibBmp) DeleteObject(dibBmp);
        if (memDC) DeleteDC(memDC);
        memDC = nullptr; dibBmp = nullptr; oldBmp = nullptr; dibBits = nullptr;
        bufW = 0; bufH = 0;
    }

    void ensureBuffer(int w, int h) {
        if (w == bufW && h == bufH && memDC && dibBits) return;
        destroyBuffer();

        HDC screenDC = GetDC(nullptr);
        memDC = CreateCompatibleDC(screenDC);
        ReleaseDC(nullptr, screenDC);

        BITMAPINFO bmi = {};
        bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth = w;
        bmi.bmiHeader.biHeight = -h; // top-down 32bpp DIB
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        dibBmp = CreateDIBSection(memDC, &bmi, DIB_RGB_COLORS, &dibBits, nullptr, 0);
        if (dibBmp) {
            oldBmp = (HBITMAP)SelectObject(memDC, dibBmp);
            bufW = w;
            bufH = h;
        }
    }
};

AppState* g_app = nullptr;

HICON createCatTrayIcon();

// MARK: - Windows Auto-Start (HKCU\Software\Microsoft\Windows\CurrentVersion\Run)

std::wstring getCurrentExeQuotedPath() {
    wchar_t buf[MAX_PATH * 2] = {};
    DWORD len = GetModuleFileNameW(nullptr, buf, (DWORD)(sizeof(buf) / sizeof(buf[0]) - 1));
    if (len == 0) return L"";
    return L"\"" + std::wstring(buf, len) + L"\"";
}

bool isAutoStartEnabled() {
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
        return false;
    }
    DWORD type = 0, size = 0;
    bool exists = (RegQueryValueExW(hKey, L"KuroCat", nullptr, &type, nullptr, &size) == ERROR_SUCCESS && size > 0);
    RegCloseKey(hKey);
    return exists;
}

bool setAutoStartEnabled(bool enable) {
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, nullptr, 0, KEY_WRITE, nullptr, &hKey, nullptr) != ERROR_SUCCESS) {
        return false;
    }
    bool ok = false;
    if (enable) {
        std::wstring cmd = getCurrentExeQuotedPath();
        if (!cmd.empty()) {
            ok = (RegSetValueExW(hKey, L"KuroCat", 0, REG_SZ, (const BYTE*)cmd.c_str(), (DWORD)((cmd.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS);
        }
    } else {
        LSTATUS st = RegDeleteValueW(hKey, L"KuroCat");
        ok = (st == ERROR_SUCCESS || st == ERROR_FILE_NOT_FOUND);
    }
    RegCloseKey(hKey);
    return ok;
}

void showTrayBalloon(AppState& app, const wchar_t* title, const wchar_t* body) {
    NOTIFYICONDATAW b = app.nid;
    b.uFlags = NIF_INFO;
    b.dwInfoFlags = NIIF_INFO | NIIF_NOSOUND;
    wcsncpy_s(b.szInfoTitle, title, _TRUNCATE);
    wcsncpy_s(b.szInfo, body, _TRUNCATE);
    Shell_NotifyIconW(NIM_MODIFY, &b);
}

void registerTrayIcon(AppState& app) {
    if (!app.trayIcon) app.trayIcon = createCatTrayIcon();
    app.nid = {};
    app.nid.cbSize = sizeof(app.nid);
    app.nid.hWnd = app.menuOwnerHwnd ? app.menuOwnerHwnd : app.hwnd;
    app.nid.uID = 1;
    app.nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    app.nid.uCallbackMessage = WM_TRAYICON;
    app.nid.hIcon = app.trayIcon;
    wcscpy_s(app.nid.szTip, L"KuroCat \u9ED1\u732B\u952E\u76D8\u684C\u5BA0 (\u53F3\u952E/\u5DE6\u952E\u6253\u5F00\u83DC\u5355)");
    Shell_NotifyIconW(NIM_ADD, &app.nid);
}

HICON createCatTrayIcon() {
    using namespace Gdiplus;
    constexpr int sz = 32;
    Bitmap bmp(sz, sz, PixelFormat32bppPARGB);
    Graphics g(&bmp);
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.Clear(Color(0, 0, 0, 0));

    SolidBrush black(Color(255, 22, 22, 26));
    PointF lEar[3] = { {4, 15}, {6, 3}, {14, 11} };
    PointF rEar[3] = { {28, 15}, {26, 3}, {18, 11} };
    g.FillPolygon(&black, lEar, 3);
    g.FillPolygon(&black, rEar, 3);
    g.FillEllipse(&black, 4.0f, 8.0f, 24.0f, 21.0f);

    SolidBrush lime(Color(255, 201, 242, 64));
    g.FillEllipse(&lime, 8.5f, 14.5f, 6.0f, 5.2f);
    g.FillEllipse(&lime, 17.5f, 14.5f, 6.0f, 5.2f);
    g.FillEllipse(&black, 10.7f, 15.2f, 1.8f, 3.8f);
    g.FillEllipse(&black, 19.7f, 15.2f, 1.8f, 3.8f);

    HICON hIcon = nullptr;
    bmp.GetHICON(&hIcon);
    return hIcon;
}

void computeDefaultOrigin(int w, int h, int& outX, int& outY) {
    RECT work = {};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    outX = work.right - w - 24;
    outY = work.bottom - h - 12;
}

void applyWindowScaleAndPosition(AppState& app, bool anchorBottomCenter) {
    int newW = (int)std::round(CatPhysics::CanvasWidth * app.settings.scale);
    int newH = (int)std::round(CatPhysics::CanvasHeight * app.settings.scale);

    int x = app.settings.posX;
    int y = app.settings.posY;
    if (anchorBottomCenter && app.hwnd) {
        RECT r = {};
        GetWindowRect(app.hwnd, &r);
        int oldMidX = (r.left + r.right) / 2;
        int oldBotY = r.bottom;
        x = oldMidX - newW / 2;
        y = oldBotY - newH;
    } else if (x == -99999 || y == -99999) {
        computeDefaultOrigin(newW, newH, x, y);
    }

    // Clamp onto virtual desktop so saved off-monitor coords never get lost
    int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (x + newW < vx + 40 || x > vx + vw - 40 || y + newH < vy + 40 || y > vy + vh - 40) {
        computeDefaultOrigin(newW, newH, x, y);
    }

    app.settings.posX = x;
    app.settings.posY = y;
    HWND insertAfter = app.settings.alwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST;
    SetWindowPos(app.hwnd, insertAfter, x, y, newW, newH, SWP_NOACTIVATE);
    app.settings.saveToRegistry();
}

void setClickThrough(HWND hwnd, bool transparent) {
    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    bool isTrans = (ex & WS_EX_TRANSPARENT) != 0;
    if (isTrans != transparent) {
        if (transparent) ex |= WS_EX_TRANSPARENT;
        else ex &= ~WS_EX_TRANSPARENT;
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex);
    }
}

void showContextMenu(AppState& app, POINT screenPt) {
    HMENU menu = CreatePopupMenu();
    AppLanguage lang = app.settings.language;
    auto T = [&](const wchar_t* en, const wchar_t* zh) { return trW(lang, en, zh); };

    // Status & live stats header
    std::wstring statusStr = app.input.isRawInputRegistered
        ? T(L"\u25CF Hardware Monitoring Active (Raw Input)", L"\u25CF \u786C\u4EF6\u7EA7\u5168\u72B6\u6001\u76D1\u542C\u4E2D (Raw Input \u6E38\u620F/\u6253\u5B57)")
        : T(L"\u26A0 Raw Input Inactive", L"\u26A0 Raw Input \u672A\u542F\u52A8");
    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, statusStr.c_str());

    std::wstring moodStr;
    if (app.physics.isSleeping()) moodStr = T(L"  \u00B7  Sleeping", L"  \u00B7  \u547C\u547C\u5927\u7761\u4E2D");
    else if (app.physics.effectiveTiredness() > 0.35f) moodStr = T(L"  \u00B7  Tired", L"  \u00B7  \u71AC\u591C\u56F0\u56F0\u4E2D");

    std::wstring stats = isChineseUI(lang)
        ? (L"\u4ECA\u65E5\u51FB\u952E " + std::to_wstring(app.input.totalKeystrokesToday) + L"  \u00B7  KPM " + std::to_wstring(app.input.currentKPM()) + L"  \u00B7  \u6478\u732B " + std::to_wstring(app.physics.totalPetSessions) + L" \u6B21" + moodStr)
        : (L"Today " + std::to_wstring(app.input.totalKeystrokesToday) + L"  \u00B7  KPM " + std::to_wstring(app.input.currentKPM()) + L"  \u00B7  Pets " + std::to_wstring(app.physics.totalPetSessions) + moodStr);
    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, stats.c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

    AppendMenuW(menu, MF_STRING, CMD_TOGGLE_VISIBLE, app.isVisible ? T(L"Hide KuroCat", L"\u9690\u85CF\u5C0F\u732B") : T(L"Show KuroCat", L"\u663E\u793A\u5C0F\u732B"));
    AppendMenuW(menu, MF_STRING | (app.settings.fullClickThrough ? MF_CHECKED : 0), CMD_TOGGLE_CLICKTHROUGH, T(L"Full Click-Through (Ctrl+Alt+Shift+P / Hold Alt)", L"\u5B8C\u5168\u9F20\u6807\u7A7F\u900F (Ctrl+Alt+Shift+P / \u6309\u4F4FAlt\u53EF\u53F3\u952E)"));
    AppendMenuW(menu, MF_STRING | (app.settings.alwaysOnTop ? MF_CHECKED : 0), CMD_TOGGLE_TOPMOST, T(L"Always on Top", L"\u7A97\u53E3\u7F6E\u9876\u663E\u793A"));
    AppendMenuW(menu, MF_STRING | (isAutoStartEnabled() ? MF_CHECKED : 0), CMD_TOGGLE_AUTOSTART, T(L"Launch at Login", L"\u5F00\u673A\u81EA\u52A8\u542F\u52A8"));
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

    AppendMenuW(menu, MF_STRING | (app.settings.showKeyBadges ? MF_CHECKED : 0), CMD_TOGGLE_BADGES, T(L"Floating Keycap Badges ([W] [A] [\u21E7])", L"\u663E\u793A\u6309\u952E\u6C14\u6CE1 ([S] [W] [\u21E7])"));
    AppendMenuW(menu, MF_STRING | (app.settings.footEasterEgg ? MF_CHECKED : 0), CMD_TOGGLE_FOOT, T(L"3-Key Hind-Foot Easter Egg", L"3\u952E\u540C\u65F6\u6309\u300C\u7528\u811A\u6309\u300D\u5F69\u86CB"));
    AppendMenuW(menu, MF_STRING | (app.settings.petInteraction ? MF_CHECKED : 0), CMD_TOGGLE_PET, T(L"Petting Interaction (Head / Back)", L"\u6478\u5934/\u6478\u80CC\u95ED\u773C\u4E92\u52A8"));
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

    // 10 Breed Presets submenu
    HMENU breedMenu = CreatePopupMenu();
    const wchar_t* breedEn[10] = { L"Classic Black Cat", L"Seal-Point Siamese", L"Orange Tabby", L"Silver Tabby", L"Tuxedo", L"Calico", L"Long-Haired Ragdoll", L"British Shorthair Blue", L"White Persian", L"Golden Maine Coon" };
    const wchar_t* breedZh[10] = { L"\u7ECF\u5178\u5C0F\u9ED1\u732B", L"\u6316\u7164\u66B9\u7F57\u732B", L"\u5927\u6A58\u864E\u6591", L"\u7F8E\u77ED\u94F6\u864E\u6591", L"\u5976\u725B\u71D5\u5C3E\u670D", L"\u4E09\u82B1\u62DB\u8D22\u732B", L"\u957F\u6BDB\u5E03\u5076\u732B", L"\u82F1\u77ED\u84DD\u732B", L"\u957F\u6BDB\u767D\u6CE2\u65AF", L"\u91D1\u6E10\u5C42\u7F05\u56E0" };
    for (int i = 0; i < 10; ++i) {
        AppendMenuW(breedMenu, MF_STRING | (app.settings.appearance.presetID == i ? MF_CHECKED : 0), CMD_BREED_BASE + i, T(breedEn[i], breedZh[i]));
    }
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)breedMenu, T(L"Cat Breed Presets", L"\u732B\u54AA\u54C1\u79CD\u9884\u8BBE"));

    // Custom Appearance submenu (Fur Pattern + Fur Length + Native Win32 Color Pickers!)
    HMENU customMenu = CreatePopupMenu();
    HMENU patMenu = CreatePopupMenu();
    const wchar_t* patEn[6] = { L"Solid", L"Colorpoint / Siamese", L"Tuxedo", L"Tabby", L"Calico", L"Spotted" };
    const wchar_t* patZh[6] = { L"\u7EAF\u8272", L"\u91CD\u70B9\u8272 / \u66B9\u7F57", L"\u5976\u725B / \u71D5\u5C3E\u670D", L"\u864E\u6591", L"\u4E09\u82B1", L"\u6591\u70B9" };
    for (int i = 0; i < 6; ++i) {
        AppendMenuW(patMenu, MF_STRING | ((int)app.settings.appearance.pattern == i ? MF_CHECKED : 0), CMD_PATTERN_BASE + i, T(patEn[i], patZh[i]));
    }
    AppendMenuW(customMenu, MF_POPUP, (UINT_PTR)patMenu, T(L"Fur Pattern", L"\u6BDB\u53D1\u82B1\u7EB9"));
    AppendMenuW(customMenu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(customMenu, MF_STRING | (app.settings.appearance.furLength < 0.30f ? MF_CHECKED : 0), CMD_FUR_SHORT, T(L"Short Fur (Sleek)", L"\u77ED\u6BDB (\u987A\u6ED1)"));
    AppendMenuW(customMenu, MF_STRING | (app.settings.appearance.furLength >= 0.30f && app.settings.appearance.furLength < 0.70f ? MF_CHECKED : 0), CMD_FUR_MEDIUM, T(L"Medium Fur (Plush)", L"\u4E2D\u6BDB (\u84EC\u677E)"));
    AppendMenuW(customMenu, MF_STRING | (app.settings.appearance.furLength >= 0.70f ? MF_CHECKED : 0), CMD_FUR_LONG, T(L"Long Fur (Fluffy + Physics)", L"\u957F\u6BDB (\u84EC\u677E\u7269\u7406)"));
    AppendMenuW(customMenu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(customMenu, MF_STRING, CMD_PICK_PRIMARY,   T(L"Pick Primary Coat Color...", L"\u9009\u62E9\u4E3B\u6BDB\u8272..."));
    AppendMenuW(customMenu, MF_STRING, CMD_PICK_SECONDARY, T(L"Pick Markings / Points Color...", L"\u9009\u62E9\u82B1\u7EB9 / \u91CD\u70B9\u8272..."));
    AppendMenuW(customMenu, MF_STRING, CMD_PICK_TERTIARY,  T(L"Pick Accent / 3rd Color...", L"\u9009\u62E9\u70B9\u7F00 / \u7B2C\u4E09\u8272..."));
    AppendMenuW(customMenu, MF_STRING, CMD_PICK_EYE,       T(L"Pick Eye Color...", L"\u9009\u62E9\u77B3\u8272..."));
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)customMenu, T(L"Custom Cat Studio (Fur / Colors)", L"\u81EA\u5B9A\u4E49\u732B\u54AA (\u6BDB\u53D1/\u53D6\u8272\u5668)"));

    // Tie / Bow Tie submenu
    HMENU tieMenu = CreatePopupMenu();
    AppendMenuW(tieMenu, MF_STRING | (app.settings.showTie ? MF_CHECKED : 0), CMD_TIE_TOGGLE, T(L"Wear Tie / Bow Tie", L"\u4F69\u6234\u9886\u5E26 / \u9886\u7ED3"));
    AppendMenuW(tieMenu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(tieMenu, MF_STRING | (app.settings.tieStyle == TieStyle::Necktie ? MF_CHECKED : 0), CMD_TIE_STYLE_NECK, T(L"Style: Necktie", L"\u6B3E\u5F0F: \u7ECF\u5178\u9886\u5E26"));
    AppendMenuW(tieMenu, MF_STRING | (app.settings.tieStyle == TieStyle::BowTie ? MF_CHECKED : 0), CMD_TIE_STYLE_BOW, T(L"Style: Bow Tie", L"\u6B3E\u5F0F: \u5B66\u9662\u9886\u7ED3"));
    AppendMenuW(tieMenu, MF_SEPARATOR, 0, nullptr);
    const wchar_t* tcEn[6] = { L"Cyan", L"Crimson", L"Navy", L"Emerald", L"Amber", L"Lavender" };
    const wchar_t* tcZh[6] = { L"\u9752\u8272", L"\u82CF\u683C\u5170\u7EA2", L"\u5B66\u9662\u85CF\u84DD", L"\u68EE\u7CFB\u58A8\u7EFF", L"\u6696\u9633\u59DC\u9EC4", L"\u9999\u828B\u6D45\u7D2B" };
    for (int i = 0; i < 6; ++i) {
        AppendMenuW(tieMenu, MF_STRING | ((int)app.settings.tieColor == i ? MF_CHECKED : 0), CMD_TIE_COLOR_BASE + i, T(tcEn[i], tcZh[i]));
    }
    AppendMenuW(tieMenu, MF_SEPARATOR, 0, nullptr);
    const wchar_t* tpEn[4] = { L"Scottish Tartan", L"Diagonal Stripe", L"Polka Dot", L"Solid" };
    const wchar_t* tpZh[4] = { L"\u82CF\u683C\u5170\u683C\u7EB9", L"\u5B66\u9662\u659C\u6761\u7EB9", L"\u7ECF\u5178\u6CE2\u70B9", L"\u7B80\u7EA6\u7EAF\u8272" };
    for (int i = 0; i < 4; ++i) {
        AppendMenuW(tieMenu, MF_STRING | ((int)app.settings.tiePattern == i ? MF_CHECKED : 0), CMD_TIE_PAT_BASE + i, T(tpEn[i], tpZh[i]));
    }
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)tieMenu, T(L"Tie / Bow Tie", L"\u9886\u5E26 / \u9886\u7ED3\u914D\u9970"));

    // Keyboard Theme submenu
    HMENU kbMenu = CreatePopupMenu();
    AppendMenuW(kbMenu, MF_STRING | (app.settings.keyboardTheme == KeyboardTheme::ClassicMilk ? MF_CHECKED : 0), CMD_KB_MILK, T(L"Classic Milk & Amber", L"\u7ECF\u5178\u5976\u767D\u6696\u9EC4 (\u539F\u7248)"));
    AppendMenuW(kbMenu, MF_STRING | (app.settings.keyboardTheme == KeyboardTheme::MidnightHacker ? MF_CHECKED : 0), CMD_KB_HACKER, T(L"Midnight Hacker", L"\u6697\u591C\u6781\u5BA2\u9ED1"));
    AppendMenuW(kbMenu, MF_STRING | (app.settings.keyboardTheme == KeyboardTheme::RetroCream ? MF_CHECKED : 0), CMD_KB_RETRO, T(L"Retro Cream", L"\u590D\u53E4\u5976\u6CB9\u7070"));
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)kbMenu, T(L"Keyboard Theme", L"\u952E\u76D8\u914D\u8272"));

    // Tired Eyes submenu
    HMENU tiredMenu = CreatePopupMenu();
    AppendMenuW(tiredMenu, MF_STRING | (app.settings.tiredEyesMode == TiredEyesMode::AutoLateNight ? MF_CHECKED : 0), CMD_TIRED_AUTO, T(L"Auto (0:00-6:00 AM)", L"\u81EA\u52A8 (0:00-6:00 \u71AC\u591C\u773C)"));
    AppendMenuW(tiredMenu, MF_STRING | (app.settings.tiredEyesMode == TiredEyesMode::AlwaysOn ? MF_CHECKED : 0), CMD_TIRED_ON, T(L"Always On", L"\u59CB\u7EC8\u5F00\u542F\u75B2\u60EB\u773C"));
    AppendMenuW(tiredMenu, MF_STRING | (app.settings.tiredEyesMode == TiredEyesMode::Off ? MF_CHECKED : 0), CMD_TIRED_OFF, T(L"Off", L"\u5173\u95ED"));
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)tiredMenu, T(L"Late-Night Tired Eyes", L"\u71AC\u591C\u75B2\u60EB\u773C"));

    // Scale submenu
    HMENU scaleMenu = CreatePopupMenu();
    auto chk = [&](float v) -> UINT { return std::fabs(app.settings.scale - v) < 0.05f ? MF_CHECKED : 0; };
    AppendMenuW(scaleMenu, MF_STRING | chk(0.65f), CMD_SCALE_65,  T(L"Mini (0.65x)", L"\u8FF7\u4F60 (0.65x)"));
    AppendMenuW(scaleMenu, MF_STRING | chk(0.85f), CMD_SCALE_85,  T(L"Small (0.85x)", L"\u504F\u5C0F (0.85x)"));
    AppendMenuW(scaleMenu, MF_STRING | chk(1.00f), CMD_SCALE_100, T(L"Standard (1.0x)", L"\u6807\u51C6 (1.0x)"));
    AppendMenuW(scaleMenu, MF_STRING | chk(1.25f), CMD_SCALE_125, T(L"Large (1.25x)", L"\u504F\u5927 (1.25x)"));
    AppendMenuW(scaleMenu, MF_STRING | chk(1.50f), CMD_SCALE_150, T(L"Extra Large (1.5x)", L"\u8D85\u5927 (1.5x)"));
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)scaleMenu, T(L"Size", L"\u5C3A\u5BF8\u5927\u5C0F"));

    // Language submenu
    HMENU langMenu = CreatePopupMenu();
    AppendMenuW(langMenu, MF_STRING | (lang == AppLanguage::Auto ? MF_CHECKED : 0), CMD_LANG_AUTO, T(L"System Default (Auto)", L"\u8DDF\u968F\u7CFB\u7EDF (\u81EA\u52A8)"));
    AppendMenuW(langMenu, MF_STRING | (lang == AppLanguage::English ? MF_CHECKED : 0), CMD_LANG_EN, L"English");
    AppendMenuW(langMenu, MF_STRING | (lang == AppLanguage::ZhCN ? MF_CHECKED : 0), CMD_LANG_ZH, L"\u7B80\u4F53\u4E2D\u6587");
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)langMenu, L"Language / \u8BED\u8A00");

    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, CMD_DEMO_BURST, T(L"Demo Typing Burst", L"\u6F14\u793A\u6253\u5B57\u52A8\u753B"));
    AppendMenuW(menu, MF_STRING, CMD_RESET_POS, T(L"Reset Position", L"\u91CD\u7F6E\u4F4D\u7F6E\u5230\u53F3\u4E0B\u89D2"));
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, CMD_QUIT, T(L"Quit KuroCat", L"\u9000\u51FA KuroCat"));

    HWND menuOwner = app.menuOwnerHwnd ? app.menuOwnerHwnd : app.hwnd;
    SetForegroundWindow(menuOwner);
    UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, screenPt.x, screenPt.y, 0, menuOwner, nullptr);
    PostMessageW(menuOwner, WM_NULL, 0, 0);
    DestroyMenu(menu);

    if (cmd >= CMD_BREED_BASE && cmd < CMD_BREED_BASE + 10) {
        app.settings.appearance = makeBreedPreset((CatBreedPreset)(cmd - CMD_BREED_BASE));
        app.settings.saveToRegistry();
        return;
    }
    if (cmd >= CMD_PATTERN_BASE && cmd < CMD_PATTERN_BASE + 6) {
        app.settings.appearance.pattern = (FurPattern)(cmd - CMD_PATTERN_BASE);
        app.settings.appearance.presetID = -1;
        app.settings.saveToRegistry();
        return;
    }
    if (cmd >= CMD_TIE_COLOR_BASE && cmd < CMD_TIE_COLOR_BASE + 6) {
        app.settings.tieColor = (TieColorTheme)(cmd - CMD_TIE_COLOR_BASE);
        app.settings.showTie = true;
        app.settings.saveToRegistry();
        return;
    }
    if (cmd >= CMD_TIE_PAT_BASE && cmd < CMD_TIE_PAT_BASE + 4) {
        app.settings.tiePattern = (TiePattern)(cmd - CMD_TIE_PAT_BASE);
        app.settings.showTie = true;
        app.settings.saveToRegistry();
        return;
    }

    switch (cmd) {
        case CMD_TOGGLE_VISIBLE:
            app.isVisible = !app.isVisible;
            ShowWindow(app.hwnd, app.isVisible ? SW_SHOWNOACTIVATE : SW_HIDE);
            break;
        case CMD_TOGGLE_CLICKTHROUGH:
            app.settings.fullClickThrough = !app.settings.fullClickThrough;
            app.settings.saveToRegistry();
            if (app.settings.fullClickThrough) {
                showTrayBalloon(app,
                    T(L"KuroCat Full Click-Through Enabled", L"KuroCat \u5DF2\u5F00\u542F\u5B8C\u5168\u9F20\u6807\u7A7F\u900F"),
                    T(L"To unlock: Press Ctrl+Alt+Shift+P, hold Alt + right-click cat, or click the tray icon.", L"\u53D6\u6D88\u65B9\u5F0F\uFF1A\u6309 Ctrl+Alt+Shift+P\uFF0C\u6216\u6309\u4F4F Alt \u952E\u53F3\u952E\u5C0F\u732B\uFF0C\u6216\u70B9\u53F3\u4E0B\u89D2\u6258\u76D8\u5C0F\u732B\u56FE\u6807\uFF0C\u6216\u518D\u6B21\u53CC\u51FB KuroCat.exe"));
            }
            break;
        case CMD_TOGGLE_TOPMOST:
            app.settings.alwaysOnTop = !app.settings.alwaysOnTop;
            applyWindowScaleAndPosition(app, false);
            break;
        case CMD_TOGGLE_AUTOSTART:
            setAutoStartEnabled(!isAutoStartEnabled());
            break;
        case CMD_TOGGLE_BADGES:
            app.settings.showKeyBadges = !app.settings.showKeyBadges;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_FOOT:
            app.settings.footEasterEgg = !app.settings.footEasterEgg;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_PET:
            app.settings.petInteraction = !app.settings.petInteraction;
            app.settings.saveToRegistry();
            break;
        case CMD_FUR_SHORT:
            app.settings.appearance.furLength = 0.0f; app.settings.appearance.presetID = -1; app.settings.saveToRegistry(); break;
        case CMD_FUR_MEDIUM:
            app.settings.appearance.furLength = 0.45f; app.settings.appearance.presetID = -1; app.settings.saveToRegistry(); break;
        case CMD_FUR_LONG:
            app.settings.appearance.furLength = 1.0f; app.settings.appearance.presetID = -1; app.settings.saveToRegistry(); break;
        case CMD_PICK_PRIMARY:
            if (pickWinColor(menuOwner, app.settings.appearance.primaryColor)) { app.settings.appearance.presetID = -1; app.settings.saveToRegistry(); }
            break;
        case CMD_PICK_SECONDARY:
            if (pickWinColor(menuOwner, app.settings.appearance.secondaryColor)) { app.settings.appearance.presetID = -1; app.settings.saveToRegistry(); }
            break;
        case CMD_PICK_TERTIARY:
            if (pickWinColor(menuOwner, app.settings.appearance.tertiaryColor)) { app.settings.appearance.presetID = -1; app.settings.saveToRegistry(); }
            break;
        case CMD_PICK_EYE:
            if (pickWinColor(menuOwner, app.settings.appearance.eyeColor)) { app.settings.appearance.presetID = -1; app.settings.saveToRegistry(); }
            break;
        case CMD_TIE_TOGGLE:     app.settings.showTie = !app.settings.showTie; app.settings.saveToRegistry(); break;
        case CMD_TIE_STYLE_NECK: app.settings.tieStyle = TieStyle::Necktie; app.settings.showTie = true; app.settings.saveToRegistry(); break;
        case CMD_TIE_STYLE_BOW:  app.settings.tieStyle = TieStyle::BowTie; app.settings.showTie = true; app.settings.saveToRegistry(); break;
        case CMD_TIRED_AUTO:     app.settings.tiredEyesMode = TiredEyesMode::AutoLateNight; app.settings.saveToRegistry(); break;
        case CMD_TIRED_ON:       app.settings.tiredEyesMode = TiredEyesMode::AlwaysOn; app.settings.saveToRegistry(); break;
        case CMD_TIRED_OFF:      app.settings.tiredEyesMode = TiredEyesMode::Off; app.settings.saveToRegistry(); break;
        case CMD_LANG_AUTO:      app.settings.language = AppLanguage::Auto; app.settings.saveToRegistry(); break;
        case CMD_LANG_EN:        app.settings.language = AppLanguage::English; app.settings.saveToRegistry(); break;
        case CMD_LANG_ZH:        app.settings.language = AppLanguage::ZhCN; app.settings.saveToRegistry(); break;
        case CMD_KB_MILK:   app.settings.keyboardTheme = KeyboardTheme::ClassicMilk; app.settings.saveToRegistry(); break;
        case CMD_KB_HACKER: app.settings.keyboardTheme = KeyboardTheme::MidnightHacker; app.settings.saveToRegistry(); break;
        case CMD_KB_RETRO:  app.settings.keyboardTheme = KeyboardTheme::RetroCream; app.settings.saveToRegistry(); break;
        case CMD_SCALE_65:  app.settings.scale = 0.65f; applyWindowScaleAndPosition(app, true); break;
        case CMD_SCALE_85:  app.settings.scale = 0.85f; applyWindowScaleAndPosition(app, true); break;
        case CMD_SCALE_100: app.settings.scale = 1.00f; applyWindowScaleAndPosition(app, true); break;
        case CMD_SCALE_125: app.settings.scale = 1.25f; applyWindowScaleAndPosition(app, true); break;
        case CMD_SCALE_150: app.settings.scale = 1.50f; applyWindowScaleAndPosition(app, true); break;
        case CMD_DEMO_BURST:
            app.demoActive = true;
            app.demoStartTime = nowSeconds();
            app.demoStepIdx = 0;
            break;
        case CMD_RESET_POS:
            app.settings.posX = -99999;
            app.settings.posY = -99999;
            applyWindowScaleAndPosition(app, false);
            break;
        case CMD_QUIT:
            PostQuitMessage(0);
            break;
        default:
            break;
    }
}

void tickAndRender(AppState& app) {
    if (!app.isVisible || !app.hwnd) return;

    double now = nowSeconds();
    float dt = (float)(now - app.lastTickTime);
    app.lastTickTime = now;
    if (dt <= 0.0f || dt > 0.2f) dt = 1.0f / 60.0f;

    // Optional menu demo typing burst
    if (app.demoActive) {
        static const PhysicalKey demoKeys[] = {
            PhysicalKey::W, PhysicalKey::A, PhysicalKey::S, PhysicalKey::D,
            PhysicalKey::F, PhysicalKey::J, PhysicalKey::O, PhysicalKey::E,
            PhysicalKey::Space, PhysicalKey::LeftShift
        };
        int targetIdx = (int)((now - app.demoStartTime) / 0.13);
        while (app.demoStepIdx <= targetIdx && app.demoStepIdx < 10) {
            app.physics.triggerKeyDown(demoKeys[app.demoStepIdx], app.settings);
            app.demoStepIdx++;
        }
        if (app.demoStepIdx >= 10) app.demoActive = false;
    }

    RECT wr = {};
    GetWindowRect(app.hwnd, &wr);
    int w = std::max(1, (int)(wr.right - wr.left));
    int h = std::max(1, (int)(wr.bottom - wr.top));

    app.physics.step(dt, wr, app.input, app.settings);

    // Smart Click-Through + Petting Detection
    if (!app.isDragging) {
        POINT cur = {};
        GetCursorPos(&cur);
        if (PtInRect(&wr, cur)) {
            Pt cp = {
                (float)(cur.x - wr.left) / (float)w * CatPhysics::CanvasWidth,
                (float)(cur.y - wr.top)  / (float)h * CatPhysics::CanvasHeight
            };
            CatHitZone zone = CatRenderer::hitTest(cp, app.physics);
            if (zone == CatHitZone::Head || zone == CatHitZone::Body) {
                if (app.hasLastHover) {
                    float d = std::hypot(cp.x - app.lastHoverCanvas.x, cp.y - app.lastHoverCanvas.y);
                    if (d > 1.2f && d < 80.0f) {
                        app.physics.registerPetStroke(cp, d, zone == CatHitZone::Head, app.settings);
                    }
                }
                app.lastHoverCanvas = cp;
                app.hasLastHover = true;
            } else {
                app.hasLastHover = false;
            }
            // Holding Alt temporarily unlocks click-through so user can ALWAYS right-click or drag the cat!
            bool altHeld = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
            bool clickThrough = (app.settings.fullClickThrough && !altHeld) || (zone == CatHitZone::None);
            setClickThrough(app.hwnd, clickThrough);
        } else {
            app.hasLastHover = false;
            setClickThrough(app.hwnd, true);
        }
    }

    // Render 32-bit Premultiplied ARGB frame directly into DIB and present via UpdateLayeredWindow
    app.ensureBuffer(w, h);
    if (!app.memDC || !app.dibBits) return;

    Gdiplus::Bitmap bmp(w, h, w * 4, PixelFormat32bppPARGB, static_cast<BYTE*>(app.dibBits));
    Gdiplus::Graphics g(&bmp);
    g.Clear(Gdiplus::Color(0, 0, 0, 0));
    g.ScaleTransform((float)w / CatPhysics::CanvasWidth, (float)h / CatPhysics::CanvasHeight);
    CatRenderer::draw(g, app.physics, app.settings);

    POINT ptDst = { wr.left, wr.top };
    SIZE szWnd = { w, h };
    POINT ptSrc = { 0, 0 };
    BLENDFUNCTION blend = {};
    blend.BlendOp = AC_SRC_OVER;
    blend.SourceConstantAlpha = 255;
    blend.AlphaFormat = AC_SRC_ALPHA;

    HDC screenDC = GetDC(nullptr);
    UpdateLayeredWindow(app.hwnd, screenDC, &ptDst, &szWnd, app.memDC, &ptSrc, 0, &blend, ULW_ALPHA);
    ReleaseDC(nullptr, screenDC);
}

LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    AppState* app = g_app;
    switch (msg) {
        case WM_INPUT:
            if (app) app->input.handleRawInput(lParam);
            return 0;

        case WM_TIMER:
            if (wParam == TIMER_RENDER && app) tickAndRender(*app);
            return 0;

        case WM_SETCURSOR:
            if (LOWORD(lParam) == HTCLIENT) {
                SetCursor(LoadCursorW(nullptr, IDC_HAND));
                return TRUE;
            }
            break;

        case WM_LBUTTONDOWN: {
            bool altHeld = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
            if (app && (!app->settings.fullClickThrough || altHeld)) {
                app->isDragging = true;
                GetCursorPos(&app->dragStartCursor);
                RECT wr = {};
                GetWindowRect(hwnd, &wr);
                app->dragStartWinOrigin = { wr.left, wr.top };
                SetCapture(hwnd);
            }
            return 0;
        }

        case WM_MOUSEMOVE:
            if (app && app->isDragging) {
                POINT cur = {};
                GetCursorPos(&cur);
                int nx = app->dragStartWinOrigin.x + (cur.x - app->dragStartCursor.x);
                int ny = app->dragStartWinOrigin.y + (cur.y - app->dragStartCursor.y);
                SetWindowPos(hwnd, nullptr, nx, ny, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
            return 0;

        case WM_LBUTTONUP:
            if (app && app->isDragging) {
                app->isDragging = false;
                ReleaseCapture();
                RECT wr = {};
                GetWindowRect(hwnd, &wr);
                app->settings.posX = wr.left;
                app->settings.posY = wr.top;
                app->settings.saveToRegistry();
            }
            return 0;

        case WM_RBUTTONUP:
            if (app) {
                POINT pt = {};
                GetCursorPos(&pt);
                showContextMenu(*app, pt);
            }
            return 0;

        case WM_TRAYICON:
            if (app && (lParam == WM_RBUTTONUP || lParam == WM_LBUTTONUP || lParam == WM_CONTEXTMENU)) {
                POINT pt = {};
                GetCursorPos(&pt);
                showContextMenu(*app, pt);
            }
            return 0;

        case WM_HOTKEY:
            if (app && wParam == HOTKEY_CLICKTHROUGH_ID) {
                app->settings.fullClickThrough = !app->settings.fullClickThrough;
                app->settings.saveToRegistry();
                if (app->settings.fullClickThrough) {
                    showTrayBalloon(*app,
                        L"KuroCat \u5DF2\u5F00\u542F\u5B8C\u5168\u9F20\u6807\u7A7F\u900F",
                        L"\u518D\u6B21\u6309 Ctrl+Alt+Shift+P \u6216\u6309\u4F4F Alt \u53F3\u952E\u5C0F\u732B\u5373\u53EF\u53D6\u6D88");
                } else {
                    showTrayBalloon(*app,
                        L"KuroCat \u5DF2\u53D6\u6D88\u5B8C\u5168\u9F20\u6807\u7A7F\u900F",
                        L"\u73B0\u5728\u53EF\u4EE5\u6B63\u5E38\u62D6\u52A8\u3001\u6478\u5934\u548C\u53F3\u952E\u6253\u5F00\u83DC\u5355\u4E86");
                }
            }
            return 0;

        case WM_WAKE_EXISTING:
            if (app) {
                // Re-launching KuroCat.exe unlocks click-through, restores visibility & opens settings menu!
                if (app->settings.fullClickThrough) {
                    app->settings.fullClickThrough = false;
                    app->settings.saveToRegistry();
                }
                if (!app->isVisible) {
                    app->isVisible = true;
                    ShowWindow(app->hwnd, SW_SHOWNOACTIVATE);
                }
                POINT pt = {};
                GetCursorPos(&pt);
                showContextMenu(*app, pt);
            }
            return 0;

        case WM_DESTROY:
            if (hwnd == (app ? app->hwnd : nullptr)) {
                KillTimer(hwnd, TIMER_RENDER);
                if (app) {
                    if (app->menuOwnerHwnd) {
                        UnregisterHotKey(app->menuOwnerHwnd, HOTKEY_CLICKTHROUGH_ID);
                        DestroyWindow(app->menuOwnerHwnd);
                        app->menuOwnerHwnd = nullptr;
                    }
                    Shell_NotifyIconW(NIM_DELETE, &app->nid);
                    if (app->trayIcon) DestroyIcon(app->trayIcon);
                    app->destroyBuffer();
                }
                PostQuitMessage(0);
            }
            return 0;
    }
    if (g_msgTaskbarCreated != 0 && msg == g_msgTaskbarCreated && app && hwnd == app->menuOwnerHwnd) {
        registerTrayIcon(*app);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

} // namespace

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, PWSTR, int) {
    // Enable crisp Per-Monitor V2 DPI awareness on Windows 10/11
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    // Single-instance guard: re-launching KuroCat.exe wakes the existing cat,
    // cancels full click-through, and pops up the menu so users NEVER get stuck!
    HANDLE hMutex = CreateMutexW(nullptr, TRUE, L"Local\\KuroCatDesktopPetSingleInstance");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        if (HWND existing = FindWindowW(L"KuroCatTrayOwnerClass", nullptr)) {
            PostMessageW(existing, WM_WAKE_EXISTING, 0, 0);
        }
        if (hMutex) CloseHandle(hMutex);
        return 0;
    }

    g_msgTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");

    Gdiplus::GdiplusStartupInput gdipInput;
    ULONG_PTR gdipToken = 0;
    Gdiplus::GdiplusStartup(&gdipToken, &gdipInput, nullptr);

    AppState app;
    g_app = &app;
    app.settings.loadFromRegistry();

    // Refresh auto-start exe path if user enabled auto-start and moved KuroCat.exe
    if (isAutoStartEnabled()) {
        setAutoStartEnabled(true);
    }

    app.input.onKeyDown = [&](PhysicalKey k) { app.physics.triggerKeyDown(k, app.settings); };
    app.input.onMouseClick = [&](int btn, bool down) { app.physics.triggerMouseClick(btn, down); };

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = wndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = L"KuroCatOverlayWindowClass";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassExW(&wc);

    // Dedicated hidden tray/menu owner window (NO WS_EX_NOACTIVATE / WS_EX_TRANSPARENT)
    WNDCLASSEXW trayWc = {};
    trayWc.cbSize = sizeof(trayWc);
    trayWc.lpfnWndProc = wndProc;
    trayWc.hInstance = hInst;
    trayWc.lpszClassName = L"KuroCatTrayOwnerClass";
    RegisterClassExW(&trayWc);

    app.menuOwnerHwnd = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        trayWc.lpszClassName,
        L"KuroCatTray",
        WS_POPUP,
        0, 0, 0, 0,
        nullptr, nullptr, hInst, nullptr
    );

    int initW = (int)std::round(CatPhysics::CanvasWidth * app.settings.scale);
    int initH = (int)std::round(CatPhysics::CanvasHeight * app.settings.scale);
    int initX = 0, initY = 0;
    if (app.settings.posX != -99999 && app.settings.posY != -99999) {
        initX = app.settings.posX; initY = app.settings.posY;
    } else {
        computeDefaultOrigin(initW, initH, initX, initY);
    }

    DWORD exStyle = WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT
                  | (app.settings.alwaysOnTop ? WS_EX_TOPMOST : 0);

    app.hwnd = CreateWindowExW(
        exStyle,
        wc.lpszClassName,
        L"KuroCat",
        WS_POPUP,
        initX, initY, initW, initH,
        nullptr, nullptr, hInst, nullptr
    );
    if (!app.hwnd) {
        if (app.menuOwnerHwnd) DestroyWindow(app.menuOwnerHwnd);
        Gdiplus::GdiplusShutdown(gdipToken);
        if (hMutex) CloseHandle(hMutex);
        return 1;
    }

    applyWindowScaleAndPosition(app, false);
    app.input.registerRawInput(app.hwnd);
    registerTrayIcon(app);

    // Global shortcut Ctrl+Alt+Shift+P to toggle full click-through anytime!
    if (app.menuOwnerHwnd) {
        RegisterHotKey(app.menuOwnerHwnd, HOTKEY_CLICKTHROUGH_ID, MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT, 'P');
    }

    ShowWindow(app.hwnd, SW_SHOWNOACTIVATE);
    app.lastTickTime = nowSeconds();
    tickAndRender(app);
    SetTimer(app.hwnd, TIMER_RENDER, 16, nullptr);

    MSG msg = {};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    Gdiplus::GdiplusShutdown(gdipToken);
    if (hMutex) CloseHandle(hMutex);
    return 0;
}
