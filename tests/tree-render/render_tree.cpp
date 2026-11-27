// 圣诞树版离屏渲染测试（开发用，不参与打包）
// 原项目：KuroCat — Copyright (c) 2026 chanke17, MIT License
// 新增部分：Copyright (c) 2026 Allen Mai, MIT License
#define NOMINMAX
#include <windows.h>
#include <algorithm>
using std::min;
using std::max;
#include <gdiplus.h>
#include <string>
#include "../../windows/src/CatRenderer.hpp"

#pragma comment(lib, "gdiplus.lib")

static int GetEncoderClsid(const WCHAR* format, CLSID* pClsid) {
    UINT num = 0, size = 0;
    Gdiplus::GetImageEncodersSize(&num, &size);
    if (size == 0) return -1;
    auto* codecs = (Gdiplus::ImageCodecInfo*)malloc(size);
    Gdiplus::GetImageEncoders(num, size, codecs);
    for (UINT i = 0; i < num; ++i) {
        if (wcscmp(codecs[i].MimeType, format) == 0) { *pClsid = codecs[i].Clsid; free(codecs); return (int)i; }
    }
    free(codecs);
    return -1;
}

static void renderOne(const wchar_t* out, TreeTheme theme, float time, int pose) {
    Gdiplus::Bitmap bmp(720, 640, PixelFormat32bppARGB);
    Gdiplus::Graphics g(&bmp);
    g.Clear(Gdiplus::Color(255, 244, 247, 245));
    g.ScaleTransform(2.0f, 2.0f);

    CatPhysics physics;
    CatSettings settings;
    settings.treeTheme = theme;
    settings.scale = 1.0f;
    settings.whiteOutline = true;
    const SkinSpec& skin = builtInTreeSkin(theme);
    physics.time = time;
    if (pose == 1) {
        physics.treeFlash.value = 0.9f;
        for (int i = 0; i < 12; ++i) physics.spawnTreeStar(physics.treeCrownPoint(0.15f + 0.07f * i), 1.0f);
    } else if (pose == 2) {
        physics.treeFlash.value = 1.0f;
        for (int i = 0; i < 26; ++i) {
            Pt top = { 180.0f + (float)(i % 7 - 3) * 5.0f, 34.0f + (float)(i % 5) * 4.0f };
            physics.sparkles.push_back({ top, { (float)(i % 9 - 4) * 26.0f, -120.0f - (float)(i % 6) * 18.0f }, 0.35f, 1.2f, false });
        }
        for (int k = 0; k < 4; ++k) physics.gifts.push_back({ { 140.0f + 24.0f * k, 150.0f - 10.0f * k }, { 0, 0 }, -12.0f * k, 40.0f, 0.4f, 1.6f, 0.9f, k });
    }
    CatRenderer::draw(g, physics, settings, skin, KeyboardSkinSpec::builtInTheme(0));

    CLSID png; GetEncoderClsid(L"image/png", &png);
    bmp.Save(out, &png, nullptr);
}

static void renderStates() {
    struct Case { const wchar_t* file; int mode; };
    const Case cases[] = { { L"state_star.png", 0 }, { L"state_gift.png", 1 }, { L"state_fountain.png", 2 } };
    for (const Case& c : cases) {
        Gdiplus::Bitmap bmp(720, 640, PixelFormat32bppARGB);
        Gdiplus::Graphics g(&bmp);
        g.Clear(Gdiplus::Color(255, 244, 247, 245));
        g.ScaleTransform(2.0f, 2.0f);

        CatPhysics physics;
        CatSettings settings;
        settings.scale = 1.0f;
        physics.time = 2.0f;
        const SkinSpec& skin = builtInTreeSkin(TreeTheme::ClassicGreen);

        if (c.mode == 0) {
            // 单颗星：中等尺寸、位于树侧空中
            physics.sparkles.push_back({ { 250.0f, 150.0f }, { 0, 0 }, 0.42f, 1.0f, false });
        } else if (c.mode == 1) {
            // 单个礼物：四种款式横向排开，方便核对尺寸
            for (int k = 0; k < 4; ++k)
                physics.gifts.push_back({ { 82.0f + 66.0f * k, 150.0f }, { 0, 0 }, -14.0f + 9.0f * k, 0.0f,
                                           0.35f, 1.6f, 0.95f, k });
        } else {
            // 喷泉：模拟从中部向外喷出的峰值时刻
            for (int i = 0; i < 18; ++i) {
                float ang = -2.86f + (float)i / 18.0f * 2.58f;
                float dist = 60.0f + (float)(i % 5) * 16.0f;
                Pt pos = { 180.0f + std::cos(ang) * dist, 176.0f + std::sin(ang) * dist };
                physics.sparkles.push_back({ pos, { 0, 0 }, 0.35f + 0.02f * (float)(i % 4), 1.0f, false });
            }
            for (int k = 0; k < 3; ++k) {
                physics.gifts.push_back({ { 100.0f + 80.0f * k, 146.0f - 10.0f * k }, { 0, 0 },
                                           -18.0f + 18.0f * k, 30.0f, 0.42f, 1.6f, 0.9f, k });
            }
        }
        CatRenderer::draw(g, physics, settings, skin, KeyboardSkinSpec::builtInTheme(0));
        CLSID png; GetEncoderClsid(L"image/png", &png);
        bmp.Save(c.file, &png, nullptr);
    }
}

int main() {
    GdiplusStartupInput in;
    ULONG_PTR token = 0;
    GdiplusStartup(&token, &in, nullptr);
    renderOne(L"tree_classic.png", TreeTheme::ClassicGreen, 1.3f, 0);
    renderOne(L"tree_snow.png", TreeTheme::SnowBlue, 2.1f, 1);
    renderOne(L"tree_rose.png", TreeTheme::RoseGold, 0.7f, 0);
    renderOne(L"tree_neon_fountain.png", TreeTheme::MidnightNeon, 3.4f, 2);
    renderStates();

    // 逻辑自检：树形命中、点击弹星、连打喷泉
    CatPhysics ph;
    ph.setTreeMode(true);
    CatSettings st;
    int hitTree = TreeRenderer::hitTest({ 180.0f, 210.0f }) ? 1 : 0;
    int hitEmpty = TreeRenderer::hitTest({ 20.0f, 20.0f }) ? 1 : 0;
    int hitTrunk = TreeRenderer::hitTest({ 180.0f, 300.0f }) ? 1 : 0;
    ph.treeOnTap({ 180.0f, 220.0f });
    size_t tapStars = ph.sparkles.size();
    for (int i = 0; i < 16; ++i) ph.treeOnKey(st);
    printf("hitTree=%d hitTrunk=%d hitEmpty=%d tapStars=%zu stars=%zu gifts=%zu fountain=%.2f\n",
           hitTree, hitTrunk, hitEmpty, tapStars, ph.sparkles.size(), ph.gifts.size(), ph.treeFountainTime);
    GdiplusShutdown(token);
    return 0;
}
