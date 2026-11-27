#pragma once
// KuroCat 圣诞树版（Christmas Tree edition）
// 原项目：KuroCat — Copyright (c) 2026 chanke17, MIT License（见仓库根目录 LICENSE）
// 新增/修改部分：Copyright (c) 2026 Allen Mai, MIT License（沿用原仓库协议）
//
// 本文件是「圣诞树」角色的全部绘制逻辑（造型参考用户提供的插画）：
//   - 树体：5 层下垂式冷杉枝条，深色描边 + 暖绿渐变 + 针叶碎笔，外侧尖梢翻卷
//   - 奶白色绒球彩带两段斜挎、大颗高光装饰球、红色小蝴蝶结、金色碎闪
//   - 树顶八角细射线星 + 棕色底座
//   - 底部三只礼物盒（绿配金、米白配红、橙点配红），双环蝴蝶结带垂带
//   - 打字/点击弹出的四角凹边闪光星（CatPhysics::sparkles，只向上飞）
//   - 随机礼物（礼物盒 / 手机 / 游戏机 / 笔记本电脑，CatPhysics::gifts）
// 坐标系统一使用 360x320 画布（y 轴向下），缩放/旋转/翻转由外层 Graphics 变换处理。
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <cmath>
#include <vector>
#include <algorithm>
#include "CatPhysics.hpp"
#include "../../shared/SkinSpec.hpp"

using namespace Gdiplus;   // 本文件全部使用 GDI+ 绘制

// ---------------------------------------------------------------------------
// 配色：从 SkinSpec.palette 映射到树体各部位，保证「换树皮肤」和「换猫皮肤」一样简单
//   body       → 树冠主色          bodyShade → 树冠暗部
//   belly      → 树冠高光（针叶提亮）
//   legs       → 树干 / 底座       paws      → 树干暗部
//   points     → 装饰球主色        earOuter  → 装饰球副色
//   earInner   → 装饰球第三色      nose      → 蝴蝶结 / 缎带
//   stripes    → 彩带 / 星星点缀   tail      → 彩带主色
//   tailTip    → 高光 / 雪色        iris      → 树顶星（可被「星星颜色」覆盖）
// ---------------------------------------------------------------------------
struct TreeLook {
    Gdiplus::Color foliageLight, foliageMid, foliageDark, outline;
    Gdiplus::Color trunk, trunkShade;
    Gdiplus::Color ribbons[3];
    Gdiplus::Color ornaments[4];
    Gdiplus::Color star, garland, snow;
};

inline Gdiplus::Color treeColorOf(const SkinColor& c, Gdiplus::Color fallback) {
    if (!c.set) return fallback;
    auto b = [](double v) { return (BYTE)std::lround(std::clamp(v, 0.0, 1.0) * 255.0); };
    return Gdiplus::Color(b(c.a), b(c.r), b(c.g), b(c.b));
}

inline Gdiplus::Color treeMix(Gdiplus::Color a, Gdiplus::Color b, float t) {
    t = std::clamp(t, 0.0f, 1.0f);
    return Gdiplus::Color(255,
        (BYTE)std::lround(a.GetR() + (b.GetR() - a.GetR()) * t),
        (BYTE)std::lround(a.GetG() + (b.GetG() - a.GetG()) * t),
        (BYTE)std::lround(a.GetB() + (b.GetB() - a.GetB()) * t));
}

inline Gdiplus::Color treeShade(Gdiplus::Color c, float k) {
    auto f = [&](BYTE v) { return (BYTE)std::clamp((int)std::lround(v * k), 0, 255); };
    return Gdiplus::Color(c.GetA(), f(c.GetR()), f(c.GetG()), f(c.GetB()));
}

inline Gdiplus::Color treeWithAlpha(Gdiplus::Color c, BYTE a) {
    return Gdiplus::Color(a, c.GetR(), c.GetG(), c.GetB());
}

// 四款内置圣诞树配色（用户新增）。第一套按参考图的暖绿调校。
inline const SkinSpec& builtInTreeSkin(TreeTheme theme) {
    static const std::vector<SkinSpec> trees = [] {
        auto hx = [](unsigned int rgb) { return SkinColor::hex(rgb); };
        std::vector<SkinSpec> v(4);

        SkinSpec& g = v[0];
        g.id = "tree:0"; g.name = "经典圣诞绿"; g.builtIn = true; g.renderStyle = SkinRenderStyle::Tree;
        g.palette.body = hx(0x4A8A3C); g.palette.belly = hx(0x7FB84A); g.palette.bodyShade = hx(0x2E6430);
        g.palette.legs = hx(0x8A5A2B); g.palette.paws = hx(0x5E3A18);
        g.palette.points = hx(0xD9452F); g.palette.earOuter = hx(0xE9B44C); g.palette.earInner = hx(0xEDE6D6);
        g.palette.nose = hx(0xC8402F); g.palette.stripes = hx(0xE9C05A);
        g.palette.tail = hx(0xFBF3E2); g.palette.tailTip = hx(0xFFFBF2);
        g.palette.iris = hx(0xF0A03C);

        SkinSpec& s = v[1];
        s.id = "tree:1"; s.name = "雪夜蓝"; s.builtIn = true; s.renderStyle = SkinRenderStyle::Tree;
        s.palette.body = hx(0x2A5C55); s.palette.belly = hx(0x4E8C7C); s.palette.bodyShade = hx(0x173B39);
        s.palette.legs = hx(0x5A4433); s.palette.paws = hx(0x3A2A1E);
        s.palette.points = hx(0xBFD9E8); s.palette.earOuter = hx(0x8FB8D6); s.palette.earInner = hx(0xF2F6FA);
        s.palette.nose = hx(0x6FA8C8); s.palette.stripes = hx(0xCFE6F2);
        s.palette.tail = hx(0xF4FAFF); s.palette.tailTip = hx(0xFFFFFF);
        s.palette.iris = hx(0xBFE9FF);

        SkinSpec& p = v[2];
        p.id = "tree:2"; p.name = "粉金铃铛"; p.builtIn = true; p.renderStyle = SkinRenderStyle::Tree;
        p.palette.body = hx(0x3C6B4A); p.palette.belly = hx(0x6FA06A); p.palette.bodyShade = hx(0x284A33);
        p.palette.legs = hx(0x8A6236); p.palette.paws = hx(0x5E3F1E);
        p.palette.points = hx(0xE8A0B4); p.palette.earOuter = hx(0xE7C877); p.palette.earInner = hx(0xFFD1DC);
        p.palette.nose = hx(0xD98A9C); p.palette.stripes = hx(0xF6D77A);
        p.palette.tail = hx(0xFFF3E4); p.palette.tailTip = hx(0xFFFFFF);
        p.palette.iris = hx(0xF6D77A);

        SkinSpec& n = v[3];
        n.id = "tree:3"; n.name = "暗夜霓虹"; n.builtIn = true; n.renderStyle = SkinRenderStyle::Tree;
        n.palette.body = hx(0x1E4438); n.palette.belly = hx(0x2F6B52); n.palette.bodyShade = hx(0x0E241E);
        n.palette.legs = hx(0x3A2F2A); n.palette.paws = hx(0x241C18);
        n.palette.points = hx(0xFF3FA4); n.palette.earOuter = hx(0x4CF2D0); n.palette.earInner = hx(0x8CFF3F);
        n.palette.nose = hx(0xFF3FA4); n.palette.stripes = hx(0x4CF2D0);
        n.palette.tail = hx(0xEAF6E8); n.palette.tailTip = hx(0xF2FFF0);
        n.palette.iris = hx(0xE6FF57);
        return v;
    }();
    int i = std::clamp((int)theme, 0, (int)trees.size() - 1);
    return trees[(size_t)i];
}

