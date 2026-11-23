#include <gtk/gtk.h>
#include <gdk/gdk.h>
#include <cairo.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <limits.h>
#include <string>
#include <algorithm>
#include <unistd.h>
#include "KeyMap.hpp"
#include "InputEngine.hpp"
#include "CatPhysics.hpp"
#include "CatRenderer.hpp"

struct LinuxApp {
    GtkWidget* window = nullptr;
    GtkWidget* drawArea = nullptr;
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    GtkStatusIcon* trayIcon = nullptr;
    G_GNUC_END_IGNORE_DEPRECATIONS

    CatSettings settings;
    InputEngine input;
    CatPhysics physics;

    bool isVisible = true;
    bool isDragging = false;
    bool clickThroughTemporarilyUnlocked = false;
    double dragStartRootX = 0.0, dragStartRootY = 0.0;
    int dragStartWinX = 0, dragStartWinY = 0;

    bool hasLastHover = false;
    Pt lastHoverCanvas = { 0.0f, 0.0f };
    double lastTickTime = 0.0;

    bool demoActive = false;
    double demoStartTime = 0.0;
    int demoStepIdx = 0;
};

static LinuxApp* g_app = nullptr;

// MARK: - Launch at Login (Freedesktop XDG Autostart: Ubuntu/Debian/Deepin/统信 UOS/KDE/GNOME)

static std::string getAutostartDir() {
    const char* xdg = std::getenv("XDG_CONFIG_HOME");
    if (xdg && xdg[0] != '\0') return std::string(xdg) + "/autostart";
    const char* home = std::getenv("HOME");
    return std::string(home ? home : "/tmp") + "/.config/autostart";
}

static std::string getAutostartFilePath() {
    return getAutostartDir() + "/kurocat.desktop";
}

static std::string getSelfExePath() {
    char buf[PATH_MAX] = {0};
    ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (len > 0) {
        buf[len] = '\0';
        return std::string(buf);
    }
    return "kurocat";
}

static bool isAutoStartEnabled() {
    return access(getAutostartFilePath().c_str(), F_OK) == 0;
}

static bool setAutoStartEnabled(bool enable) {
    std::string path = getAutostartFilePath();
    if (!enable) {
        std::remove(path.c_str());
        return true;
    }
    std::string dir = getAutostartDir();
    g_mkdir_with_parents(dir.c_str(), 0755);
    std::string exe = getSelfExePath();
    std::ofstream f(path);
    if (!f.is_open()) return false;
    f << "[Desktop Entry]\n"
      << "Type=Application\n"
      << "Name=KuroCat\n"
      << "Name[zh_CN]=KuroCat 黑猫桌宠\n"
      << "Comment=Native desktop keyboard & mouse cat pet\n"
      << "Exec=\"" << exe << "\"\n"
      << "Icon=kurocat\n"
      << "Terminal=false\n"
      << "X-GNOME-Autostart-enabled=true\n";
    return f.good();
}

static void updateInputShape(LinuxApp& app) {
    if (!app.window || !gtk_widget_get_realized(app.window)) return;
    if (app.settings.fullClickThrough && !app.clickThroughTemporarilyUnlocked) {
        cairo_region_t* empty = cairo_region_create();
        gtk_widget_input_shape_combine_region(app.window, empty);
        cairo_region_destroy(empty);
        return;
    }

    // Smart per-area input mask: transparent corners pass clicks straight through,
    // while the cat head/body & mini keyboard remain interactive for petting, dragging & right-click!
    float s = app.settings.scale;
    cairo_region_t* reg = cairo_region_create();
    cairo_rectangle_int_t catBox = {
        (int)(128 * s), (int)(72 * s), (int)(116 * s), (int)(172 * s)
    };
    cairo_rectangle_int_t kbBox = {
        (int)(56 * s), (int)(230 * s), (int)(242 * s), (int)(72 * s)
    };
    cairo_region_union_rectangle(reg, &catBox);
    cairo_region_union_rectangle(reg, &kbBox);
    gtk_widget_input_shape_combine_region(app.window, reg);
    cairo_region_destroy(reg);
}

static void getDefaultOrigin(int w, int h, int& outX, int& outY) {
    GdkDisplay* dpy = gdk_display_get_default();
    GdkMonitor* mon = dpy ? gdk_display_get_primary_monitor(dpy) : nullptr;
    if (!mon && dpy) mon = gdk_display_get_monitor(dpy, 0);
    GdkRectangle geo = { 0, 0, 1440, 900 };
    if (mon) gdk_monitor_get_workarea(mon, &geo);
    outX = geo.x + geo.width - w - 24;
    outY = geo.y + geo.height - h - 16;
}

static void applyWindowScaleAndPos(LinuxApp& app, bool anchorBottomCenter) {
    int newW = (int)std::round(CatPhysics::CanvasWidth * app.settings.scale);
    int newH = (int)std::round(CatPhysics::CanvasHeight * app.settings.scale);

    int x = app.settings.posX;
    int y = app.settings.posY;
    if (anchorBottomCenter && app.window) {
        int oldX = 0, oldY = 0, oldW = 0, oldH = 0;
        gtk_window_get_position(GTK_WINDOW(app.window), &oldX, &oldY);
        gtk_window_get_size(GTK_WINDOW(app.window), &oldW, &oldH);
        x = oldX + oldW / 2 - newW / 2;
        y = oldY + oldH - newH;
    } else if (x == -99999 || y == -99999) {
        getDefaultOrigin(newW, newH, x, y);
    }

    app.settings.posX = x;
    app.settings.posY = y;
    gtk_window_resize(GTK_WINDOW(app.window), newW, newH);
    gtk_window_move(GTK_WINDOW(app.window), x, y);
    gtk_window_set_keep_above(GTK_WINDOW(app.window), app.settings.alwaysOnTop ? TRUE : FALSE);
    updateInputShape(app);
    app.settings.save();
}

static GdkPixbuf* createCatTrayPixbuf() {
    constexpr int sz = 32;
    cairo_surface_t* surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, sz, sz);
    cairo_t* cr = cairo_create(surf);
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

    // Matte black cat head silhouette
    cairo_set_source_rgba(cr, 0.085, 0.085, 0.10, 1.0);
    cairo_move_to(cr, 4, 15); cairo_line_to(cr, 6, 3); cairo_line_to(cr, 14, 11); cairo_close_path(cr); cairo_fill(cr);
    cairo_move_to(cr, 28, 15); cairo_line_to(cr, 26, 3); cairo_line_to(cr, 18, 11); cairo_close_path(cr); cairo_fill(cr);
    cairo_save(cr); cairo_translate(cr, 16, 18.5); cairo_scale(cr, 12.0, 10.5); cairo_arc(cr, 0, 0, 1.0, 0, 6.2832); cairo_restore(cr); cairo_fill(cr);

    // Chartreuse glowing eyes
    cairo_set_source_rgba(cr, 0.79, 0.95, 0.25, 1.0);
    cairo_save(cr); cairo_translate(cr, 11.5, 17.2); cairo_scale(cr, 3.0, 2.6); cairo_arc(cr, 0, 0, 1.0, 0, 6.2832); cairo_restore(cr); cairo_fill(cr);
    cairo_save(cr); cairo_translate(cr, 20.5, 17.2); cairo_scale(cr, 3.0, 2.6); cairo_arc(cr, 0, 0, 1.0, 0, 6.2832); cairo_restore(cr); cairo_fill(cr);

    cairo_set_source_rgba(cr, 0.08, 0.08, 0.10, 1.0);
    cairo_save(cr); cairo_translate(cr, 11.5, 17.2); cairo_scale(cr, 0.9, 1.9); cairo_arc(cr, 0, 0, 1.0, 0, 6.2832); cairo_restore(cr); cairo_fill(cr);
    cairo_save(cr); cairo_translate(cr, 20.5, 17.2); cairo_scale(cr, 0.9, 1.9); cairo_arc(cr, 0, 0, 1.0, 0, 6.2832); cairo_restore(cr); cairo_fill(cr);

    GdkPixbuf* pb = gdk_pixbuf_get_from_surface(surf, 0, 0, sz, sz);
    cairo_destroy(cr);
    cairo_surface_destroy(surf);
    return pb;
}

static void updateTrayTooltip(LinuxApp& app) {
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    if (app.trayIcon) {
        gtk_status_icon_set_tooltip_text(
            app.trayIcon,
            trU8(app.settings.language,
                 "KuroCat Desktop Pet (Right-click for settings)",
                 "KuroCat 黑猫键盘桌宠 (右键设置)"));
    }
    G_GNUC_END_IGNORE_DEPRECATIONS
}

static void setGdkColorFromRGB(GtkColorButton* btn, RGBColor c) {
    GdkRGBA rgba = { c.r / 255.0, c.g / 255.0, c.b / 255.0, 1.0 };
    gtk_color_chooser_set_rgba(GTK_COLOR_CHOOSER(btn), &rgba);
}

static RGBColor rgbFromColorButton(GtkColorButton* btn) {
    GdkRGBA rgba = { 0, 0, 0, 1 };
    gtk_color_chooser_get_rgba(GTK_COLOR_CHOOSER(btn), &rgba);
    return {
        (uint8_t)std::clamp((int)std::round(rgba.red * 255.0), 0, 255),
        (uint8_t)std::clamp((int)std::round(rgba.green * 255.0), 0, 255),
        (uint8_t)std::clamp((int)std::round(rgba.blue * 255.0), 0, 255)
    };
}

struct StudioWidgets {
    GtkWidget* dialog = nullptr;
    GtkWidget* patternCombo = nullptr;
    GtkWidget* furScale = nullptr;
    GtkWidget* primaryBtn = nullptr;
    GtkWidget* secondaryBtn = nullptr;
    GtkWidget* tertiaryBtn = nullptr;
    GtkWidget* eyeBtn = nullptr;
    bool updating = false;
};

static StudioWidgets g_studio;

static void syncStudioControlsFromApp() {
    if (!g_studio.dialog || !g_app) return;
    g_studio.updating = true;
    const auto& a = g_app->settings.appearance;
    gtk_combo_box_set_active(GTK_COMBO_BOX(g_studio.patternCombo), (int)a.pattern);
    gtk_range_set_value(GTK_RANGE(g_studio.furScale), a.furLength);
    setGdkColorFromRGB(GTK_COLOR_BUTTON(g_studio.primaryBtn), a.primaryColor);
    setGdkColorFromRGB(GTK_COLOR_BUTTON(g_studio.secondaryBtn), a.secondaryColor);
    setGdkColorFromRGB(GTK_COLOR_BUTTON(g_studio.tertiaryBtn), a.tertiaryColor);
    setGdkColorFromRGB(GTK_COLOR_BUTTON(g_studio.eyeBtn), a.eyeColor);
    g_studio.updating = false;
}