inline TreeLook treeLookFor(const SkinSpec& skin, EyeColorTheme eye, bool overrideIris) {
    const SkinPalette& p = skin.palette;
    TreeLook l{};
    Gdiplus::Color base = treeColorOf(p.body, Gdiplus::Color(255, 0x4A, 0x8A, 0x3C));
    l.foliageMid = base;
    l.foliageLight = treeColorOf(p.belly, treeMix(base, Gdiplus::Color(255, 0xFF, 0xF2, 0xC0), 0.25f));
    l.foliageDark = treeColorOf(p.bodyShade, treeShade(base, 0.62f));
    // 描边：暗绿偏褐，参考图是深色线稿而不是白边
    l.outline = treeMix(treeShade(base, 0.40f), Gdiplus::Color(255, 0x2A, 0x1E, 0x10), 0.42f);

    l.trunk = treeColorOf(p.legs, Gdiplus::Color(255, 0x8A, 0x5A, 0x2B));
    l.trunkShade = treeColorOf(p.paws, treeShade(l.trunk, 0.70f));

    Gdiplus::Color bow = treeColorOf(p.nose, Gdiplus::Color(255, 0xC8, 0x40, 0x2F));
    l.ribbons[0] = bow;
    l.ribbons[1] = treeColorOf(p.stripes, Gdiplus::Color(255, 0xE9, 0xC0, 0x5A));
    l.ribbons[2] = treeColorOf(p.earOuter, Gdiplus::Color(255, 0xE9, 0xB4, 0x4C));

    l.ornaments[0] = treeColorOf(p.points, Gdiplus::Color(255, 0xD9, 0x45, 0x2F));
    l.ornaments[1] = treeColorOf(p.earOuter, Gdiplus::Color(255, 0xE9, 0xB4, 0x4C));
    l.ornaments[2] = treeColorOf(p.earInner, Gdiplus::Color(255, 0xED, 0xE6, 0xD6));
    l.ornaments[3] = treeMix(l.ornaments[0], l.ornaments[1], 0.5f);

    l.garland = treeColorOf(p.tail, Gdiplus::Color(255, 0xFB, 0xF3, 0xE2));
    l.snow = treeColorOf(p.tailTip, Gdiplus::Color(255, 0xFF, 0xF8, 0xEC));
    l.star = treeColorOf(p.iris, Gdiplus::Color(255, 0xF0, 0xA0, 0x3C));
    if (overrideIris || !p.iris.set) {
        static const unsigned int eyeRgb[7] = { 0xD4FF3F, 0x7FD8FF, 0xFFB74D, 0x6FE3FF, 0xFFC46B, 0xB8C98A, 0xD4B24A };
        unsigned int rgb = eyeRgb[std::clamp((int)eye, 0, 6)];
        l.star = Gdiplus::Color(255, (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255);
    }
    return l;
}

class TreeRenderer {
public:
    // 五层枝条几何（apex 顶点 / base 底边 / 半宽），比例参考插画：高宽比约 1.25~1.3
    static constexpr int TierCount = 5;
    static constexpr float ApexY[TierCount] = { 50.0f, 82.0f, 116.0f, 152.0f, 196.0f };
    static constexpr float BaseY[TierCount] = { 102.0f, 138.0f, 176.0f, 218.0f, 266.0f };
    static constexpr float HalfW[TierCount] = { 38.0f, 52.0f, 66.0f, 81.0f, 96.0f };
    // 每层轻微左右错位，避免完全对称的“机器感”
    static constexpr float TierShift[TierCount] = { 1.5f, -2.5f, 2.0f, -2.0f, 0.0f };
    static constexpr float CenterX = 180.0f;
    static constexpr float GroundY = 300.0f;
    static constexpr float StarY = 26.0f;
    static constexpr float StarR = 17.5f;

    // 树形命中：枝条三角 + 树顶星 + 底部礼物，空白处仍穿透桌面
    static bool hitTest(Pt p) {
        if (std::hypot(p.x - CenterX, p.y - StarY) <= StarR + 2.0f) return true;
        for (int i = 0; i < TierCount; ++i) {
            if (p.y < ApexY[i] || p.y > BaseY[i] + 12.0f) continue;
            float u = std::clamp((p.y - ApexY[i]) / (BaseY[i] - ApexY[i]), 0.0f, 1.0f);
            if (std::fabs(p.x - CenterX) <= HalfW[i] * u + 7.0f) return true;
        }
        if (p.y >= 276.0f && p.y <= 316.0f && std::fabs(p.x - CenterX) <= 90.0f) return true;
        return false;
    }

    static void draw(Graphics& g, const CatPhysics& physics, const CatSettings& settings, const SkinSpec& skin) {
        TreeLook look = treeLookFor(skin, settings.eyeTheme, settings.overrideSkinIris);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        g.SetPixelOffsetMode(PixelOffsetModeHighQuality);

        float breathe = std::sin(physics.time * 1.5f) * 0.9f;
        float squash = std::clamp(physics.treeSquash.value, 0.90f, 1.10f);
        float lean = std::clamp(physics.treeLean.value, -0.055f, 0.055f);

        GraphicsState st = g.Save();
        g.TranslateTransform(CenterX, BaseY[TierCount - 1] + 14.0f);
        g.RotateTransform(lean * 57.29578f);
        g.ScaleTransform(1.0f, squash);
        g.TranslateTransform(-CenterX, -(BaseY[TierCount - 1] + 14.0f) + breathe);

        drawGroundShadow(g, look);
        drawTreeBackdrop(g, look);
        for (int i = TierCount - 1; i >= 0; --i) drawTier(g, i, look);
        drawGarland(g, physics, look);
        drawOrnaments(g, physics, look);
        drawTopperStar(g, physics, look);
        drawBaseGifts(g, look);
        g.Restore(st);

        drawParticles(g, physics, look);
    }

private:
    // ---------------------------------------------------------------- 基础工具
    static void addRoundedRect(GraphicsPath& path, RectF r, float radius) {
        float d = radius * 2.0f;
        if (d > std::min(r.Width, r.Height)) d = std::min(r.Width, r.Height);
        if (d <= 0.1f) { path.AddRectangle(r); return; }
        path.AddArc(r.X, r.Y, d, d, 180.0f, 90.0f);
        path.AddArc(r.GetRight() - d, r.Y, d, d, 270.0f, 90.0f);
        path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0.0f, 90.0f);
        path.AddArc(r.X, r.GetBottom() - d, d, d, 90.0f, 90.0f);
        path.CloseFigure();
    }

    static void drawGroundShadow(Graphics& g, const TreeLook& look) {
        SolidBrush soft(Color(40, 0, 0, 0));
        g.FillEllipse(&soft, RectF(66.0f, GroundY - 6.0f, 228.0f, 18.0f));
        SolidBrush dark(Color(30, 0, 0, 0));
        g.FillEllipse(&dark, RectF(104.0f, GroundY - 1.0f, 152.0f, 10.0f));
        (void)look;
    }

    // ---------------------------------------------------------------- 枝条
    // 单层枝条轮廓：两侧内收的下垂弧线 + 外端尖梢 + 下沿 5 个宽尖瓣（插画式冷杉）
    static void buildTierPath(GraphicsPath& path, int i) {
        float ay = ApexY[i], by = BaseY[i], hw = HalfW[i];
        float cx = CenterX + TierShift[i];
        float mid = ay + (by - ay) * 0.50f;
        (void)mid;
        const float tipDrop = 9.0f + (float)i * 0.8f;

        path.StartFigure();
        // 右侧：从顶点向右下扫，中段明显内收，末端下垂
        path.AddBezier(PointF(cx, ay),
                       PointF(cx + hw * 0.30f, ay + (by - ay) * 0.30f),
                       PointF(cx + hw * 0.58f, by - 26.0f),
                       PointF(cx + hw * 0.86f, by - 13.0f));
        // 右端尖梢：向外并微微下垂，收成尖角（不做回卷，避免描边糊成一团）
        path.AddBezier(PointF(cx + hw * 0.86f, by - 13.0f),
                       PointF(cx + hw + 6.0f, by - 4.0f),
                       PointF(cx + hw + 12.0f, by + 2.0f),
                       PointF(cx + hw + 13.0f, by + 5.0f));

        // 下沿宽尖瓣（右 → 左）
        const int lobes = 6;
        float xStart = cx + hw + 13.0f;
        float xEnd = cx - hw - 13.0f;
        for (int j = 0; j < lobes; ++j) {
            float xa = xStart + (xEnd - xStart) * (float)j / (float)lobes;
            float xb = xStart + (xEnd - xStart) * (float)(j + 1) / (float)lobes;
            float xm = (xa + xb) * 0.5f;
            float dip = by + tipDrop + (float)(j % 2) * 2.0f;
            path.AddBezier(PointF(xa, by + 5.0f),
                           PointF(xa + (xm - xa) * 0.55f, dip - 1.0f),
                           PointF(xm - (xm - xa) * 0.22f, dip),
                           PointF(xm, dip));
            path.AddBezier(PointF(xm, dip),
                           PointF(xm + (xb - xm) * 0.22f, dip),
                           PointF(xb - (xb - xm) * 0.55f, dip - 1.0f),
                           PointF(xb, by + 5.0f));
        }

        // 左端尖梢
        path.AddBezier(PointF(cx - hw - 13.0f, by + 5.0f),
                       PointF(cx - hw - 12.0f, by + 2.0f),
                       PointF(cx - hw - 6.0f, by - 4.0f),
                       PointF(cx - hw * 0.86f, by - 13.0f));
        path.AddBezier(PointF(cx - hw * 0.86f, by - 13.0f),
                       PointF(cx - hw * 0.58f, by - 26.0f),
                       PointF(cx - hw * 0.30f, ay + (by - ay) * 0.30f),
                       PointF(cx, ay));
        path.CloseFigure();
    }

    // 整棵树的底层剪影：填满各层枝条之间的凹口，避免透出背景，
    // 同时充当“内部枝丛”的暗部（参考图整棵树是密实的，没有白色缝隙）
    static void drawTreeBackdrop(Graphics& g, const TreeLook& look) {
        GraphicsPath path;
        const float topY = 44.0f;
        const float botY = 268.0f;
        const float wTop = 6.0f;
        const float wBot = 95.0f;
        path.StartFigure();
        path.AddBezier(PointF(CenterX, topY),
                       PointF(CenterX + 26.0f, 110.0f),
                       PointF(CenterX + 74.0f, 208.0f),
                       PointF(CenterX + wBot, botY - 6.0f));
        const int lobes = 8;
        for (int j = 0; j < lobes; ++j) {
            float xa = CenterX + wBot + (float)j * (-2.0f * wBot / lobes);
            float xb = CenterX + wBot + (float)(j + 1) * (-2.0f * wBot / lobes);
            float xm = (xa + xb) * 0.5f;
            path.AddBezier(PointF(xa, botY - 4.0f), PointF(xa + (xm - xa) * 0.5f, botY + 14.0f),
                           PointF(xm - (xm - xa) * 0.2f, botY + 12.0f), PointF(xm, botY + 8.0f));
            path.AddBezier(PointF(xm, botY + 8.0f), PointF(xm + (xb - xm) * 0.2f, botY + 12.0f),
                           PointF(xb - (xb - xm) * 0.5f, botY + 14.0f), PointF(xb, botY - 4.0f));
        }
        path.AddBezier(PointF(CenterX - wBot, botY - 6.0f),
                       PointF(CenterX - 74.0f, 208.0f),
                       PointF(CenterX - 26.0f, 110.0f),
                       PointF(CenterX, topY));
        path.CloseFigure();

        Gdiplus::Color deep = treeMix(look.foliageDark, look.outline, 0.22f);
        SolidBrush fill(deep);
        g.FillPath(&fill, &path);
        Pen edge(treeWithAlpha(look.outline, 210), 1.6f);
        edge.SetLineJoin(LineJoinRound);
        g.DrawPath(&edge, &path);
        (void)wTop;

        // 内部枝丛：几道竖直暗笔（裁剪在剪影内，避免线条跑到树外）
        GraphicsState clipState = g.Save();
        g.SetClip(&path);
        Pen inner(treeWithAlpha(look.outline, 55), 1.4f);
        inner.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
        for (int k = 0; k < 5; ++k) {
            float x = CenterX + ((float)k - 2.0f) * 26.0f;
            g.DrawLine(&inner, PointF(x, 96.0f + (float)(k % 2) * 22.0f), PointF(x * 0.98f + CenterX * 0.02f, 250.0f));
        }
        g.Restore(clipState);
    }

    static void drawNeedles(Graphics& g, int i, const TreeLook& look) {
        float ay = ApexY[i], by = BaseY[i], hw = HalfW[i];
        float cx = CenterX + TierShift[i];
        Pen light(treeWithAlpha(look.foliageLight, 200), 1.4f);
        light.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
        Pen dark(treeWithAlpha(look.foliageDark, 150), 1.3f);
        dark.SetLineCap(LineCapRound, LineCapRound, DashCapRound);

        // 下沿针叶：短促、朝下，压在轮廓内侧，不甩到树形之外
        const int tufts = 8;
        for (int k = 0; k < tufts; ++k) {
            float t = (float)k / (float)(tufts - 1);
            float x = cx + (t * 2.0f - 1.0f) * (hw - 4.0f);
            float y = by + 1.0f + std::sin(t * 3.14159f) * 4.0f;
            float len = 4.0f + (k % 3) * 1.6f;
            float lean = (t - 0.5f) * 3.0f;
            g.DrawBezier(&light, PointF(x, y - len), PointF(x + lean * 0.4f, y - len * 0.45f),
                         PointF(x + lean * 0.8f, y - len * 0.20f), PointF(x + lean, y));
        }
        // 层内高光：两道贴合树形的浅色弧线
        for (int k = 0; k < 2; ++k) {
            float u = 0.30f + 0.22f * (float)k;
            float y = ay + (by - ay) * u;
            float w = hw * u * 0.92f;
            g.DrawBezier(&light, PointF(cx - w * 0.72f, y + 3.0f),
                         PointF(cx - w * 0.36f, y - 2.0f),
                         PointF(cx + w * 0.10f, y - 2.0f),
                         PointF(cx + w * 0.42f, y + 2.0f));
        }
        // 层内暗部：靠近右侧的一小段压暗，增加体积感
        g.DrawBezier(&dark, PointF(cx + hw * 0.42f, ay + (by - ay) * 0.60f),
                     PointF(cx + hw * 0.70f, ay + (by - ay) * 0.72f),
                     PointF(cx + hw * 0.82f, ay + (by - ay) * 0.82f),
                     PointF(cx + hw * 0.88f, ay + (by - ay) * 0.94f));
        // 枝条分层线：一道横向暗弧，让每层内部也有“枝丛”感
        Pen branch(treeWithAlpha(look.foliageDark, 70), 1.6f);
        branch.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
        for (int b = 0; b < 2; ++b) {
            float u = 0.46f + 0.20f * (float)b;
            float y = ay + (by - ay) * u;
            float w = hw * u * 0.94f;
            g.DrawBezier(&branch, PointF(cx - w, y + 2.0f), PointF(cx - w * 0.35f, y - 3.0f),
                         PointF(cx + w * 0.35f, y - 3.0f), PointF(cx + w, y + 2.0f));
        }
        // 外侧尖梢的小卷须（参考图每层端点都有细细的卷曲枝条）
        Pen curl(treeWithAlpha(look.foliageLight, 210), 1.3f);
        curl.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
        for (int side = -1; side <= 1; side += 2) {
            float x = cx + side * (hw + 12.0f);
            float y = by + 3.0f;
            g.DrawBezier(&curl, PointF(x, y),
                         PointF(x + side * 7.0f, y - 6.0f),
                         PointF(x + side * 12.0f, y - 12.0f),
                         PointF(x + side * 6.0f, y - 14.0f));
        }
    }

    static void drawTier(Graphics& g, int i, const TreeLook& look) {
        float ay = ApexY[i], by = BaseY[i], hw = HalfW[i];
        GraphicsPath path;
        buildTierPath(path, i);

        // 下层枝条的投影（让层次分开）
        GraphicsState s1 = g.Save();
        g.TranslateTransform(0.0f, 7.0f);
        SolidBrush shadow(Color(48, 20, 30, 12));
        g.FillPath(&shadow, &path);
        g.Restore(s1);

        Gdiplus::Color top = treeMix(look.foliageMid, look.foliageLight,
                                     0.30f + 0.06f * (float)(TierCount - 1 - i));
        Gdiplus::Color bottom = treeMix(look.foliageMid, look.foliageDark, 0.55f);
        LinearGradientBrush br(RectF(CenterX - hw - 18.0f, ay, (hw + 18.0f) * 2.0f, by - ay + 24.0f),
                               top, bottom, LinearGradientModeVertical);
        g.FillPath(&br, &path);

        // 底部暗部（同一轮廓下移后裁剪到本层内，靠半透明叠出厚度）
        GraphicsState s2 = g.Save();
        g.SetClip(&path);
        SolidBrush deep(treeWithAlpha(look.foliageDark, 120));
        g.FillRectangle(&deep, RectF(CenterX - hw - 20.0f, by - 16.0f, (hw + 20.0f) * 2.0f, 40.0f));
        g.Restore(s2);

        Pen outline(look.outline, 2.0f);
        outline.SetLineJoin(LineJoinRound);
        g.DrawPath(&outline, &path);
        drawNeedles(g, i, look);
        drawBranchlets(g, i, look);
    }

    // 枝梢碎枝：沿每层下沿和两侧伸出的小三角枝，打散几何感（参考图的毛边）
    static void drawBranchlets(Graphics& g, int i, const TreeLook& look) {
        float ay = ApexY[i], by = BaseY[i], hw = HalfW[i];
        float cx = CenterX + TierShift[i];
        Pen edge(treeWithAlpha(look.outline, 190), 1.0f);
        edge.SetLineJoin(LineJoinRound);
        SolidBrush light(look.foliageLight);
        SolidBrush mid(look.foliageMid);
        SolidBrush dark(look.foliageDark);

        // 下沿 11 根长一点的枝梢，明暗交替，打散轮廓的几何感
        for (int k = 0; k < 11; ++k) {
            float t = ((float)k + 0.5f) / 11.0f;
            float x = cx + (t * 2.0f - 1.0f) * (hw + 9.0f);
            float y = by + 3.0f + std::sin(t * 3.14159f) * 5.0f;
            float len = 9.0f + 5.0f * (0.5f + 0.5f * std::sin((float)k * 2.7f + (float)i));
            float drift = ((float)k - 5.0f) * 1.1f;
            PointF pts[3] = {
                PointF(x - 2.8f, y - 1.0f),
                PointF(x + 2.8f, y - 1.0f),
                PointF(x + drift, y + len)
            };
            SolidBrush& brush = (k % 3 == 0) ? dark : ((k % 3 == 1) ? mid : light);
            g.FillPolygon(&brush, pts, 3);
            g.DrawPolygon(&edge, pts, 3);
        }
        // 两侧各 3 根横向小枝
        for (int side = -1; side <= 1; side += 2) {
            for (int k = 0; k < 3; ++k) {
                float u = 0.38f + 0.20f * (float)k;
                float y = ay + (by - ay) * u;
                float x = cx + side * (hw * u);
                float len = 10.0f + 3.5f * (float)k;
                PointF pts[3] = {
                    PointF(x, y - 2.6f),
                    PointF(x, y + 2.6f),
                    PointF(x + side * len, y + 4.0f)
                };
                g.FillPolygon((k % 2 == 0) ? &mid : &light, pts, 3);
                g.DrawPolygon(&edge, pts, 3);
            }
        }
    }

    // ---------------------------------------------------------------- 奶白绒球彩带
    static void drawGarlandSwag(Graphics& g, const TreeLook& look, PointF a, PointF c, PointF b, float thickness) {
        const int steps = 64;
        PointF prev = a;
        for (int s = 0; s <= steps; ++s) {
            float t = (float)s / (float)steps;
            float mt = 1.0f - t;
            PointF p(mt * mt * a.X + 2.0f * mt * t * c.X + t * t * b.X,
                     mt * mt * a.Y + 2.0f * mt * t * c.Y + t * t * b.Y);
            // 绒球串：相邻小球重叠，连成一条蓬松的奶白彩带
            float r = thickness * (0.80f + 0.22f * std::sin(t * 27.0f));
            SolidBrush shadow(treeWithAlpha(treeShade(look.garland, 0.72f), 80));
            g.FillEllipse(&shadow, RectF(p.X - r, p.Y - r + 1.4f, r * 2.0f, r * 2.0f));
            SolidBrush ball(look.garland);
            g.FillEllipse(&ball, RectF(p.X - r, p.Y - r, r * 2.0f, r * 2.0f));
            SolidBrush hi(Color(165, 255, 255, 255));
            g.FillEllipse(&hi, RectF(p.X - r * 0.50f, p.Y - r * 0.58f, r * 0.62f, r * 0.62f));
            prev = p;
        }
        (void)prev;
    }

    static void drawGarland(Graphics& g, const CatPhysics& physics, const TreeLook& look) {
        float sway = std::sin(physics.time * 1.3f) * 1.2f;
        // 两道斜挎彩带，走向参考插画：左低右高，整体收在树形内部
        drawGarlandSwag(g, look, PointF(CenterX - 72.0f, 232.0f + sway),
                        PointF(CenterX - 4.0f, 252.0f + sway), PointF(CenterX + 54.0f, 192.0f + sway), 5.0f);
        drawGarlandSwag(g, look, PointF(CenterX - 44.0f, 168.0f + sway * 0.8f),
                        PointF(CenterX + 4.0f, 184.0f + sway * 0.8f), PointF(CenterX + 38.0f, 142.0f + sway * 0.8f), 4.2f);
    }

    // ---------------------------------------------------------------- 装饰球 / 蝴蝶结
    static void drawBauble(Graphics& g, float x, float y, float r, Gdiplus::Color color, const TreeLook& look) {
        Pen string(treeWithAlpha(look.outline, 190), 1.2f);
        g.DrawLine(&string, PointF(x, y - r - 8.0f), PointF(x, y - r - 0.5f));
        SolidBrush cap(look.trunk);
        g.FillRectangle(&cap, RectF(x - 1.6f, y - r - 2.6f, 3.2f, 3.2f));

        SolidBrush body(color);
        g.FillEllipse(&body, RectF(x - r, y - r, r * 2.0f, r * 2.0f));
        Pen rim(treeShade(color, 0.62f), 1.5f);
        g.DrawEllipse(&rim, RectF(x - r, y - r, r * 2.0f, r * 2.0f));
        // 高光：上左月牙 + 小亮点
        SolidBrush gloss(Color(150, 255, 255, 255));
        g.FillEllipse(&gloss, RectF(x - r * 0.66f, y - r * 0.72f, r * 0.78f, r * 0.58f));
        SolidBrush pin(Color(235, 255, 255, 255));
        g.FillEllipse(&pin, RectF(x + r * 0.18f, y + r * 0.12f, r * 0.26f, r * 0.26f));
    }

    static void drawBow(Graphics& g, float cx, float cy, float size, Gdiplus::Color color, const TreeLook& look) {
        SolidBrush fill(color);
        Pen edge(treeShade(color, 0.55f), 1.0f);
        // 两个近似三角形的环（小尺寸下比椭圆更清楚）
        for (int side = -1; side <= 1; side += 2) {
            PointF pts[3] = {
                PointF(cx + side * size * 0.10f, cy - size * 0.06f),
                PointF(cx + side * size * 0.62f, cy - size * 0.34f),
                PointF(cx + side * size * 0.58f, cy + size * 0.30f)
            };
            g.FillPolygon(&fill, pts, 3);
            g.DrawPolygon(&edge, pts, 3);
        }
        // 两条短垂带
        for (int side = -1; side <= 1; side += 2) {
            PointF tail[3] = {
                PointF(cx + side * size * 0.05f, cy + size * 0.04f),
                PointF(cx + side * size * 0.30f, cy + size * 0.60f),
                PointF(cx + side * size * 0.14f, cy + size * 0.62f)
            };
            g.FillPolygon(&fill, tail, 3);
            g.DrawPolygon(&edge, tail, 3);
        }
        // 结
        SolidBrush knot(treeShade(color, 0.84f));
        g.FillEllipse(&knot, RectF(cx - size * 0.14f, cy - size * 0.14f, size * 0.28f, size * 0.28f));
        Pen knotEdge(look.outline, 0.8f);
        g.DrawEllipse(&knotEdge, RectF(cx - size * 0.14f, cy - size * 0.14f, size * 0.28f, size * 0.28f));
    }

    static void drawOrnaments(Graphics& g, const CatPhysics& physics, const TreeLook& look) {
        // 圆形装饰球：按层疏密分布（越靠下越多），位置/大小用确定性伪随机打散，
        // 避免等距成排；每帧保持一致，不会闪烁。
        auto hash = [](int k) {
            float v = std::sin((float)k * 12.9898f + 4.1414f) * 43758.5453f;
            return v - std::floor(v);
        };
        float sway = std::sin(physics.time * 1.7f) * 0.9f;
        static const int tierCounts[TierCount] = { 2, 4, 6, 9, 12 };   // 顶层少、底层多，共 33 颗
        int seed = 7;
        for (int i = TierCount - 1; i >= 0; --i) {
            int count = tierCounts[i];
            for (int k = 0; k < count; ++k) {
                float h1 = hash(seed++), h2 = hash(seed++), h3 = hash(seed++), h4 = hash(seed++);
                float u = 0.30f + 0.64f * h1;                     // 落在枝身而不是枝梢
                float sideSign = (h2 < 0.5f) ? -1.0f : 1.0f;      // 左右各半
                float sideMag = 0.28f + 0.66f * h3;               // 偏外侧，避免挤在中轴
                float y = ApexY[i] + (BaseY[i] - ApexY[i]) * u;
                float halfW = HalfW[i] * ((y - ApexY[i]) / (BaseY[i] - ApexY[i]));
                float x = CenterX + TierShift[i] + halfW * sideSign * sideMag + (h4 - 0.5f) * 3.0f;
                float tierScale = 0.62f + 0.38f * ((float)i / (float)(TierCount - 1));  // 越靠下越大颗
                float r = (3.4f + 4.2f * h4) * tierScale;
                Gdiplus::Color c = look.ornaments[(int)(h4 * 3.999f) % 4];
                drawBauble(g, x, y, r, c, look);
            }
        }
        // 小红蝴蝶结，散布在枝条间
        struct BowSpot { int tier; float u; float side; float size; };
        static const BowSpot bows[] = {
            { 4, 0.44f, -0.34f, 7.6f }, { 4, 0.64f, 0.46f, 7.0f },
            { 3, 0.38f,  0.26f, 7.2f }, { 3, 0.62f, -0.54f, 6.4f },
            { 2, 0.52f,  0.58f, 5.8f }
        };
        for (const BowSpot& b : bows) {
            int i = b.tier;
            float y = ApexY[i] + (BaseY[i] - ApexY[i]) * b.u;
            float halfW = HalfW[i] * ((y - ApexY[i]) / (BaseY[i] - ApexY[i]));
            drawBow(g, CenterX + TierShift[i] + halfW * b.side + sway * 0.5f, y, b.size, look.ribbons[0], look);
        }
        // 金色碎闪
        static const float specks[][2] = {
            { 96.0f, 210.0f }, { 268.0f, 196.0f }, { 118.0f, 148.0f },
            { 250.0f, 132.0f }, { 208.0f, 84.0f }, { 140.0f, 96.0f }, { 292.0f, 240.0f }
        };
        for (int k = 0; k < 7; ++k) {
            float tw = 0.55f + 0.45f * std::sin(physics.time * 2.2f + (float)k * 1.7f);
            drawSparkle(g, specks[k][0], specks[k][1], 2.6f + tw * 1.4f,
                        treeWithAlpha(look.ribbons[1], (BYTE)(90 + 130 * tw)), false);
        }
    }

    // ---------------------------------------------------------------- 树顶八角星 + 底座
    static void drawTopperStar(Graphics& g, const CatPhysics& physics, const TreeLook& look) {
        float pulse = 1.0f + std::sin(physics.time * 2.2f) * 0.035f;
        float R = StarR * pulse;

        // 底座（棕色小托）
        GraphicsPath base;
        addRoundedRect(base, RectF(CenterX - 5.0f, StarY + 12.0f, 10.0f, 13.0f), 2.2f);
        SolidBrush baseFill(look.trunk);
        g.FillPath(&baseFill, &base);
        Pen baseEdge(look.outline, 1.5f);
        g.DrawPath(&baseEdge, &base);

        // 八角射线星（8 个细长尖 + 8 个内凹谷）
        PointF pts[16];
        for (int k = 0; k < 16; ++k) {
            float ang = -3.14159f * 0.5f + (float)k * 3.14159f / 8.0f;
            float r = (k % 2 == 0) ? R : R * 0.38f;   // 八角星：内谷 0.38R，星体更饱满
            pts[k] = PointF(CenterX + std::cos(ang) * r, StarY + std::sin(ang) * r);
        }
        // 光晕（很淡，只做呼吸感）
        for (int i = 2; i >= 1; --i) {
            SolidBrush halo(treeWithAlpha(look.star, (BYTE)(6 + i * 3)));
            float rr = R * (1.10f + 0.14f * (float)i);
            g.FillEllipse(&halo, RectF(CenterX - rr, StarY - rr, rr * 2.0f, rr * 2.0f));
        }
        SolidBrush fill(treeMix(look.star, Gdiplus::Color(255, 244, 150, 60), 0.45f));
        g.FillPolygon(&fill, pts, 16);
        Pen edge(Gdiplus::Color(235, 96, 54, 16), 1.7f);
        edge.SetLineJoin(LineJoinRound);
        g.DrawPolygon(&edge, pts, 16);
        // 中心高光
        SolidBrush core(Color(210, 255, 250, 226));
        g.FillEllipse(&core, RectF(CenterX - 2.6f, StarY - 2.6f, 5.2f, 5.2f));
    }

    // ---------------------------------------------------------------- 礼物盒（参考图样式）
    static void drawGiftBox(Graphics& g, float cx, float cy, float w, float h, float rotDeg,
                            Gdiplus::Color body, Gdiplus::Color ribbon, Gdiplus::Color bow,
                            bool dots, const TreeLook& look, bool shadow = true) {
        GraphicsState st = g.Save();
        g.TranslateTransform(cx, cy);
        g.RotateTransform(rotDeg);

        if (shadow) {
            SolidBrush sh(Color(46, 0, 0, 0));
            g.FillEllipse(&sh, RectF(-w * 0.60f, h * 0.46f, w * 1.20f, h * 0.20f));
        }
        Pen edge(look.outline, 1.5f);
        edge.SetLineJoin(LineJoinRound);

        // 盒身
        RectF bodyR(-w * 0.5f, -h * 0.20f, w, h * 0.62f);
        GraphicsPath bodyPath;
        addRoundedRect(bodyPath, bodyR, 2.0f);
        SolidBrush bodyBrush(body);
        g.FillPath(&bodyBrush, &bodyPath);
        g.DrawPath(&edge, &bodyPath);
        // 盖
        RectF lidR(-w * 0.54f, -h * 0.38f, w * 1.08f, h * 0.20f);
        GraphicsPath lidPath;
        addRoundedRect(lidPath, lidR, 2.0f);
        SolidBrush lidBrush(treeShade(body, 0.94f));
        g.FillPath(&lidBrush, &lidPath);
        g.DrawPath(&edge, &lidPath);
        // 竖向缎带（参考图是窄缎带）
        SolidBrush rb(ribbon);
        g.FillRectangle(&rb, RectF(-w * 0.055f, -h * 0.38f, w * 0.11f, h * 0.80f));
        g.DrawLine(&edge, PointF(-w * 0.055f, -h * 0.38f), PointF(-w * 0.055f, h * 0.42f));
        g.DrawLine(&edge, PointF(w * 0.055f, -h * 0.38f), PointF(w * 0.055f, h * 0.42f));
        // 白色圆点（参考图右侧小盒）
        if (dots) {
            SolidBrush dot(Color(235, 255, 255, 255));
            for (int row = 0; row < 2; ++row) {
                for (int col = 0; col < 3; ++col) {
                    float dx = (-0.28f + 0.28f * (float)col) * w;
                    float dy = 0.02f * h + 0.22f * h * (float)row;
                    if (std::fabs(dx) < w * 0.11f) continue;
                    g.FillEllipse(&dot, RectF(dx - 1.1f, dy - 1.1f, 2.2f, 2.2f));
                }
            }
        }
        // 大蝴蝶结（双环 + 垂带），环体积收小、垂带更短
        float bs = w * 0.30f;
        SolidBrush bowFill(bow);
        Pen bowEdge(treeShade(bow, 0.55f), 1.0f);
        for (int side = -1; side <= 1; side += 2) {
            GraphicsState s2 = g.Save();
            g.TranslateTransform(side * bs * 0.52f, -h * 0.40f);
            g.RotateTransform(side * -24.0f);
            RectF lp(-bs * 0.52f, -bs * 0.26f, bs * 1.00f, bs * 0.52f);
            GraphicsPath loop;
            loop.AddEllipse(lp);
            g.FillPath(&bowFill, &loop);
            g.DrawPath(&bowEdge, &loop);
            g.Restore(s2);
        }
        SolidBrush knot(bow);
        g.FillEllipse(&knot, RectF(-bs * 0.17f, -h * 0.44f, bs * 0.34f, bs * 0.34f));
        g.DrawEllipse(&bowEdge, RectF(-bs * 0.17f, -h * 0.44f, bs * 0.34f, bs * 0.34f));
        // 垂带
        for (int side = -1; side <= 1; side += 2) {
            PointF a(side * bs * 0.10f, -h * 0.34f);
            PointF b(side * bs * 0.40f, -h * 0.22f);
            PointF c(side * bs * 0.54f, -h * 0.10f);
            Pen tail(bow, 2.0f);
            g.DrawLine(&tail, a, b);
            g.DrawLine(&tail, b, c);
        }
        g.Restore(st);
    }

    static void drawBaseGifts(Graphics& g, const TreeLook& look) {
        // 绿盒金带（左）、米白盒红带（中）、橙色白点红带（右）
        Gdiplus::Color green = treeMix(look.foliageMid, Gdiplus::Color(255, 255, 255), 0.10f);
        Gdiplus::Color gold = look.ribbons[2];
        Gdiplus::Color cream = Gdiplus::Color(255, 0xF1, 0xE5, 0xC8);
        Gdiplus::Color red = look.ribbons[0];
        Gdiplus::Color orange = Gdiplus::Color(255, 0xE2, 0x8C, 0x4C);

        drawGiftBox(g, 116.0f, 291.0f, 52.0f, 42.0f, -5.0f, green, gold, gold, false, look);
        drawGiftBox(g, 182.0f, 293.0f, 56.0f, 43.0f, 2.0f, cream, red, red, false, look);
        drawGiftBox(g, 236.0f, 297.0f, 30.0f, 25.0f, 7.0f, orange, red, red, true, look);
    }

    // ---------------------------------------------------------------- 闪光星 / 礼物粒子
    // 四角凹边闪光星（参考图的星星样式），带细描边
    static void drawSparkle(Graphics& g, float x, float y, float r, Gdiplus::Color color, bool outline = true) {
        GraphicsPath star;
        float k = r * 0.30f;
        star.StartFigure();
        star.AddBezier(PointF(x, y - r), PointF(x + k * 0.30f, y - r * 0.55f), PointF(x + r * 0.55f, y - k * 0.30f), PointF(x + r, y));
        star.AddBezier(PointF(x + r, y), PointF(x + r * 0.55f, y + k * 0.30f), PointF(x + k * 0.30f, y + r * 0.55f), PointF(x, y + r));
        star.AddBezier(PointF(x, y + r), PointF(x - k * 0.30f, y + r * 0.55f), PointF(x - r * 0.55f, y + k * 0.30f), PointF(x - r, y));
        star.AddBezier(PointF(x - r, y), PointF(x - r * 0.55f, y - k * 0.30f), PointF(x - k * 0.30f, y - r * 0.55f), PointF(x, y - r));
        star.CloseFigure();
        SolidBrush fill(color);
        g.FillPath(&fill, &star);
        if (outline) {
            Pen pen(Color(150, 90, 60, 20), 0.9f);
            pen.SetLineJoin(LineJoinRound);
            g.DrawPath(&pen, &star);
        }
        SolidBrush core(Color(210, 255, 250, 226));
        g.FillEllipse(&core, RectF(x - r * 0.20f, y - r * 0.20f, r * 0.40f, r * 0.40f));
    }

    // 礼物图标：0 礼物盒 / 1 手机 / 2 游戏机 / 3 笔记本电脑
    static void drawGiftIcon(Graphics& g, int kind, float cx, float cy, float s, float rotDeg,
                            const TreeLook& look, bool shadow = true) {
        if (kind == 0) {
            // 与底部礼物同款：盒 + 盖 + 十字缎带 + 双环蝴蝶结
            drawGiftBox(g, cx, cy, 20.0f * s, 17.0f * s, rotDeg,
                        look.ornaments[1], look.ribbons[0], look.ribbons[0], false, look, shadow);
            return;
        }
        GraphicsState st = g.Save();
        g.TranslateTransform(cx, cy);
        g.RotateTransform(rotDeg);
        g.ScaleTransform(s, s);
        if (shadow) {
            SolidBrush sh(Color(42, 0, 0, 0));
            g.FillEllipse(&sh, RectF(-11.0f, 9.0f, 22.0f, 5.0f));
        }
        Pen edge(look.outline, 1.4f);
        edge.SetLineJoin(LineJoinRound);
        switch (kind) {
            case 1: {  // 手机
                GraphicsPath body;
                addRoundedRect(body, RectF(-5.8f, -10.4f, 11.6f, 20.8f), 2.6f);
                SolidBrush b(Color(255, 46, 50, 60));
                g.FillPath(&b, &body);
                g.DrawPath(&edge, &body);
                GraphicsPath screen;
                addRoundedRect(screen, RectF(-4.4f, -8.8f, 8.8f, 15.6f), 1.4f);
                SolidBrush sc(Color(255, 96, 206, 255));
                g.FillPath(&sc, &screen);
                SolidBrush dot(Color(255, 238, 238, 244));
                g.FillEllipse(&dot, RectF(-1.1f, 7.8f, 2.2f, 2.2f));
                drawSparkle(g, 0.0f, -2.4f, 3.2f, Color(255, 255, 250, 230), false);
                break;
            }
            case 2: {  // 游戏机
                GraphicsPath body;
                addRoundedRect(body, RectF(-11.5f, -6.8f, 23.0f, 13.6f), 4.8f);
                SolidBrush b(Color(255, 52, 54, 66));
                g.FillPath(&b, &body);
                g.DrawPath(&edge, &body);
                SolidBrush pad(Color(255, 28, 30, 36));
                g.FillRectangle(&pad, RectF(-8.8f, -2.0f, 5.6f, 2.0f));
                g.FillRectangle(&pad, RectF(-7.0f, -3.8f, 2.0f, 5.6f));
                SolidBrush a1(look.ornaments[0]);
                SolidBrush a2(look.ornaments[2]);
                g.FillEllipse(&a1, RectF(3.4f, -3.8f, 3.2f, 3.2f));
                g.FillEllipse(&a2, RectF(6.8f, -0.6f, 3.2f, 3.2f));
                break;
            }
            default: {  // 笔记本电脑
                GraphicsPath screen;
                addRoundedRect(screen, RectF(-8.8f, -9.8f, 17.6f, 12.2f), 1.8f);
                SolidBrush b(Color(255, 72, 78, 92));
                g.FillPath(&b, &screen);
                g.DrawPath(&edge, &screen);
                SolidBrush sc(Color(255, 124, 222, 255));
                g.FillRectangle(&sc, RectF(-7.4f, -8.4f, 14.8f, 9.6f));
                GraphicsPath base;
                addRoundedRect(base, RectF(-11.4f, 2.6f, 22.8f, 3.6f), 1.4f);
                SolidBrush bb(Color(255, 182, 186, 196));
                g.FillPath(&bb, &base);
                g.DrawPath(&edge, &base);
                break;
            }
        }
        g.Restore(st);
    }

    // 靠近画布边缘时淡出/收缩，避免 2 倍尺寸的粒子被 360x320 画布硬裁掉
    static float edgeFade(float x, float y, float r) {
        float d = std::min(std::min(x - r, 360.0f - x - r), std::min(y - r, 320.0f - y - r));
        return std::clamp(d / 26.0f, 0.0f, 1.0f);
    }

    static void drawParticles(Graphics& g, const CatPhysics& physics, const TreeLook& look) {
        // 星星：只向上飞，尺寸是原来的 2 倍
        for (const auto& sp : physics.sparkles) {
            if (sp.isSleepZ) continue;
            float p = std::clamp(sp.age / std::max(0.05f, sp.lifetime), 0.0f, 1.0f);
            float r = 6.8f + p * 8.4f;
            float fade = edgeFade(sp.position.x, sp.position.y, r);
            BYTE a = (BYTE)(std::sin(std::min(1.0f, p * 1.25f) * 3.14159f) * 245.0f * fade);
            if (a < 10) continue;
            GraphicsState gs = g.Save();
            g.TranslateTransform(sp.position.x, sp.position.y);
            g.RotateTransform(p * 70.0f - 35.0f);
            drawSparkle(g, 0.0f, 0.0f, r, treeWithAlpha(treeMix(look.star, Color(255, 255, 240, 190), 0.45f), a));
            g.Restore(gs);
        }
        // 礼物：尺寸 2 倍；接近画布边缘时按比例收缩，不出界
        for (const auto& gift : physics.gifts) {
            float p = std::clamp(gift.age / std::max(0.05f, gift.lifetime), 0.0f, 1.0f);
            if (p > 0.94f) continue;
            float scale = gift.scale * (p < 0.12f ? (p / 0.12f) : 1.0f) * (p > 0.8f ? (1.0f - (p - 0.8f) / 0.2f) : 1.0f);
            scale *= 2.0f;                                   // 整体放大 2 倍
            float gr = 26.0f * scale * 0.5f;
            float fade = edgeFade(gift.position.x, gift.position.y, gr);
            if (fade < 0.05f) continue;
            scale *= (0.35f + 0.65f * fade);
            drawGiftIcon(g, gift.kind, gift.position.x, gift.position.y, std::max(0.15f, scale), gift.rotation, look);
        }
    }
};