static void showCustomCatStudio(LinuxApp& app) {
    if (g_studio.dialog) {
        gtk_window_present(GTK_WINDOW(g_studio.dialog));
        syncStudioControlsFromApp();
        return;
    }

    auto L = [&](const char* en, const char* zh) { return trU8(app.settings.language, en, zh); };

    GtkWidget* dlg = gtk_dialog_new_with_buttons(
        L("KuroCat — Custom Cat Studio", "KuroCat — 自定义猫咪工坊"),
        nullptr,
        GTK_DIALOG_DESTROY_WITH_PARENT,
        L("Close", "关闭"), GTK_RESPONSE_CLOSE,
        nullptr);
    gtk_window_set_default_size(GTK_WINDOW(dlg), 460, 460);
    gtk_window_set_keep_above(GTK_WINDOW(dlg), TRUE);
    g_studio.dialog = dlg;

    GtkWidget* content = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    GtkWidget* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_set_border_width(GTK_CONTAINER(root), 14);
    gtk_container_add(GTK_CONTAINER(content), root);

    // 1. Breed Presets Grid (10 breeds, 2 columns x 5 rows)
    GtkWidget* breedLbl = gtk_label_new(L("Breed Presets (1-Click):", "常见品种预设 (一键切换)："));
    gtk_widget_set_halign(breedLbl, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(root), breedLbl, FALSE, FALSE, 0);

    GtkWidget* grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 6);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_column_homogeneous(GTK_GRID(grid), TRUE);

    struct PresetDef { CatBreedPreset p; const char* en; const char* zh; };
    const PresetDef presets[] = {
        { CatBreedPreset::ClassicBlack,    "Classic Black",        "经典小黑猫" },
        { CatBreedPreset::Siamese,         "Siamese",              "挖煤暹罗猫" },
        { CatBreedPreset::OrangeTabby,     "Orange Tabby",         "大橘虎斑猫" },
        { CatBreedPreset::SilverTabby,     "Silver Tabby",         "银渐层美短" },
        { CatBreedPreset::Tuxedo,          "Tuxedo",               "燕尾服奶牛猫" },
        { CatBreedPreset::Calico,          "Calico",               "三花猫" },
        { CatBreedPreset::Ragdoll,         "Long-Haired Ragdoll",  "长毛布偶猫" },
        { CatBreedPreset::BritishBlue,     "British Blue",         "英短蓝猫" },
        { CatBreedPreset::WhitePersian,    "White Persian",        "长毛白波斯" },
        { CatBreedPreset::GoldenMaineCoon, "Golden Maine Coon",    "长毛金缅因" },
    };

    for (int i = 0; i < 10; ++i) {
        GtkWidget* btn = gtk_button_new_with_label(L(presets[i].en, presets[i].zh));
        g_signal_connect(btn, "clicked", G_CALLBACK(+[](GtkButton*, gpointer data) {
            if (!g_app) return;
            g_app->settings.appearance = makeBreedPreset((CatBreedPreset)(intptr_t)data);
            g_app->settings.save();
            syncStudioControlsFromApp();
        }), (gpointer)(intptr_t)presets[i].p);
        gtk_grid_attach(GTK_GRID(grid), btn, i % 2, i / 2, 1, 1);
    }
    gtk_box_pack_start(GTK_BOX(root), grid, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(root), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 2);

    // 2. Fur Pattern Combo
    GtkWidget* patRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    GtkWidget* patLbl = gtk_label_new(L("Fur Pattern:", "毛色花纹："));
    GtkWidget* patCombo = gtk_combo_box_text_new();
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(patCombo), L("Solid", "纯色"));
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(patCombo), L("Colorpoint", "重点色"));
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(patCombo), L("Tuxedo", "奶牛燕尾服"));
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(patCombo), L("Tabby", "虎斑条纹"));
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(patCombo), L("Calico", "三花拼色"));
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(patCombo), L("Spotted", "豹点斑纹"));
    g_studio.patternCombo = patCombo;
    g_signal_connect(patCombo, "changed", G_CALLBACK(+[](GtkComboBox* cb, gpointer) {
        if (!g_app || g_studio.updating) return;
        int idx = gtk_combo_box_get_active(cb);
        if (idx >= 0 && idx <= 5) {
            g_app->settings.appearance.pattern = (FurPattern)idx;
            g_app->settings.appearance.presetID = -1;
            g_app->settings.save();
        }
    }), nullptr);
    gtk_box_pack_start(GTK_BOX(patRow), patLbl, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(patRow), patCombo, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(root), patRow, FALSE, FALSE, 0);

    // 3. Fur Length Slider
    GtkWidget* furRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    GtkWidget* furLbl = gtk_label_new(L("Fur Length:", "毛发长度："));
    GtkWidget* furScale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0.0, 1.0, 0.02);
    gtk_scale_set_digits(GTK_SCALE(furScale), 2);
    g_studio.furScale = furScale;
    g_signal_connect(furScale, "value-changed", G_CALLBACK(+[](GtkRange* r, gpointer) {
        if (!g_app || g_studio.updating) return;
        g_app->settings.appearance.furLength = (float)gtk_range_get_value(r);
        g_app->settings.appearance.presetID = -1;
        g_app->settings.save();
    }), nullptr);
    gtk_box_pack_start(GTK_BOX(furRow), furLbl, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(furRow), furScale, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(root), furRow, FALSE, FALSE, 0);

    // 4. Multi-Color Pickers
    GtkWidget* colGrid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(colGrid), 6);
    gtk_grid_set_column_spacing(GTK_GRID(colGrid), 10);

    auto addColorRow = [&](int row, const char* label, GtkWidget*& outBtn, int slot) {
        GtkWidget* l = gtk_label_new(label);
        gtk_widget_set_halign(l, GTK_ALIGN_START);
        GtkWidget* btn = gtk_color_button_new();
        gtk_color_chooser_set_use_alpha(GTK_COLOR_CHOOSER(btn), FALSE);
        outBtn = btn;
        g_signal_connect(btn, "color-set", G_CALLBACK(+[](GtkColorButton* b, gpointer data) {
            if (!g_app || g_studio.updating) return;
            RGBColor c = rgbFromColorButton(b);
            int s = (int)(intptr_t)data;
            if (s == 0) g_app->settings.appearance.primaryColor = c;
            else if (s == 1) g_app->settings.appearance.secondaryColor = c;
            else if (s == 2) g_app->settings.appearance.tertiaryColor = c;
            else if (s == 3) g_app->settings.appearance.eyeColor = c;
            g_app->settings.appearance.presetID = -1;
            g_app->settings.save();
        }), (gpointer)(intptr_t)slot);
        gtk_grid_attach(GTK_GRID(colGrid), l, 0, row, 1, 1);
        gtk_grid_attach(GTK_GRID(colGrid), btn, 1, row, 1, 1);
    };

    addColorRow(0, L("Primary Coat Color:", "主毛色："), g_studio.primaryBtn, 0);
    addColorRow(1, L("Secondary / Pattern Color:", "副毛色 / 花纹色："), g_studio.secondaryBtn, 1);
    addColorRow(2, L("Tertiary / Accent Color:", "第三花纹色 / 点缀色："), g_studio.tertiaryBtn, 2);
    addColorRow(3, L("Eye Color:", "瞳孔颜色："), g_studio.eyeBtn, 3);
    gtk_box_pack_start(GTK_BOX(root), colGrid, FALSE, FALSE, 0);

    syncStudioControlsFromApp();

    g_signal_connect(dlg, "response", G_CALLBACK(+[](GtkDialog* d, gint, gpointer) {
        gtk_widget_destroy(GTK_WIDGET(d));
    }), nullptr);
    g_signal_connect(dlg, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer) {
        g_studio = StudioWidgets{};
    }), nullptr);

    gtk_widget_show_all(dlg);
}

static void showPopupMenu(LinuxApp& app, GdkEventButton* evt) {
    GtkWidget* menu = gtk_menu_new();
    auto L = [&](const char* en, const char* zh) { return trU8(app.settings.language, en, zh); };

    auto addDisabled = [&](const std::string& label) {
        GtkWidget* it = gtk_menu_item_new_with_label(label.c_str());
        gtk_widget_set_sensitive(it, FALSE);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), it);
    };
    auto addSep = [&]() {
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
    };
    auto addCheck = [&](const char* label, bool checked, GCallback cb, gpointer data = nullptr) {
        GtkWidget* it = gtk_check_menu_item_new_with_label(label);
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), checked ? TRUE : FALSE);
        g_signal_connect(it, "toggled", cb, data);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), it);
    };
    auto addAction = [&](const char* label, GCallback cb, gpointer data = nullptr) {
        GtkWidget* it = gtk_menu_item_new_with_label(label);
        g_signal_connect(it, "activate", cb, data);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), it);
    };

    std::string moodSuffix;
    if (app.physics.sleepDepth.value > 0.55f) moodSuffix = L("  ·  Sleeping", "  ·  打盹中");
    else if (app.physics.tiredness.value > 0.35f) moodSuffix = L("  ·  Late-Night Tired", "  ·  熬夜困倦中");

    addDisabled(app.input.statusText());
    if (isChineseUI(app.settings.language)) {
        addDisabled("今日击键 " + std::to_string(app.input.totalKeystrokesToday)
            + "  ·  KPM " + std::to_string(app.input.currentKPM())
            + "  ·  摸猫 " + std::to_string(app.physics.totalPetSessions) + " 次" + moodSuffix);
    } else {
        addDisabled("Keys " + std::to_string(app.input.totalKeystrokesToday)
            + "  ·  KPM " + std::to_string(app.input.currentKPM())
            + "  ·  Pets " + std::to_string(app.physics.totalPetSessions) + moodSuffix);
    }
    addSep();

    addAction(app.isVisible ? L("Hide Cat", "隐藏小猫") : L("Show Cat", "显示小猫"), G_CALLBACK(+[](GtkMenuItem*, gpointer) {
        g_app->isVisible = !g_app->isVisible;
        if (g_app->isVisible) gtk_widget_show(g_app->window);
        else gtk_widget_hide(g_app->window);
    }));

    addCheck(L("Full Click-Through (Hold Alt to Drag/Menu)", "完全鼠标穿透 (按住 Alt 可临时右键/拖动)"),
             app.settings.fullClickThrough, G_CALLBACK(+[](GtkCheckMenuItem* item, gpointer) {
        g_app->settings.fullClickThrough = gtk_check_menu_item_get_active(item);
        updateInputShape(*g_app);
        g_app->settings.save();
    }));

    addCheck(L("Always on Top", "窗口置顶显示"), app.settings.alwaysOnTop, G_CALLBACK(+[](GtkCheckMenuItem* item, gpointer) {
        g_app->settings.alwaysOnTop = gtk_check_menu_item_get_active(item);
        applyWindowScaleAndPos(*g_app, false);
    }));

    addCheck(L("Launch at Login", "开机自动启动"), isAutoStartEnabled(), G_CALLBACK(+[](GtkCheckMenuItem* item, gpointer) {
        setAutoStartEnabled(gtk_check_menu_item_get_active(item));
    }));

    addSep();

    addCheck(L("Show Keycap Bubbles ([S] [W])", "显示按键气泡 ([S] [W] [⇧])"), app.settings.showKeyBadges, G_CALLBACK(+[](GtkCheckMenuItem* item, gpointer) {
        g_app->settings.showKeyBadges = gtk_check_menu_item_get_active(item);
        g_app->settings.save();
    }));
    addCheck(L("3-Key Hind Foot Easter Egg", "3键同时按「用脚按」彩蛋 🐾"), app.settings.footEasterEgg, G_CALLBACK(+[](GtkCheckMenuItem* item, gpointer) {
        g_app->settings.footEasterEgg = gtk_check_menu_item_get_active(item);
        g_app->settings.save();
    }));
    addCheck(L("Pet Head / Body Interaction", "摸头/摸背闭眼互动"), app.settings.petInteraction, G_CALLBACK(+[](GtkCheckMenuItem* item, gpointer) {
        g_app->settings.petInteraction = gtk_check_menu_item_get_active(item);
        g_app->settings.save();
    }));

    addSep();

    // Custom Cat Studio action
    addAction(L("Open Custom Cat Studio...", "打开自定义猫咪工坊..."), G_CALLBACK(+[](GtkMenuItem*, gpointer) {
        if (g_app) showCustomCatStudio(*g_app);
    }));

    // Cat Breed Presets submenu (10 breeds)
    {
        GtkWidget* sub = gtk_menu_new();
        auto addBreed = [&](const char* en, const char* zh, CatBreedPreset p) {
            GtkWidget* it = gtk_check_menu_item_new_with_label(L(en, zh));
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), app.settings.appearance.presetID == (int)p);
            g_signal_connect(it, "activate", G_CALLBACK(+[](GtkMenuItem*, gpointer d) {
                g_app->settings.appearance = makeBreedPreset((CatBreedPreset)(intptr_t)d);
                g_app->settings.save();
                syncStudioControlsFromApp();
            }), (gpointer)(intptr_t)p);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), it);
        };
        addBreed("Classic Black",       "经典小黑猫 (原版)", CatBreedPreset::ClassicBlack);
        addBreed("Siamese",             "挖煤暹罗猫",       CatBreedPreset::Siamese);
        addBreed("Orange Tabby",        "大橘虎斑猫",       CatBreedPreset::OrangeTabby);
        addBreed("Silver Tabby",        "银渐层美短",       CatBreedPreset::SilverTabby);
        addBreed("Tuxedo",              "燕尾服奶牛猫",     CatBreedPreset::Tuxedo);
        addBreed("Calico",              "三花猫",           CatBreedPreset::Calico);
        addBreed("Long-Haired Ragdoll", "长毛布偶猫",       CatBreedPreset::Ragdoll);
        addBreed("British Blue",        "英短蓝猫",         CatBreedPreset::BritishBlue);
        addBreed("White Persian",       "长毛白波斯",       CatBreedPreset::WhitePersian);
        addBreed("Golden Maine Coon",   "长毛金缅因",       CatBreedPreset::GoldenMaineCoon);
        GtkWidget* parent = gtk_menu_item_new_with_label(L("Cat Breed Presets", "猫咪品种预设 🐱"));
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(parent), sub);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), parent);
    }

    // Tie / Bow Tie submenu
    {
        GtkWidget* sub = gtk_menu_new();
        GtkWidget* toggle = gtk_check_menu_item_new_with_label(L("Wear Tie / Bow Tie", "佩戴领带/蝴蝶结"));
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(toggle), app.settings.showTie);
        g_signal_connect(toggle, "toggled", G_CALLBACK(+[](GtkCheckMenuItem* item, gpointer) {
            g_app->settings.showTie = gtk_check_menu_item_get_active(item);
            g_app->settings.save();
        }), nullptr);
        gtk_menu_shell_append(GTK_MENU_SHELL(sub), toggle);
        gtk_menu_shell_append(GTK_MENU_SHELL(sub), gtk_separator_menu_item_new());

        auto addTieStyle = [&](const char* en, const char* zh, TieStyle s) {
            GtkWidget* it = gtk_check_menu_item_new_with_label(L(en, zh));
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), app.settings.tieStyle == s);
            g_signal_connect(it, "activate", G_CALLBACK(+[](GtkMenuItem*, gpointer d) {
                g_app->settings.tieStyle = (TieStyle)(intptr_t)d;
                g_app->settings.showTie = true;
                g_app->settings.save();
            }), (gpointer)(intptr_t)s);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), it);
        };
        addTieStyle("Necktie", "领带", TieStyle::Necktie);
        addTieStyle("Bow Tie", "蝴蝶结", TieStyle::BowTie);
        gtk_menu_shell_append(GTK_MENU_SHELL(sub), gtk_separator_menu_item_new());

        auto addTieCol = [&](const char* en, const char* zh, TieColorTheme c) {
            GtkWidget* it = gtk_check_menu_item_new_with_label(L(en, zh));
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), app.settings.tieColor == c);
            g_signal_connect(it, "activate", G_CALLBACK(+[](GtkMenuItem*, gpointer d) {
                g_app->settings.tieColor = (TieColorTheme)(intptr_t)d;
                g_app->settings.showTie = true;
                g_app->settings.save();
            }), (gpointer)(intptr_t)c);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), it);
        };
        addTieCol("Cyan",     "清透天青", TieColorTheme::Cyan);
        addTieCol("Crimson",  "珊瑚绯红", TieColorTheme::Crimson);
        addTieCol("Navy",     "浅学院蓝", TieColorTheme::Navy);
        addTieCol("Emerald",  "薄荷祖母绿", TieColorTheme::Emerald);
        addTieCol("Amber",    "柔光琥珀", TieColorTheme::Amber);
        addTieCol("Lavender", "淡雅薰衣草", TieColorTheme::Lavender);
        gtk_menu_shell_append(GTK_MENU_SHELL(sub), gtk_separator_menu_item_new());

        auto addTiePat = [&](const char* en, const char* zh, TiePattern p) {
            GtkWidget* it = gtk_check_menu_item_new_with_label(L(en, zh));
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), app.settings.tiePattern == p);
            g_signal_connect(it, "activate", G_CALLBACK(+[](GtkMenuItem*, gpointer d) {
                g_app->settings.tiePattern = (TiePattern)(intptr_t)d;
                g_app->settings.showTie = true;
                g_app->settings.save();
            }), (gpointer)(intptr_t)p);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), it);
        };
        addTiePat("Scottish Tartan",  "苏格兰格子", TiePattern::ScottishGrid);
        addTiePat("Diagonal Stripes", "学院斜条纹", TiePattern::DiagonalStripe);
        addTiePat("Polka Dots",       "波尔卡圆点", TiePattern::PolkaDot);
        addTiePat("Solid Silk",       "纯色丝绸",   TiePattern::Solid);

        GtkWidget* parent = gtk_menu_item_new_with_label(L("Tie / Bow Tie", "领带与蝴蝶结 👔"));
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(parent), sub);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), parent);
    }

    // Late-Night Tired Eyes submenu
    {
        GtkWidget* sub = gtk_menu_new();
        auto addTired = [&](const char* en, const char* zh, TiredEyesMode m) {
            GtkWidget* it = gtk_check_menu_item_new_with_label(L(en, zh));
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), app.settings.tiredEyesMode == m);
            g_signal_connect(it, "activate", G_CALLBACK(+[](GtkMenuItem*, gpointer d) {
                g_app->settings.tiredEyesMode = (TiredEyesMode)(intptr_t)d;
                g_app->settings.save();
            }), (gpointer)(intptr_t)m);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), it);
        };
        addTired("Auto (0:00 - 6:00)", "自动 (凌晨 0:00-6:00)", TiredEyesMode::AutoLateNight);
        addTired("Always On",          "始终开启",             TiredEyesMode::AlwaysOn);
        addTired("Off",                "关闭",                 TiredEyesMode::Off);
        GtkWidget* parent = gtk_menu_item_new_with_label(L("Late-Night Tired Eyes", "熬夜困倦眼神 🌙"));
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(parent), sub);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), parent);
    }

    // Keyboard Theme submenu
    {
        GtkWidget* sub = gtk_menu_new();
        auto addKb = [&](const char* en, const char* zh, KeyboardTheme t) {
            GtkWidget* it = gtk_check_menu_item_new_with_label(L(en, zh));
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), app.settings.keyboardTheme == t);
            g_signal_connect(it, "activate", G_CALLBACK(+[](GtkMenuItem*, gpointer p) {
                g_app->settings.keyboardTheme = (KeyboardTheme)(intptr_t)p;
                g_app->settings.save();
            }), (gpointer)(intptr_t)t);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), it);
        };
        addKb("Classic Milk & Warm Yellow", "经典奶白暖黄 (原版)", KeyboardTheme::ClassicMilk);
        addKb("Midnight Hacker",            "暗夜极客黑",         KeyboardTheme::MidnightHacker);
        addKb("Retro Cream",                "复古奶油灰",         KeyboardTheme::RetroCream);
        GtkWidget* parent = gtk_menu_item_new_with_label(L("Keyboard Theme", "键盘配色"));
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(parent), sub);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), parent);
    }

    // Scale submenu
    {
        GtkWidget* sub = gtk_menu_new();
        struct ScaleDef { const char* en; const char* zh; int pct; };
        const ScaleDef scales[] = {
            {"Mini (0.65x)",     "迷你 (0.65x)", 65},
            {"Small (0.85x)",    "偏小 (0.85x)", 85},
            {"Standard (1.0x)",  "标准 (1.0x)", 100},
            {"Large (1.25x)",    "偏大 (1.25x)", 125},
            {"XL (1.5x)",        "超大 (1.5x)", 150}
        };
        for (const auto& sc : scales) {
            GtkWidget* it = gtk_check_menu_item_new_with_label(L(sc.en, sc.zh));
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), std::fabs(app.settings.scale * 100.0f - sc.pct) < 5.0f);
            g_signal_connect(it, "activate", G_CALLBACK(+[](GtkMenuItem*, gpointer p) {
                g_app->settings.scale = (float)(intptr_t)p / 100.0f;
                applyWindowScaleAndPos(*g_app, true);
            }), (gpointer)(intptr_t)sc.pct);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), it);
        }
        GtkWidget* parent = gtk_menu_item_new_with_label(L("Window Size", "尺寸大小"));
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(parent), sub);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), parent);
    }

    // Language submenu
    {
        GtkWidget* sub = gtk_menu_new();
        auto addLang = [&](const char* lbl, AppLanguage lang) {
            GtkWidget* it = gtk_check_menu_item_new_with_label(lbl);
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(it), app.settings.language == lang);
            g_signal_connect(it, "activate", G_CALLBACK(+[](GtkMenuItem*, gpointer d) {
                g_app->settings.language = (AppLanguage)(intptr_t)d;
                g_app->settings.save();
                updateTrayTooltip(*g_app);
            }), (gpointer)(intptr_t)lang);
            gtk_menu_shell_append(GTK_MENU_SHELL(sub), it);
        };
        addLang(L("Auto (System)", "跟随系统"), AppLanguage::Auto);
        addLang("English", AppLanguage::English);
        addLang("简体中文", AppLanguage::ZhCN);
        GtkWidget* parent = gtk_menu_item_new_with_label("Language / 语言 🌐");
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(parent), sub);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), parent);
    }

    addSep();
    addAction(L("Demo Typing Animation", "演示打字动画"), G_CALLBACK(+[](GtkMenuItem*, gpointer) {
        g_app->demoActive = true;
        g_app->demoStartTime = nowSeconds();
        g_app->demoStepIdx = 0;
    }));
    addAction(L("Reset Position to Bottom-Right", "重置位置到右下角"), G_CALLBACK(+[](GtkMenuItem*, gpointer) {
        g_app->settings.posX = -99999;
        g_app->settings.posY = -99999;
        applyWindowScaleAndPos(*g_app, false);
    }));
    addSep();
    addAction(L("Quit KuroCat", "退出 KuroCat"), G_CALLBACK(+[](GtkMenuItem*, gpointer) {
        gtk_main_quit();
    }));

    gtk_widget_show_all(menu);
    if (evt) {
        gtk_menu_popup_at_pointer(GTK_MENU(menu), (GdkEvent*)evt);
    } else {
        gtk_menu_popup_at_pointer(GTK_MENU(menu), nullptr);
    }
}

static gboolean onDraw(GtkWidget* widget, cairo_t* cr, gpointer) {
    int w = gtk_widget_get_allocated_width(widget);
    int h = gtk_widget_get_allocated_height(widget);

    cairo_save(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    cairo_paint(cr);
    cairo_restore(cr);

    cairo_save(cr);
    cairo_scale(cr, (double)w / CatPhysics::CanvasWidth, (double)h / CatPhysics::CanvasHeight);
    CatRenderer::draw(cr, g_app->physics, g_app->settings);
    cairo_restore(cr);
    return FALSE;
}

static gboolean onButtonPress(GtkWidget*, GdkEventButton* evt, gpointer) {
    if (evt->button == 3) {
        showPopupMenu(*g_app, evt);
        return TRUE;
    }
    if (evt->button == 1 && (!g_app->settings.fullClickThrough || g_app->clickThroughTemporarilyUnlocked)) {
        g_app->isDragging = true;
        g_app->dragStartRootX = evt->x_root;
        g_app->dragStartRootY = evt->y_root;
        gtk_window_get_position(GTK_WINDOW(g_app->window), &g_app->dragStartWinX, &g_app->dragStartWinY);
        return TRUE;
    }
    return FALSE;
}

static gboolean onMotionNotify(GtkWidget*, GdkEventMotion* evt, gpointer) {
    if (g_app->isDragging) {
        int nx = g_app->dragStartWinX + (int)std::round(evt->x_root - g_app->dragStartRootX);
        int ny = g_app->dragStartWinY + (int)std::round(evt->y_root - g_app->dragStartRootY);
        gtk_window_move(GTK_WINDOW(g_app->window), nx, ny);
        return TRUE;
    }
    return FALSE;
}

static gboolean onButtonRelease(GtkWidget*, GdkEventButton* evt, gpointer) {
    if (evt->button == 1 && g_app->isDragging) {
        g_app->isDragging = false;
        gtk_window_get_position(GTK_WINDOW(g_app->window), &g_app->settings.posX, &g_app->settings.posY);
        g_app->settings.save();
        return TRUE;
    }
    return FALSE;
}

static gboolean onFrameTick(gpointer) {
    if (!g_app || !g_app->isVisible) return G_SOURCE_CONTINUE;

    double now = nowSeconds();
    float dt = (float)(now - g_app->lastTickTime);
    g_app->lastTickTime = now;
    if (dt <= 0.0f || dt > 0.2f) dt = 1.0f / 60.0f;

    // Fallback GDK cursor query (for Wayland / non-X11) + Alt-key hold check
    float fbX = 0.0f, fbY = 0.0f;
    bool hasFb = false;
    bool gdkAltHeld = false;
    if (GdkDisplay* dpy = gdk_display_get_default()) {
        if (GdkSeat* seat = gdk_display_get_default_seat(dpy)) {
            if (GdkDevice* ptr = gdk_seat_get_pointer(seat)) {
                gint gx = 0, gy = 0;
                gdk_device_get_position(ptr, nullptr, &gx, &gy);
                fbX = (float)gx; fbY = (float)gy; hasFb = true;
                if (GdkWindow* gw = gtk_widget_get_window(g_app->window)) {
                    GdkModifierType mask = (GdkModifierType)0;
                    gdk_window_get_device_position(gw, ptr, nullptr, nullptr, &mask);
                    if (mask & GDK_MOD1_MASK) gdkAltHeld = true;
                }
            }
        }
    }

    g_app->input.pollAndDrain(dt, fbX, fbY, hasFb);

    // Hold Alt to temporarily unlock Full Click-Through so the user can always right-click/drag!
    bool altHeld = gdkAltHeld
        || g_app->input.activeKeys.count(PhysicalKey::LeftOption) > 0
        || g_app->input.activeKeys.count(PhysicalKey::RightOption) > 0;
    if (altHeld != g_app->clickThroughTemporarilyUnlocked) {
        g_app->clickThroughTemporarilyUnlocked = altHeld;
        if (g_app->settings.fullClickThrough) {
            updateInputShape(*g_app);
        }
    }

    if (g_app->demoActive) {
        static const PhysicalKey demoKeys[] = {
            PhysicalKey::W, PhysicalKey::A, PhysicalKey::S, PhysicalKey::D,
            PhysicalKey::F, PhysicalKey::J, PhysicalKey::O, PhysicalKey::E,
            PhysicalKey::Space, PhysicalKey::LeftShift
        };
        int targetIdx = (int)((now - g_app->demoStartTime) / 0.13);
        while (g_app->demoStepIdx <= targetIdx && g_app->demoStepIdx < 10) {
            g_app->physics.triggerKeyDown(demoKeys[g_app->demoStepIdx], g_app->settings);
            g_app->demoStepIdx++;
        }
        if (g_app->demoStepIdx >= 10) g_app->demoActive = false;
    }

    int winX = 0, winY = 0, winW = 360, winH = 320;
    gtk_window_get_position(GTK_WINDOW(g_app->window), &winX, &winY);
    gtk_window_get_size(GTK_WINDOW(g_app->window), &winW, &winH);

    // Petting detection using global cursor position (works in Smart AND Full Click-Through modes!)
    if (!g_app->isDragging && winW > 0 && winH > 0) {
        Pt cur = g_app->input.lastCursorPos;
        if (cur.x >= winX && cur.x <= winX + winW && cur.y >= winY && cur.y <= winY + winH) {
            Pt cp = {
                (cur.x - (float)winX) / (float)winW * CatPhysics::CanvasWidth,
                (cur.y - (float)winY) / (float)winH * CatPhysics::CanvasHeight
            };
            CatHitZone zone = CatRenderer::hitTest(cp, g_app->physics);
            if (zone == CatHitZone::Head || zone == CatHitZone::Body) {
                if (g_app->hasLastHover) {
                    float d = std::hypot(cp.x - g_app->lastHoverCanvas.x, cp.y - g_app->lastHoverCanvas.y);
                    if (d > 1.2f && d < 80.0f) {
                        g_app->physics.registerPetStroke(cp, d, zone == CatHitZone::Head, g_app->settings);
                    }
                }
                g_app->lastHoverCanvas = cp;
                g_app->hasLastHover = true;
            } else {
                g_app->hasLastHover = false;
            }
        } else {
            g_app->hasLastHover = false;
        }
    }

    g_app->physics.step(dt, (float)winX, (float)winY, (float)winW, g_app->input, g_app->settings);
    gtk_widget_queue_draw(g_app->drawArea);
    return G_SOURCE_CONTINUE;
}

int main(int argc, char** argv) {
    gtk_init(&argc, &argv);

    LinuxApp app;
    g_app = &app;
    app.settings.load();
    if (isAutoStartEnabled()) {
        // Keep Exec path updated if user moved portable kurocat binary
        setAutoStartEnabled(true);
    }

    app.input.onKeyDown = [&](PhysicalKey k) { app.physics.triggerKeyDown(k, app.settings); };
    app.input.onMouseClick = [&](int btn, bool down) { app.physics.triggerMouseClick(btn, down); };
    app.input.start();

    app.window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(app.window), "KuroCat");
    gtk_window_set_decorated(GTK_WINDOW(app.window), FALSE);
    gtk_window_set_skip_taskbar_hint(GTK_WINDOW(app.window), TRUE);
    gtk_window_set_skip_pager_hint(GTK_WINDOW(app.window), TRUE);
    gtk_window_set_accept_focus(GTK_WINDOW(app.window), FALSE);
    gtk_window_set_type_hint(GTK_WINDOW(app.window), GDK_WINDOW_TYPE_HINT_UTILITY);
    gtk_window_stick(GTK_WINDOW(app.window));
    gtk_widget_set_app_paintable(app.window, TRUE);

    GdkScreen* screen = gtk_widget_get_screen(app.window);
    if (GdkVisual* visual = gdk_screen_get_rgba_visual(screen)) {
        gtk_widget_set_visual(app.window, visual);
    }

    app.drawArea = gtk_drawing_area_new();
    gtk_container_add(GTK_CONTAINER(app.window), app.drawArea);

    gtk_widget_add_events(app.window, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK);
    g_signal_connect(app.drawArea, "draw", G_CALLBACK(onDraw), nullptr);
    g_signal_connect(app.window, "button-press-event", G_CALLBACK(onButtonPress), nullptr);
    g_signal_connect(app.window, "motion-notify-event", G_CALLBACK(onMotionNotify), nullptr);
    g_signal_connect(app.window, "button-release-event", G_CALLBACK(onButtonRelease), nullptr);
    g_signal_connect(app.window, "destroy", G_CALLBACK(gtk_main_quit), nullptr);
    g_signal_connect(app.window, "realize", G_CALLBACK(+[](GtkWidget* w, gpointer) {
        updateInputShape(*g_app);
        if (GdkWindow* gw = gtk_widget_get_window(w)) {
            GdkCursor* hand = gdk_cursor_new_from_name(gdk_window_get_display(gw), "grab");
            if (hand) {
                gdk_window_set_cursor(gw, hand);
                g_object_unref(hand);
            }
        }
    }), nullptr);

    // System tray icon (works cleanly on 统信 UOS, Deepin, KDE, XFCE, MATE!)
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    if (GdkPixbuf* pb = createCatTrayPixbuf()) {
        app.trayIcon = gtk_status_icon_new_from_pixbuf(pb);
        updateTrayTooltip(app);
        g_signal_connect(app.trayIcon, "popup-menu", G_CALLBACK(+[](GtkStatusIcon*, guint, guint, gpointer) {
            showPopupMenu(*g_app, nullptr);
        }), nullptr);
        g_signal_connect(app.trayIcon, "activate", G_CALLBACK(+[](GtkStatusIcon*, gpointer) {
            showPopupMenu(*g_app, nullptr);
        }), nullptr);
        g_object_unref(pb);
    }
    G_GNUC_END_IGNORE_DEPRECATIONS

    applyWindowScaleAndPos(app, false);
    gtk_widget_show_all(app.window);

    app.lastTickTime = nowSeconds();
    g_timeout_add(16, onFrameTick, nullptr);

    gtk_main();
    app.input.stop();
    return 0;
}
