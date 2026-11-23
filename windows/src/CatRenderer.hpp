#pragma once
#define NOMINMAX
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <cmath>
#include <vector>
#include <algorithm>
#include "CatPhysics.hpp"

enum class CatHitZone {
    None,
    Head,
    Body
};

class CatRenderer {
public:
    static constexpr float RadToDeg = 57.2957795f;

    static CatHitZone hitTest(Pt p, const CatPhysics& physics) {
        float cx = CatPhysics::SeatAnchor.x + physics.bodyShiftX.value;
        float breath = physics.currentBreathOffset();
        Pt headCenter = { cx + physics.bodyTilt.value * 36.0f + physics.headYaw.value * 7.5f,
                          126.0f + physics.headOffsetY.value + physics.headPitch.value * 4.8f + breath * 1.1f };

        float hdx = (p.x - headCenter.x) / 48.0f;
        float hdy = (p.y - headCenter.y) / 42.0f;
        if (hdx * hdx + hdy * hdy <= 1.0f) return CatHitZone::Head;

        float bdx = (p.x - cx) / 58.0f;
        float bdy = (p.y - 196.0f) / 56.0f;
        if (bdx * bdx + bdy * bdy <= 1.0f) return CatHitZone::Body;

        if (p.x >= 58.0f && p.x <= 294.0f && p.y >= 232.0f && p.y <= 296.0f) return CatHitZone::Body;
        return CatHitZone::None;
    }

    static void draw(Gdiplus::Graphics& g, const CatPhysics& physics, const CatSettings& settings) {
        using namespace Gdiplus;
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        g.SetPixelOffsetMode(PixelOffsetModeHighQuality);
        g.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);

        const CatAppearance& app = settings.appearance;
        float breath = physics.currentBreathOffset();
        float seatX = CatPhysics::SeatAnchor.x + physics.bodyShiftX.value;
        float seatY = CatPhysics::SeatAnchor.y;

        Pt headCenter = {
            seatX + physics.bodyTilt.value * 36.0f + physics.headYaw.value * 7.5f,
            126.0f + physics.headOffsetY.value + physics.headPitch.value * 4.8f + breath * 1.1f
        };

        // 1. Mini White Mouse (facing cat)
        drawMouse(g, physics, settings.keyboardTheme);

        // 2. Mini 65% Mechanical Keyboard (facing cat) + Backlit Glow
        drawKeyboard(g, physics, settings.keyboardTheme, toGdi(app.eyeColor));

        // 3. Tail (dedicated Long-Fur plume pipeline when furLength >= 0.30)
        if (app.useLongFurPipeline()) {
            drawLongFurTail(g, seatX, seatY, physics, app);
        } else {
            drawTail(g, seatX, seatY, physics, app);
        }

        // 4. 3D-Projected Ears
        drawEarsLayer(g, headCenter, physics, app);

        // 5. Unified Silhouette (sleek short-hair OR dedicated Long-Fur fluffy silhouette!)
        drawUnifiedSilhouette(g, seatX, seatY, headCenter, breath, physics, app);

        // 5b. Configurable Necktie / Bow Tie Accessory
        if (settings.showTie) {
            drawTieAccessory(g, seatX, headCenter, breath, physics, settings, app);
        }

        // 6. Hind Foot (3rd simultaneous key easter egg!)
        if (physics.hindFootActive.value > 0.03f) {
            drawHindFoot(g, seatX, seatY, physics, app);
        }

        // 7. 2.5D Eyes (with Sleeping & 0-6AM Tired states) & Whiskers
        drawHeadFeatures(g, headCenter, physics, app);

        // 8. Front Paws (Idle Sitting & Dynamic Reaching)
        drawFrontPaws(g, seatX, seatY, breath, physics, app);

        // 9. Floating Keycap Badges
        if (settings.showKeyBadges) {
            drawFloatingKeycaps(g, physics);
        }

        // 10. Subtle Petting Sparkles & Sleep Z
        drawSparkles(g, physics, toGdi(app.eyeColor));
    }

private:
    static Gdiplus::Color toGdi(RGBColor c, BYTE a = 255) { return Gdiplus::Color(a, c.r, c.g, c.b); }
    static Gdiplus::Color catBlack(BYTE a = 255)      { return Gdiplus::Color(a, 22, 22, 24); }
    static Gdiplus::Color contourMint(BYTE a = 194)   { return Gdiplus::Color(a, 209, 235, 227); }
    static Gdiplus::Color whiskerWhite(BYTE a = 174)  { return Gdiplus::Color(a, 224, 230, 235); }
    static Gdiplus::Color outlineFor(const CatAppearance& app, BYTE a = 215) {
        return toGdi(app.primaryColor.darkened(0.58f), a);
    }
    static Gdiplus::Color limbSepColor(const CatAppearance& app, BYTE a = 200) {
        return app.isDarkCoat() ? contourMint(a) : toGdi(app.primaryColor.darkened(0.55f), a);
    }
    static Pt cubicPoint(Pt p0, Pt p1, Pt p2, Pt p3, float t) {
        float mt = 1.0f - t, mt2 = mt * mt, t2 = t * t;
        return { mt2*mt*p0.x + 3*mt2*t*p1.x + 3*mt*t2*p2.x + t2*t*p3.x,
                 mt2*mt*p0.y + 3*mt2*t*p1.y + 3*mt*t2*p2.y + t2*t*p3.y };
    }
    static Pt cubicTangent(Pt p0, Pt p1, Pt p2, Pt p3, float t) {
        float mt = 1.0f - t;
        return { 3*mt*mt*(p1.x - p0.x) + 6*mt*t*(p2.x - p1.x) + 3*t*t*(p3.x - p2.x),
                 3*mt*mt*(p1.y - p0.y) + 6*mt*t*(p2.y - p1.y) + 3*t*t*(p3.y - p2.y) };
    }

    static Gdiplus::Color blendColor(Gdiplus::Color a, Gdiplus::Color b, float t) {
        t = std::clamp(t, 0.0f, 1.0f);
        auto lerp = [t](BYTE x, BYTE y) -> BYTE { return (BYTE)std::clamp((int)(x + (y - x) * t + 0.5f), 0, 255); };
        return Gdiplus::Color(lerp(a.GetA(), b.GetA()), lerp(a.GetR(), b.GetR()), lerp(a.GetG(), b.GetG()), lerp(a.GetB(), b.GetB()));
    }

    static void addRoundedRect(Gdiplus::GraphicsPath& p, float x, float y, float w, float h, float r) {
        float d = std::min(r * 2.0f, std::min(w, h));
        if (d <= 0.5f) {
            p.AddRectangle(Gdiplus::RectF(x, y, w, h));
            return;
        }
        p.AddArc(x, y, d, d, 180.0f, 90.0f);
        p.AddArc(x + w - d, y, d, d, 270.0f, 90.0f);
        p.AddArc(x + w - d, y + h - d, d, d, 0.0f, 90.0f);
        p.AddArc(x, y + h - d, d, d, 90.0f, 90.0f);
        p.CloseFigure();
    }

    static void addQuadPoly(Gdiplus::GraphicsPath& p, Pt tl, Pt tr, Pt br, Pt bl) {
        Gdiplus::PointF pts[4] = { {tl.x, tl.y}, {tr.x, tr.y}, {br.x, br.y}, {bl.x, bl.y} };
        p.AddPolygon(pts, 4);
    }

    static void addQuadBezier(Gdiplus::GraphicsPath& p, Pt p0, Pt ctrl, Pt p2) {
        // Convert quadratic Bezier (p0, ctrl, p2) -> exact cubic Bezier for GDI+
        Gdiplus::PointF c1(p0.x + (2.0f / 3.0f) * (ctrl.x - p0.x), p0.y + (2.0f / 3.0f) * (ctrl.y - p0.y));
        Gdiplus::PointF c2(p2.x + (2.0f / 3.0f) * (ctrl.x - p2.x), p2.y + (2.0f / 3.0f) * (ctrl.y - p2.y));
        p.AddBezier(Gdiplus::PointF(p0.x, p0.y), c1, c2, Gdiplus::PointF(p2.x, p2.y));
    }

    static Pt projectHead3D(float x, float y, float z, float yawRad, float pitchRad) {
        float cy = std::cos(yawRad), sy = std::sin(yawRad);
        float x1 = x * cy + z * sy;
        float z1 = -x * sy + z * cy;
        float cp = std::cos(pitchRad), sp = std::sin(pitchRad);
        float y2 = y * cp + z1 * sp;
        return { x1, y2 };
    }

    static Pt quadPoint(Pt p0, Pt p1, Pt p2, float t) {
        float mt = 1.0f - t;
        return { mt * mt * p0.x + 2.0f * mt * t * p1.x + t * t * p2.x,
                 mt * mt * p0.y + 2.0f * mt * t * p1.y + t * t * p2.y };
    }

    static Pt quadTangent(Pt p0, Pt p1, Pt p2, float t) {
        float mt = 1.0f - t;
        return { 2.0f * mt * (p1.x - p0.x) + 2.0f * t * (p2.x - p1.x),
                 2.0f * mt * (p1.y - p0.y) + 2.0f * t * (p2.y - p1.y) };
    }

    // MARK: - Mini White Mouse (180° facing the cat)

    static void drawMouse(Gdiplus::Graphics& g, const CatPhysics& physics, KeyboardTheme theme) {
        using namespace Gdiplus;
        Pt center = { CatPhysics::MouseBaseCenter.x + physics.mouseOffset.point().x,
                      CatPhysics::MouseBaseCenter.y + physics.mouseOffset.point().y };
        float pressShift = std::max(physics.mousePressLeft.value, physics.mousePressRight.value) * 1.6f;

        GraphicsState st = g.Save();
        g.TranslateTransform(center.x, center.y + pressShift);
        g.RotateTransform(0.22f * RadToDeg);

        SolidBrush shadowBrush(Color(60, 0, 0, 0));
        g.FillEllipse(&shadowBrush, -13.5f, -9.5f, 27.0f, 31.0f);

        Color bodyCol, borderCol, wheelCol;
        if (theme == KeyboardTheme::MidnightHacker) {
            bodyCol = Color(255, 51, 54, 61); borderCol = Color(255, 20, 20, 26); wheelCol = Color(255, 199, 242, 64);
        } else if (theme == KeyboardTheme::RetroCream) {
            bodyCol = Color(255, 227, 222, 209); borderCol = Color(255, 51, 48, 46); wheelCol = Color(255, 224, 107, 61);
        } else {
            bodyCol = Color(255, 244, 242, 236); borderCol = Color(255, 36, 36, 41); wheelCol = Color(255, 245, 176, 41);
        }

        SolidBrush bodyBrush(bodyCol);
        g.FillEllipse(&bodyBrush, -13.5f, -16.5f, 27.0f, 33.0f);

        if (physics.mousePressLeft.value > 0.05f || physics.mousePressRight.value > 0.05f) {
            GraphicsPath clipPath;
            clipPath.AddEllipse(-13.5f, -16.5f, 27.0f, 33.0f);
            GraphicsState cs = g.Save();
            g.SetClip(&clipPath);
            if (physics.mousePressLeft.value > 0.05f) {
                SolidBrush hb(Color((BYTE)(96 * physics.mousePressLeft.value), 201, 242, 64));
                g.FillRectangle(&hb, 0.0f, 0.0f, 14.0f, 17.0f);
            }
            if (physics.mousePressRight.value > 0.05f) {
                SolidBrush hb(Color((BYTE)(96 * physics.mousePressRight.value), 201, 242, 64));
                g.FillRectangle(&hb, -14.0f, 0.0f, 14.0f, 17.0f);
            }
            g.Restore(cs);
        }

        // Front button split seam pointing away from cat (bottom)
        Pen seamPen(Color(82, borderCol.GetR(), borderCol.GetG(), borderCol.GetB()), 1.05f);
        g.DrawLine(&seamPen, 0.0f, 16.0f, 0.0f, 1.5f);

        // Amber scroll wheel on front (bottom) half
        GraphicsPath wheelPath;
        addRoundedRect(wheelPath, -1.9f, 2.5f, 3.8f, 8.5f, 1.9f);
        SolidBrush wheelBrush(wheelCol);
        g.FillPath(&wheelBrush, &wheelPath);

        Pen borderPen(borderCol, 1.7f);
        g.DrawEllipse(&borderPen, -13.5f, -16.5f, 27.0f, 33.0f);
        g.Restore(st);
    }

    // MARK: - Mini 65% Mechanical Keyboard (180° facing the cat)

    static void drawKeyboard(Gdiplus::Graphics& g, const CatPhysics& physics, KeyboardTheme theme, Gdiplus::Color glowColor) {
        using namespace Gdiplus;
        Pt tl = KeyboardLayout::screenQuadPoint(-0.025f, -0.08f);
        Pt tr = KeyboardLayout::screenQuadPoint(1.025f, -0.08f);
        Pt bl = KeyboardLayout::screenQuadPoint(-0.032f, 1.08f);
        Pt br = KeyboardLayout::screenQuadPoint(1.032f, 1.08f);
        constexpr float depth = 6.5f;

        // Shadow
        {
            GraphicsPath sp;
            addQuadPoly(sp, {tl.x, tl.y + depth + 2}, {tr.x, tr.y + depth + 2},
                            {br.x, br.y + depth + 3}, {bl.x, bl.y + depth + 3});
            SolidBrush sb(Color(56, 0, 0, 0));
            g.FillPath(&sb, &sp);
        }

        Color baseCol, deckCol, keyCol, borderCol, accentCol;
        if (theme == KeyboardTheme::MidnightHacker) {
            baseCol = Color(255, 15, 15, 20); deckCol = Color(255, 26, 28, 33);
            keyCol = Color(255, 54, 56, 64); borderCol = Color(242, 28, 28, 33); accentCol = Color(255, 196, 240, 64);
        } else if (theme == KeyboardTheme::RetroCream) {
            baseCol = Color(255, 64, 61, 56); deckCol = Color(255, 97, 92, 84);
            keyCol = Color(255, 230, 224, 209); borderCol = Color(216, 173, 166, 153); accentCol = Color(255, 224, 107, 61);
        } else {
            baseCol = Color(255, 26, 26, 31); deckCol = Color(255, 36, 36, 41);
            keyCol = Color(255, 247, 246, 240); borderCol = Color(190, 199, 196, 189); accentCol = Color(255, 247, 179, 41);
        }

        {
            GraphicsPath lp;
            addQuadPoly(lp, {tl.x, tl.y + depth}, {tr.x, tr.y + depth}, {br.x, br.y + depth}, {bl.x, bl.y + depth});
            SolidBrush bb(baseCol);
            Pen bp(baseCol, 5.0f); bp.SetLineJoin(LineJoinRound);
            g.FillPath(&bb, &lp);
            g.DrawPath(&bp, &lp);
        }
        {
            GraphicsPath tp;
            addQuadPoly(tp, tl, tr, br, bl);
            SolidBrush db(deckCol);
            Pen dp(deckCol, 4.0f); dp.SetLineJoin(LineJoinRound);
            g.FillPath(&db, &tp);
            g.DrawPath(&dp, &tp);
        }

        constexpr float padU = 0.0028f;
        constexpr float padV = 0.014f;
        Color glowCol(215, glowColor.GetR(), glowColor.GetG(), glowColor.GetB());
        Pen keyBorderPen(borderCol, 0.7f);

        for (const auto& cap : KeyboardLayout::keycaps()) {
            float glow = 0.0f;
            auto it = physics.keyGlow.find(cap.key);
            if (it != physics.keyGlow.end()) glow = it->second;

            // 180° rotated to face the cat
            float su0 = (1.0f - (cap.xUnits + cap.widthUnits)) + padU;
            float su1 = (1.0f - cap.xUnits) - padU;
            float sv0 = (1.0f - (cap.row + 1) / 5.0f) + padV;
            float sv1 = (1.0f - cap.row / 5.0f) - padV;

            float dy = glow * 1.9f;
            Pt kTL = KeyboardLayout::screenQuadPoint(su0, sv0); kTL.y += dy;
            Pt kTR = KeyboardLayout::screenQuadPoint(su1, sv0); kTR.y += dy;
            Pt kBR = KeyboardLayout::screenQuadPoint(su1, sv1); kBR.y += dy;
            Pt kBL = KeyboardLayout::screenQuadPoint(su0, sv1); kBL.y += dy;

            GraphicsPath kp;
            addQuadPoly(kp, kTL, kTR, kBR, kBL);
            Color fill = cap.isAmberAccent ? accentCol : keyCol;
            if (glow > 0.02f) fill = blendColor(fill, glowCol, glow * 0.55f);

            SolidBrush kb(fill);
            g.FillPath(&kb, &kp);
            g.DrawPath(&keyBorderPen, &kp);
        }

        // Radiant backlit glow halos over pressed keys
        for (const auto& kv : physics.keyGlow) {
            if (kv.second <= 0.05f) continue;
            Pt c = KeyboardLayout::canvasPointForKey(kv.first);
            float r = 17.0f + kv.second * 6.0f;
            GraphicsPath gp;
            gp.AddEllipse(c.x - r, c.y - r, r * 2.0f, r * 2.0f);
            PathGradientBrush pgb(&gp);
            pgb.SetCenterColor(Color((BYTE)(92 * kv.second), glowCol.GetR(), glowCol.GetG(), glowCol.GetB()));
            Color surr[1] = { Color(0, glowCol.GetR(), glowCol.GetG(), glowCol.GetB()) };
            INT cnt = 1;
            pgb.SetSurroundColors(surr, &cnt);
            g.FillPath(&pgb, &gp);
        }
    }

    // MARK: - Tail (Short-Hair & Dedicated Long-Fur Plume Pipeline)

    static void drawTail(Gdiplus::Graphics& g, float seatX, float seatY, const CatPhysics& physics, const CatAppearance& app) {
        using namespace Gdiplus;
        float p = physics.tailPhase;
        float hunt = std::clamp(physics.huntIntensity.value, 0.0f, 1.0f);
        float sleepCalm = 1.0f - physics.sleepiness * 0.65f;
        float wag1 = std::sin(p) * (8.0f + hunt * 5.5f) * sleepCalm;
        float wag2 = std::cos(p * 1.3f) * (6.0f + hunt * 4.5f) * sleepCalm;
        float huntDrop = hunt * 14.0f + physics.sleepiness * 18.0f;
        float sleepCurl = physics.sleepiness * 14.0f;

        PointF root(seatX + 34.0f, seatY - 6.0f);
        PointF c1(seatX + 64.0f - sleepCurl * 0.3f, seatY + 2.0f + wag1 * 0.35f + huntDrop * 0.4f);
        PointF c2(seatX + 66.0f - sleepCurl * 0.7f + wag2 * 0.4f, seatY - 26.0f + wag1 * 0.7f + huntDrop);
        PointF tip(seatX + 91.0f - sleepCurl + wag2 * 0.5f, seatY - 30.0f + wag1 * 0.85f + huntDrop);

        RGBColor baseCol = app.primaryColor;
        if (app.pattern == FurPattern::Colorpoint) baseCol = app.secondaryColor;
        else if (app.pattern == FurPattern::Calico) baseCol = app.tertiaryColor;

        if (!app.isDarkCoat()) {
            Pen outPen(outlineFor(app), 13.6f);
            outPen.SetStartCap(LineCapRound); outPen.SetEndCap(LineCapRound); outPen.SetLineJoin(LineJoinRound);
            g.DrawBezier(&outPen, root, c1, c2, tip);
        }
        Pen tailPen(toGdi(baseCol), 11.0f);
        tailPen.SetStartCap(LineCapRound); tailPen.SetEndCap(LineCapRound); tailPen.SetLineJoin(LineJoinRound);
        g.DrawBezier(&tailPen, root, c1, c2, tip);

        Pt rPt = {root.X, root.Y}, c1Pt = {c1.X, c1.Y}, c2Pt = {c2.X, c2.Y}, tPt = {tip.X, tip.Y};
        if (app.pattern == FurPattern::Tabby || app.pattern == FurPattern::Spotted) {
            SolidBrush rb(toGdi(app.secondaryColor, 215));
            for (float t : {0.28f, 0.50f, 0.72f, 0.90f}) {
                Pt pt = cubicPoint(rPt, c1Pt, c2Pt, tPt, t);
                g.FillEllipse(&rb, pt.x - 4.0f, pt.y - 3.4f, 8.0f, 6.8f);
            }
        } else if (app.pattern == FurPattern::Calico) {
            SolidBrush rb(toGdi(app.secondaryColor));
            Pt pt = cubicPoint(rPt, c1Pt, c2Pt, tPt, 0.55f);
            g.FillEllipse(&rb, pt.x - 5.0f, pt.y - 5.0f, 10.0f, 10.0f);
        } else if (app.pattern == FurPattern::Tuxedo) {
            SolidBrush rb(toGdi(app.secondaryColor));
            g.FillEllipse(&rb, tip.X - 5.0f, tip.Y - 5.0f, 10.0f, 10.0f);
        }
    }

    static void drawLongFurTail(Gdiplus::Graphics& g, float seatX, float seatY, const CatPhysics& physics, const CatAppearance& app) {
        using namespace Gdiplus;
        float p = physics.tailPhase;
        float hunt = std::clamp(physics.huntIntensity.value, 0.0f, 1.0f);
        float sleepCalm = 1.0f - physics.sleepiness * 0.65f;
        float fluff = std::clamp(app.furLength, 0.3f, 1.0f);
        float swayX = physics.furSwayX.value;
        float swayY = physics.furSwayY.value;

        float wag1 = std::sin(p) * (7.5f + hunt * 5.0f) * sleepCalm;
        float wag2 = std::cos(p * 1.3f) * (5.5f + hunt * 4.0f) * sleepCalm;
        float huntDrop = hunt * 13.0f + physics.sleepiness * 18.0f;
        float sleepCurl = physics.sleepiness * 15.0f;

        Pt root = { seatX + 33.0f, seatY - 6.0f };
        Pt c1   = { seatX + 64.0f - sleepCurl * 0.3f + swayX * 0.35f, seatY + 4.0f + wag1 * 0.35f + huntDrop * 0.4f + swayY * 0.3f };
        Pt c2   = { seatX + 68.0f - sleepCurl * 0.7f + wag2 * 0.45f + swayX * 0.9f,  seatY - 28.0f + wag1 * 0.7f + huntDrop + swayY * 0.7f };
        Pt tip  = { seatX + 95.0f - sleepCurl + wag2 * 0.55f + swayX * 1.4f,        seatY - 34.0f + wag1 * 0.85f + huntDrop + swayY * 1.1f };

        constexpr int steps = 26;
        std::vector<PointF> poly;
        poly.reserve(steps * 2 + 4);
        std::vector<PointF> lower;
        lower.reserve(steps + 1);

        for (int i = 0; i <= steps; ++i) {
            float t = (float)i / (float)steps;
            Pt pt = cubicPoint(root, c1, c2, tip, t);
            Pt tan = cubicTangent(root, c1, c2, tip, t);
            float len = std::max(0.001f, std::hypot(tan.x, tan.y));
            float nx = -tan.y / len, ny = tan.x / len;
            float env = std::sin(std::pow(t, 0.78f) * 3.14159265f);
            float baseHW = (4.5f + 10.5f * fluff * env) * (1.0f - 0.15f * t);
            float lockU = std::max(0.0f, std::sin(t * 3.14159265f * 4.5f)) * (2.2f * fluff * env);
            float lockL = std::max(0.0f, std::sin(t * 3.14159265f * 5.5f + 0.8f)) * (4.2f * fluff * env);
            float lagX = swayX * (0.25f + t * 0.75f) * fluff;
            float lagY = (2.8f * fluff * env) + swayY * (0.25f + t * 0.65f) * fluff;
            float upH = baseHW * 0.78f + lockU;
            float dnH = baseHW * 1.15f + lockL;
            poly.push_back(PointF(pt.x - nx * upH + lagX * 0.35f, pt.y - ny * upH + lagY * 0.25f));
            lower.push_back(PointF(pt.x + nx * dnH + lagX, pt.y + ny * dnH + lagY));
        }
        poly.push_back(PointF(tip.x + 5.5f * fluff + swayX * 0.6f, tip.y - 2.0f * fluff + swayY * 0.5f));
        for (int i = steps; i >= 0; --i) poly.push_back(lower[i]);

        GraphicsPath plume;
        plume.AddClosedCurve(poly.data(), (INT)poly.size(), 0.35f);

        RGBColor baseCol = app.primaryColor;
        if (app.pattern == FurPattern::Colorpoint) baseCol = app.secondaryColor;
        else if (app.pattern == FurPattern::Calico) baseCol = app.tertiaryColor;

        GraphicsState cs = g.Save();
        g.SetClip(&plume);
        SolidBrush pb(toGdi(baseCol));
        g.FillPath(&pb, &plume);
        if (app.pattern == FurPattern::Tabby || app.pattern == FurPattern::Spotted) {
            Pen rp(toGdi(app.secondaryColor, 195), 5.2f);
            rp.SetStartCap(LineCapRound); rp.SetEndCap(LineCapRound);
            for (float t : {0.25f, 0.48f, 0.70f, 0.88f}) {
                Pt pt = cubicPoint(root, c1, c2, tip, t);
                Pt tan = cubicTangent(root, c1, c2, tip, t);
                float len = std::max(0.001f, std::hypot(tan.x, tan.y));
                float nx = -tan.y / len, ny = tan.x / len;
                g.DrawLine(&rp, pt.x - nx * 18, pt.y - ny * 18, pt.x + nx * 18, pt.y + ny * 18);
            }
        } else if (app.pattern == FurPattern::Calico) {
            SolidBrush rb(toGdi(app.secondaryColor));
            Pt pt = cubicPoint(root, c1, c2, tip, 0.54f);
            g.FillEllipse(&rb, pt.x - 14, pt.y - 14, 28, 28);
        } else if (app.pattern == FurPattern::Tuxedo) {
            SolidBrush rb(toGdi(app.secondaryColor));
            g.FillEllipse(&rb, tip.x - 12, tip.y - 12, 28, 26);
        }
        g.Restore(cs);

        Pen outPen(app.isDarkCoat() ? contourMint(66) : outlineFor(app, 210), app.isDarkCoat() ? 1.0f : 1.4f);
        g.DrawPath(&outPen, &plume);
    }

    // MARK: - 3D-Projected Ears (with Long-Fur Lynx Tips & Inner Furnishings)

    static void drawEarsLayer(Gdiplus::Graphics& g, Pt center, const CatPhysics& physics, const CatAppearance& app) {
        using namespace Gdiplus;
        GraphicsState st = g.Save();
        g.TranslateTransform(center.x, center.y);
        g.RotateTransform(physics.headTilt.value * RadToDeg);

        float yawRad = physics.headYaw.value * 0.50f;
        float pitchRad = physics.headPitch.value * 0.36f;
        float fold = physics.earFold.value;
        float twitch = physics.earTwitch.value * 0.045f;

        drawEar3D(g, true, yawRad, pitchRad, fold, twitch, physics, app);
        drawEar3D(g, false, yawRad, pitchRad, fold, -twitch, physics, app);
        g.Restore(st);
    }

    static void drawEar3D(Gdiplus::Graphics& g, bool isLeft, float yawRad, float pitchRad, float fold, float twitch, const CatPhysics& physics, const CatAppearance& app) {
        using namespace Gdiplus;
        float sign = isLeft ? -1.0f : 1.0f;
        float foldAngle = sign * (0.06f + fold * 0.34f) + twitch;
        bool longFur = app.useLongFurPipeline();
        float fluff = longFur ? std::clamp(app.furLength, 0.3f, 1.0f) : 0.0f;
        float tipDx = std::sin(foldAngle) * (32.0f + fluff * 3.0f);
        float tipDy = -std::cos(foldAngle) * (32.0f + fluff * 3.0f);

        Pt innerBase = projectHead3D(sign * 9.0f, -16.0f, 0.0f, yawRad, pitchRad);
        Pt outerBase = projectHead3D(sign * (longFur ? 36.5f : 35.0f), -4.5f, -2.0f, yawRad, pitchRad);
        Pt tip3D     = projectHead3D(sign * 24.5f + tipDx, -20.0f + tipDy, -3.0f, yawRad, pitchRad);

        GraphicsPath ear;
        if (longFur) {
            Pt lynx = { tip3D.x + sign * (1.8f * fluff) + physics.furSwayX.value * 0.35f,
                        tip3D.y - (5.0f * fluff) + physics.furSwayY.value * 0.25f };
            addQuadBezier(ear, innerBase, { (innerBase.x + tip3D.x)*0.5f - sign*3.0f, (innerBase.y + tip3D.y)*0.5f - 3.5f }, lynx);
            addQuadBezier(ear, lynx, { (outerBase.x + tip3D.x)*0.5f + sign*4.5f, (outerBase.y + tip3D.y)*0.5f - 1.5f }, outerBase);
        } else {
            Pt tipL = { tip3D.x - sign * 3.8f, tip3D.y + 2.8f };
            Pt tipR = { tip3D.x + sign * 3.8f, tip3D.y + 3.2f };
            addQuadBezier(ear, innerBase, { (innerBase.x + tipL.x) * 0.5f - sign * 1.5f, (innerBase.y + tipL.y) * 0.5f - 2.0f }, tipL);
            addQuadBezier(ear, tipL, { tip3D.x, tip3D.y - 2.2f }, tipR);
            addQuadBezier(ear, tipR, { (outerBase.x + tipR.x) * 0.5f + sign * 2.5f, (outerBase.y + tipR.y) * 0.5f - 2.0f }, outerBase);
        }
        ear.CloseFigure();

        RGBColor earCol = app.primaryColor;
        if (app.pattern == FurPattern::Colorpoint) earCol = app.secondaryColor;
        else if (app.pattern == FurPattern::Calico) earCol = isLeft ? app.secondaryColor : app.tertiaryColor;

        SolidBrush b(toGdi(earCol));
        g.FillPath(&b, &ear);
        if (!app.isDarkCoat()) {
            Pen op(outlineFor(app), 1.35f);
            g.DrawPath(&op, &ear);
        }
        if (longFur) {
            Pt fb = projectHead3D(sign * 17.5f, -18.5f, 3.0f, yawRad, pitchRad);
            Color fc = app.isDarkCoat() ? Color((BYTE)(70 * fluff), 217, 217, 217) : toGdi(app.primaryColor.lightened(0.45f), (BYTE)(190 * fluff));
            Pen fp(fc, 1.5f);
            fp.SetStartCap(LineCapRound); fp.SetEndCap(LineCapRound);
            for (int i = 0; i < 2; ++i) {
                float off = i * 4.0f;
                GraphicsPath t;
                addQuadBezier(t, {fb.x, fb.y + off}, {fb.x + sign * 5.5f * fluff, fb.y - 4.5f + off}, {fb.x + sign * 10.5f * fluff, fb.y - 6.0f + off});
                g.DrawPath(&fp, &t);
            }
        }
    }

    // MARK: - Unified Silhouette (Short-Hair & Dedicated Long-Fur Pipeline + All 6 Fur Patterns)

    static void drawUnifiedSilhouette(Gdiplus::Graphics& g, float seatX, float seatY, Pt headCenter, float breath, const CatPhysics& physics, const CatAppearance& app) {
        using namespace Gdiplus;
        float yaw = physics.headYaw.value;
        float pitch = physics.headPitch.value;
        float hTilt = physics.headTilt.value;
        float bTilt = physics.bodyTilt.value;
        bool longFur = app.useLongFurPipeline();
        float f = longFur ? std::clamp(app.furLength, 0.3f, 1.0f) : 0.0f;
        float swayX = physics.furSwayX.value;
        float swayY = physics.furSwayY.value;

        float cH = std::cos(hTilt), sH = std::sin(hTilt);
        auto H = [&](float lx, float ly) -> PointF {
            return PointF(headCenter.x + lx * cH - ly * sH, headCenter.y + lx * sH + ly * cH);
        };
        auto HPt = [&](float lx, float ly) -> Pt { PointF p = H(lx, ly); return {p.X, p.Y}; };

        float cB = std::cos(bTilt), sB = std::sin(bTilt);
        float sy = physics.bodySquash.value;
        float sx = 1.0f + (1.0f - sy) * 0.55f;
        auto B = [&](float lx, float ly) -> PointF {
            float rx = lx * sx, ry = ly * sy;
            return PointF(seatX + rx * cB - ry * sB, seatY + rx * sB + ry * cB);
        };
        auto BPt = [&](float lx, float ly) -> Pt { PointF p = B(lx, ly); return {p.X, p.Y}; };

        float cheekShift = yaw * 3.0f;
        float crownDrop = pitch * 2.0f;
        GraphicsPath path;

        if (longFur) {
            Pt crownL = HPt(-12 + cheekShift * 0.2f, -31.0f - f * 2.5f + crownDrop);
            Pt crownT = HPt(cheekShift * 0.2f + swayX * 0.35f, -34.5f - f * 4.5f + crownDrop + swayY * 0.25f);
            Pt crownR = HPt(12 + cheekShift * 0.2f, -31.0f - f * 2.5f + crownDrop);
            Pt rT = HPt(38.0f + f*3.0f + cheekShift*0.4f, -14.0f);
            Pt rC1 = HPt(47.5f + f*9.5f + cheekShift*0.4f + swayX*0.55f, 2.0f + swayY*0.45f);
            Pt rCI = HPt(43.0f + f*5.5f + cheekShift*0.35f + swayX*0.35f, 9.5f + swayY*0.35f);
            Pt rC2 = HPt(49.0f + f*11.0f + cheekShift*0.35f + swayX*0.80f, 18.0f + f*3.5f + swayY*0.65f);
            Pt rN  = HPt(41.0f + f*5.0f + cheekShift*0.25f + swayX*0.45f, 28.0f + f*2.0f);
            Pt rF1 = BPt(53.0f + f*8.5f + swayX*0.55f, -52.0f + breath*0.4f + swayY*0.45f);
            Pt rFI = BPt(50.5f + f*5.5f + swayX*0.35f, -36.0f + breath*0.3f);
            Pt rH  = BPt(55.0f + f*8.0f + swayX*0.45f, -14.0f + swayY*0.35f);
            PointF rBot = B(26.0f + f*3.0f, 12.5f);
            PointF lBot = B(-26.0f - f*3.0f, 12.5f);
            Pt lH  = BPt(-55.0f - f*8.0f + swayX*0.45f, -14.0f + swayY*0.35f);
            Pt lFI = BPt(-50.5f - f*5.5f + swayX*0.35f, -36.0f + breath*0.3f);
            Pt lF1 = BPt(-53.0f - f*8.5f + swayX*0.55f, -52.0f + breath*0.4f + swayY*0.45f);
            Pt lN  = HPt(-41.0f - f*5.0f + cheekShift*0.25f + swayX*0.45f, 28.0f + f*2.0f);
            Pt lC2 = HPt(-49.0f - f*11.0f + cheekShift*0.35f + swayX*0.80f, 18.0f + f*3.5f + swayY*0.65f);
            Pt lCI = HPt(-43.0f - f*5.5f + cheekShift*0.35f + swayX*0.35f, 9.5f + swayY*0.35f);
            Pt lC1 = HPt(-47.5f - f*9.5f + cheekShift*0.4f + swayX*0.55f, 2.0f + swayY*0.45f);
            Pt lT  = HPt(-38.0f - f*3.0f + cheekShift*0.4f, -14.0f);

            addQuadBezier(path, crownL, HPt(-4 + cheekShift*0.2f, -33.5f - f*3.5f + crownDrop), crownT);
            addQuadBezier(path, crownT, HPt(5 + cheekShift*0.2f, -33.5f - f*3.5f + crownDrop), crownR);
            addQuadBezier(path, crownR, HPt(29 + f*2 + cheekShift*0.3f, -29 + crownDrop), rT);
            addQuadBezier(path, rT, HPt(45.5f + f*7.5f + cheekShift*0.4f, -7), rC1);
            addQuadBezier(path, rC1, HPt(46.5f + f*7.5f + cheekShift*0.4f, 7), rCI);
            addQuadBezier(path, rCI, HPt(49.5f + f*10 + cheekShift*0.35f, 13), rC2);
            addQuadBezier(path, rC2, HPt(46.5f + f*8 + cheekShift*0.3f, 25 + f*2), rN);
            addQuadBezier(path, rN, BPt(52 + f*7.5f, -62), rF1);
            addQuadBezier(path, rF1, BPt(53 + f*7.5f, -42), rFI);
            addQuadBezier(path, rFI, BPt(55.5f + f*8, -25), rH);
            path.AddBezier(PointF(rH.x, rH.y), B(52 + f*6.5f, 6), B(40 + f*4.5f, 12.5f), rBot);
            path.AddLine(rBot, lBot);
            path.AddBezier(lBot, B(-40 - f*4.5f, 12.5f), B(-52 - f*6.5f, 6), PointF(lH.x, lH.y));
            addQuadBezier(path, lH, BPt(-55.5f - f*8, -25), lFI);
            addQuadBezier(path, lFI, BPt(-53 - f*7.5f, -42), lF1);
            addQuadBezier(path, lF1, BPt(-52 - f*7.5f, -62), lN);
            addQuadBezier(path, lN, HPt(-46.5f - f*8 + cheekShift*0.3f, 25 + f*2), lC2);
            addQuadBezier(path, lC2, HPt(-49.5f - f*10 + cheekShift*0.35f, 13), lCI);
            addQuadBezier(path, lCI, HPt(-46.5f - f*7.5f + cheekShift*0.4f, 7), lC1);
            addQuadBezier(path, lC1, HPt(-45.5f - f*7.5f + cheekShift*0.4f, -7), lT);
            addQuadBezier(path, lT, HPt(-29 - f*2 + cheekShift*0.3f, -29 + crownDrop), crownL);
            path.CloseFigure();
        } else {
            float leftCheekX = -42.5f + cheekShift * 0.4f;
            float rightCheekX = 42.5f + cheekShift * 0.4f;
            PointF crown  = H(cheekShift * 0.2f, -30.0f + crownDrop);
            PointF rCheek = H(rightCheekX, 5.0f);
            PointF rHip   = B(49.0f, -14.0f);
            PointF rBot   = B(24.0f, 12.0f);
            PointF lBot   = B(-24.0f, 12.0f);
            PointF lHip   = B(-49.0f, -14.0f);
            PointF lCheek = H(leftCheekX, 5.0f);

            path.AddBezier(crown, H(26.0f + cheekShift * 0.3f, -30.0f + crownDrop), H(rightCheekX + 1.5f, -14.0f), rCheek);
            path.AddBezier(rCheek, H(rightCheekX - 2.5f, 24.0f), B(51.5f, -48.0f + breath * 0.5f), rHip);
            path.AddBezier(rHip, B(47.0f, 5.0f), B(36.0f, 12.0f), rBot);
            path.AddLine(rBot, lBot);
            path.AddBezier(lBot, B(-36.0f, 12.0f), B(-47.0f, 5.0f), lHip);
            path.AddBezier(lHip, B(-51.5f, -48.0f + breath * 0.5f), H(leftCheekX + 2.5f, 24.0f), lCheek);
            path.AddBezier(lCheek, H(leftCheekX - 1.5f, -14.0f), H(-26.0f + cheekShift * 0.3f, -30.0f + crownDrop), crown);
            path.CloseFigure();
        }

        GraphicsState cs = g.Save();
        g.SetClip(&path);

        // Base coat fill
        if (app.isDarkCoat()) {
            SolidBrush b(toGdi(app.primaryColor));
            g.FillPath(&b, &path);
        } else {
            Color cTop = toGdi(app.primaryColor);
            Color cBot = toGdi(app.primaryColor.darkened(0.09f));
            LinearGradientBrush bodyGrad(PointF(seatX, headCenter.y - 54.0f), PointF(seatX, seatY + 38.0f), cTop, cBot);
            bodyGrad.SetWrapMode(WrapModeTileFlipXY);
            Color bodyCols[4] = { cTop, cTop, cBot, cBot };
            REAL bodyPos[4] = { 0.0f, 0.22f, 0.80f, 1.0f };
            bodyGrad.SetInterpolationColors(bodyCols, bodyPos, 4);
            g.FillPath(&bodyGrad, &path);
        }

        // Clipped fur pattern markings
        float yawRad = yaw * 0.50f, pitchRad = pitch * 0.36f;
        if (app.pattern == FurPattern::Colorpoint) {
            Pt maskC = projectHead3D(0.0f, 2.5f, 27.0f, yawRad, pitchRad);
            float maskSX = std::max(0.76f, std::cos(yawRad * 0.7f)) * 1.18f;
            float maskSY = std::max(0.82f, std::cos(pitchRad * 0.7f)) * 0.88f;
            GraphicsState ms = g.Save();
            g.TranslateTransform(headCenter.x, headCenter.y);
            g.RotateTransform(hTilt * RadToDeg);
            g.TranslateTransform(maskC.x, maskC.y);
            g.ScaleTransform(maskSX, maskSY);
            GraphicsPath maskEllipse;
            maskEllipse.AddEllipse(-31.0f, -31.0f, 62.0f, 62.0f);
            PathGradientBrush maskBrush(&maskEllipse);
            Color cols[4] = { toGdi(app.tertiaryColor, 0), toGdi(app.tertiaryColor, 180), toGdi(app.secondaryColor, 244), toGdi(app.secondaryColor, 255) };
            REAL pos[4] = { 0.0f, 0.26f, 0.56f, 1.0f };
            maskBrush.SetInterpolationColors(cols, pos, 4);
            g.FillPath(&maskBrush, &maskEllipse);
            g.Restore(ms);
        } else if (app.pattern == FurPattern::Tuxedo) {
            SolidBrush bibB(toGdi(app.secondaryColor));
            GraphicsPath bib;
            Pt cTop = HPt(yaw * 5.0f, 22.0f), bR = BPt(22, -32), bBot = BPt(0, 14), bL = BPt(-22, -32);
            addQuadBezier(bib, cTop, HPt(20 + yaw*4, 34), bR);
            addQuadBezier(bib, bR, BPt(26, -4), bBot);
            addQuadBezier(bib, bBot, BPt(-26, -4), bL);
            addQuadBezier(bib, bL, HPt(-20 + yaw*4, 34), cTop);
            bib.CloseFigure();
            g.FillPath(&bibB, &bib);

            GraphicsState ms = g.Save();
            g.TranslateTransform(headCenter.x, headCenter.y);
            g.RotateTransform(hTilt * RadToDeg);
            Pt muz = projectHead3D(0.0f, 14.0f, 27.0f, yawRad, pitchRad);
            g.FillEllipse(&bibB, muz.x - 16, muz.y - 8, 32, 19);
            g.Restore(ms);
        } else if (app.pattern == FurPattern::Tabby) {
            SolidBrush bellyB(toGdi(app.tertiaryColor, 190));
            PointF bc = B(0, -18);
            g.FillEllipse(&bellyB, bc.X - 24, bc.Y - 26, 48, 58);

            for (float side : {-1.0f, 1.0f}) {
                for (int idx = 0; idx < 3; ++idx) {
                    float yOff = -44.0f + idx * 16.0f;
                    Pen sp(toGdi(app.secondaryColor, 214), 5.4f - idx * 0.4f);
                    sp.SetStartCap(LineCapRound); sp.SetEndCap(LineCapRound);
                    GraphicsPath gp;
                    addQuadBezier(gp, BPt(side * 58, yOff), BPt(side * 38, yOff - 4), BPt(side * 24, yOff + 5));
                    g.DrawPath(&sp, &gp);
                }
            }
            GraphicsState ms = g.Save();
            g.TranslateTransform(headCenter.x, headCenter.y);
            g.RotateTransform(hTilt * RadToDeg);
            Pen mp(toGdi(app.secondaryColor, 224), 2.8f);
            mp.SetStartCap(LineCapRound); mp.SetEndCap(LineCapRound);
            for (float dx : {-7.5f, 0.0f, 7.5f}) {
                Pt tP = projectHead3D(dx * 1.1f, -25.0f, 22.0f, yawRad, pitchRad);
                Pt bP = projectHead3D(dx * 0.75f, -14.5f, 26.0f, yawRad, pitchRad);
                g.DrawLine(&mp, tP.x, tP.y, bP.x, bP.y);
            }
            Pen cp(toGdi(app.secondaryColor, 220), 2.5f);
            cp.SetStartCap(LineCapRound); cp.SetEndCap(LineCapRound);
            for (float sign : {-1.0f, 1.0f}) {
                for (float ry : {4.0f, 10.5f}) {
                    Pt p0 = projectHead3D(sign * 39.0f, ry - 1.5f, 10.0f, yawRad, pitchRad);
                    Pt p1 = projectHead3D(sign * 25.0f, ry + 1.5f, 22.0f, yawRad, pitchRad);
                    g.DrawLine(&cp, p0.x, p0.y, p1.x, p1.y);
                }
            }
            g.Restore(ms);
        } else if (app.pattern == FurPattern::Calico) {
            SolidBrush p1(toGdi(app.secondaryColor)), p2(toGdi(app.tertiaryColor));
            GraphicsState ms = g.Save();
            g.TranslateTransform(headCenter.x, headCenter.y);
            g.RotateTransform(hTilt * RadToDeg);
            Pt pL = projectHead3D(-22.0f, -15.0f, 18.0f, yawRad, pitchRad);
            g.FillEllipse(&p1, pL.x - 24, pL.y - 20, 44, 38);
            Pt pR = projectHead3D(24.0f, -12.0f, 17.0f, yawRad, pitchRad);
            g.FillEllipse(&p2, pR.x - 20, pR.y - 18, 42, 34);
            g.Restore(ms);
            PointF hp1 = B(32, -26), hp2 = B(-34, -10);
            g.FillEllipse(&p1, hp1.X - 24, hp1.Y - 22, 48, 42);
            g.FillEllipse(&p2, hp2.X - 22, hp2.Y - 18, 44, 36);
        } else if (app.pattern == FurPattern::Spotted) {
            SolidBrush sb(toGdi(app.secondaryColor));
            GraphicsState ms = g.Save();
            g.TranslateTransform(headCenter.x, headCenter.y);
            g.RotateTransform(hTilt * RadToDeg);
            Pt s1 = projectHead3D(-18, -17, 20, yawRad, pitchRad);
            Pt s2 = projectHead3D(20, -14, 19, yawRad, pitchRad);
            g.FillEllipse(&sb, s1.x - 12, s1.y - 10, 24, 20);
            g.FillEllipse(&sb, s2.x - 9, s2.y - 8, 18, 15);
            g.Restore(ms);
            const float spots[4][4] = { {-30,-34,24,20}, {28,-36,20,18}, {34,-8,26,22}, {-24,-4,18,16} };
            for (auto& sp : spots) {
                PointF pt = B(sp[0], sp[1]);
                g.FillEllipse(&sb, pt.X - sp[2]*0.5f, pt.Y - sp[3]*0.5f, sp[2], sp[3]);
            }
        }

        // Soft layered chest mane for long-fur cats (fades smoothly from upper neck!)
        if (longFur) {
            GraphicsState ms = g.Save();
            g.TranslateTransform(seatX * 0.45f + headCenter.x * 0.55f, headCenter.y + 34.0f + breath * 0.45f);
            g.RotateTransform((bTilt * 0.65f + hTilt * 0.35f) * RadToDeg);
            float mw = 26.0f + f * 14.0f, mh = 15.0f + f * 18.0f;
            RGBColor mCol = (app.pattern == FurPattern::Tuxedo) ? app.secondaryColor
                : ((app.pattern == FurPattern::Tabby) ? app.tertiaryColor : app.primaryColor.lightened(app.isDarkCoat() ? 0.08f : 0.22f));
            GraphicsPath mane;
            addQuadBezier(mane, {-mw, -10}, {-mw*0.92f, mh*0.35f}, {-mw*0.48f + swayX*0.5f, mh*0.72f + swayY*0.5f});
            addQuadBezier(mane, {-mw*0.48f + swayX*0.5f, mh*0.72f + swayY*0.5f}, {-mw*0.18f + swayX*0.65f, mh*0.92f}, {swayX*0.85f, mh + swayY*0.85f});
            addQuadBezier(mane, {swayX*0.85f, mh + swayY*0.85f}, {mw*0.18f + swayX*0.65f, mh*0.92f}, {mw*0.48f + swayX*0.5f, mh*0.72f + swayY*0.5f});
            addQuadBezier(mane, {mw*0.48f + swayX*0.5f, mh*0.72f + swayY*0.5f}, {mw*0.92f, mh*0.35f}, {mw, -10});
            mane.CloseFigure();
            LinearGradientBrush mg(PointF(0, -10), PointF(0, mh + 2), toGdi(mCol, 0), toGdi(mCol, 240));
            g.FillPath(&mg, &mane);
            g.Restore(ms);
        }

        g.Restore(cs);

        if (!app.isDarkCoat()) {
            Pen outPen(outlineFor(app), 1.5f);
            g.DrawPath(&outPen, &path);
        }

        // Tucked hind paws at bottom
        GraphicsState ps = g.Save();
        g.TranslateTransform(seatX, seatY);
        g.RotateTransform(bTilt * RadToDeg);
        g.ScaleTransform(sx, sy);

        RGBColor hpCol = (app.pattern == FurPattern::Colorpoint || app.pattern == FurPattern::Tuxedo) ? app.secondaryColor : app.primaryColor;
        SolidBrush pawBrush(toGdi(hpCol));
        g.FillEllipse(&pawBrush, -35.0f, 3.0f, 17.0f, 11.0f);
        if (physics.hindFootActive.value < 0.35f) {
            g.FillEllipse(&pawBrush, 18.0f, 3.0f, 17.0f, 11.0f);
        }

        Pen rimPen(limbSepColor(app, 148), 1.3f);
        rimPen.SetStartCap(LineCapRound); rimPen.SetEndCap(LineCapRound);
        g.DrawArc(&rimPen, -34.0f, 1.0f, 15.0f, 15.0f, 15.0f, 150.0f);
        if (physics.hindFootActive.value < 0.35f) {
            g.DrawArc(&rimPen, 19.0f, 1.0f, 15.0f, 15.0f, 15.0f, 150.0f);
        }
        g.Restore(ps);
    }

    // MARK: - Configurable Necktie / Bow Tie Accessory

    static void fillTieFabric(Gdiplus::Graphics& g, Gdiplus::GraphicsPath& path, float bx, float by, float bw, float bh, const TiePalette& pal, TiePattern pat) {
        using namespace Gdiplus;
        GraphicsState cs = g.Save();
        g.SetClip(&path);
        SolidBrush baseB(toGdi(pal.base));
        g.FillRectangle(&baseB, bx, by, bw, bh);

        if (pat == TiePattern::ScottishGrid) {
            GraphicsState rs = g.Save();
            g.TranslateTransform(bx + bw * 0.5f, by + bh * 0.5f);
            g.RotateTransform(45.0f);
            float span = std::max(bw, bh) * 1.6f, cell = 7.6f;
            SolidBrush darkB(toGdi(pal.dark, 140));
            for (float pos = -span; pos <= span; pos += cell) {
                g.FillRectangle(&darkB, pos, -span, 2.8f, span * 2.0f);
                g.FillRectangle(&darkB, -span, pos, span * 2.0f, 2.8f);
            }
            Pen lightP(toGdi(pal.light, 224), 0.75f);
            for (float pos = -span + cell * 0.5f + 1.4f; pos <= span; pos += cell) {
                g.DrawLine(&lightP, pos, -span, pos, span);
                g.DrawLine(&lightP, -span, pos, span, pos);
            }
            g.Restore(rs);
        } else if (pat == TiePattern::DiagonalStripe) {
            GraphicsState rs = g.Save();
            g.TranslateTransform(bx + bw * 0.5f, by + bh * 0.5f);
            g.RotateTransform(45.0f);
            float span = std::max(bw, bh) * 1.6f;
            SolidBrush darkB(toGdi(pal.dark, 200)), lightB(toGdi(pal.light, 225));
            for (float pos = -span; pos <= span; pos += 7.2f) {
                g.FillRectangle(&darkB, pos, -span, 2.8f, span * 2.0f);
                g.FillRectangle(&lightB, pos + 3.4f, -span, 0.9f, span * 2.0f);
            }
            g.Restore(rs);
        } else if (pat == TiePattern::PolkaDot) {
            SolidBrush dotB(toGdi(pal.light, 232));
            int row = 0;
            for (float y = by - 2.0f; y <= by + bh + 2.0f; y += 4.6f, ++row) {
                float ox = (row % 2 == 0) ? 0.0f : 2.6f;
                for (float x = bx - 2.0f + ox; x <= bx + bw + 2.0f; x += 5.2f) {
                    g.FillEllipse(&dotB, x - 1.1f, y - 1.1f, 2.2f, 2.2f);
                }
            }
        }
        g.Restore(cs);
    }

    static void drawTieAccessory(Gdiplus::Graphics& g, float seatX, Pt headCenter, float breath, const CatPhysics& physics, const CatSettings& settings, const CatAppearance& app) {
        using namespace Gdiplus;
        TiePalette pal = getTiePalette(settings.tieColor);
        float neckX = seatX * 0.45f + headCenter.x * 0.55f + physics.headYaw.value * 4.5f;
        float neckY = headCenter.y + 30.5f + breath * 0.35f;
        float tilt = physics.bodyTilt.value * 0.65f + physics.headTilt.value * 0.35f;
        Color outCol = app.isDarkCoat() ? Color(218, 12, 12, 14) : outlineFor(app);

        GraphicsState st = g.Save();
        g.TranslateTransform(neckX, neckY);
        g.RotateTransform(tilt * RadToDeg);

        // Collar band
        GraphicsPath collar;
        addQuadBezier(collar, {-24.5f, -3.5f}, {0, 4.5f}, {24.5f, -3.5f});
        collar.AddLine(24.5f, -3.5f, 23.0f, 1.5f);
        addQuadBezier(collar, {23.0f, 1.5f}, {0, 8.8f}, {-23.0f, 1.5f});
        collar.CloseFigure();
        fillTieFabric(g, collar, -26, -6, 52, 18, pal, settings.tiePattern);
        Pen outPen(outCol, 1.05f);
        g.DrawPath(&outPen, &collar);

        if (settings.tieStyle == TieStyle::Necktie) {
            PointF bladePts[5] = { {-3.6f,5.5f}, {3.6f,5.5f}, {8.2f,27.0f}, {0.0f,35.5f}, {-8.2f,27.0f} };
            GraphicsPath blade;
            blade.AddPolygon(bladePts, 5);
            fillTieFabric(g, blade, -10, 4, 20, 34, pal, settings.tiePattern);
            g.DrawPath(&outPen, &blade);

            GraphicsPath knot;
            addQuadBezier(knot, {-5.4f,-1.0f}, {0,-2.4f}, {5.4f,-1.0f});
            knot.AddLine(5.4f,-1.0f, 3.8f,6.4f);
            addQuadBezier(knot, {3.8f,6.4f}, {0,7.4f}, {-3.8f,6.4f});
            knot.CloseFigure();
            fillTieFabric(g, knot, -7, -3, 14, 12, pal, settings.tiePattern);
            g.DrawPath(&outPen, &knot);
        } else {
            for (float sign : {-1.0f, 1.0f}) {
                GraphicsPath wing;
                addQuadBezier(wing, {sign*3.0f, 0.2f}, {sign*10.2f, -4.8f}, {sign*16.5f, -5.2f});
                addQuadBezier(wing, {sign*16.5f, -5.2f}, {sign*19.2f, -1.0f}, {sign*17.5f, 3.2f});
                addQuadBezier(wing, {sign*17.5f, 3.2f}, {sign*18.6f, 8.2f}, {sign*15.2f, 11.0f});
                addQuadBezier(wing, {sign*15.2f, 11.0f}, {sign*9.5f, 10.6f}, {sign*3.0f, 5.8f});
                wing.CloseFigure();
                fillTieFabric(g, wing, sign > 0 ? 1.0f : -20.0f, -7.0f, 19.0f, 20.0f, pal, settings.tiePattern);
                g.DrawPath(&outPen, &wing);
            }
            GraphicsPath bk;
            addRoundedRect(bk, -4.4f, -1.6f, 8.8f, 9.4f, 3.2f);
            fillTieFabric(g, bk, -6, -3, 12, 12, pal, settings.tiePattern);
            g.DrawPath(&outPen, &bk);
        }
        g.Restore(st);
    }

    // MARK: - 3rd Key Hind Foot

    static void drawHindFoot(Gdiplus::Graphics& g, float seatX, float seatY, const CatPhysics& physics, const CatAppearance& app) {
        Pt hip = { seatX + 26.0f, seatY + 2.0f };
        Pt target = physics.hindFoot.point();
        Pt mid = { (hip.x + target.x) * 0.5f + 10.0f, (hip.y + target.y) * 0.5f - 8.0f };
        drawLimb(g, hip, mid, target, 15.0f, 12.0f, true, 0.85f * physics.hindFootActive.value, app);
    }

    // MARK: - 2.5D Eyes & Whiskers

    static void drawHeadFeatures(Gdiplus::Graphics& g, Pt center, const CatPhysics& physics, const CatAppearance& app) {
        using namespace Gdiplus;
        GraphicsState st = g.Save();
        g.TranslateTransform(center.x, center.y);
        g.RotateTransform(physics.headTilt.value * RadToDeg);

        float yawRad = physics.headYaw.value * 0.50f;
        float pitchRad = physics.headPitch.value * 0.36f;

        drawEye3D(g, true, yawRad, pitchRad, physics, app);
        drawEye3D(g, false, yawRad, pitchRad, physics, app);
        drawWhiskers3D(g, yawRad, pitchRad, physics, app);
        g.Restore(st);
    }

    static void drawEye3D(Gdiplus::Graphics& g, bool isLeft, float yawRad, float pitchRad, const CatPhysics& physics, const CatAppearance& app) {
        using namespace Gdiplus;
        float sign = isLeft ? -1.0f : 1.0f;
        Color eyeCol = toGdi(app.eyeColor);
        Pt proj = projectHead3D(sign * 17.2f, -2.0f, 27.5f, yawRad, pitchRad);

        float eyeNormal = yawRad + sign * 0.34f;
        float foreX = std::clamp(std::cos(eyeNormal) / std::cos(0.34f), 0.64f, 1.06f);
        float foreY = std::clamp(std::cos(pitchRad * 0.85f), 0.78f, 1.03f);

        GraphicsState st = g.Save();
        g.TranslateTransform(proj.x, proj.y);
        g.ScaleTransform(foreX, foreY);

        // Mode 1: Happy closed glowing curved line eyes (petting head!)
        if (physics.isHappyClosedEyes()) {
            GraphicsPath hp;
            addQuadBezier(hp, {-11.5f, 1.0f}, {sign * 1.5f, 3.4f}, {11.5f, 1.0f});
            Pen p(eyeCol, 2.6f);
            p.SetStartCap(LineCapRound); p.SetEndCap(LineCapRound);
            g.DrawPath(&p, &hp);
            g.Restore(st);
            return;
        }

        // Mode 2: Blissful half-squint glowing slits (petting body!)
        if (physics.isBlissfulSquint()) {
            GraphicsPath sp;
            addQuadBezier(sp, {-11.5f, -0.5f}, {0.0f, 0.6f}, {11.5f, -0.5f});
            addQuadBezier(sp, {11.5f, -0.5f}, {0.0f, 4.8f}, {-11.5f, -0.5f});
            sp.CloseFigure();
            SolidBrush sb(eyeCol);
            g.FillPath(&sb, &sp);
            g.Restore(st);
            return;
        }

        // Mode 3: Peaceful Sleeping Eyes (idle / late-night nap!)
        if (physics.isSleeping()) {
            float sa = std::min(1.0f, (physics.sleepiness - 0.65f) / 0.25f);
            float faceLum = (app.pattern == FurPattern::Colorpoint) ? app.secondaryColor.luminance() : app.primaryColor.luminance();
            Color lidCol = (faceLum < 0.35f) ? contourMint((BYTE)(215 * sa)) : toGdi(app.primaryColor.darkened(0.65f), (BYTE)(210 * sa));
            GraphicsPath sp;
            addQuadBezier(sp, {-10.5f, 1.5f}, {0.0f, 7.2f}, {10.5f, 1.5f});
            Pen p(lidCol, 2.3f);
            p.SetStartCap(LineCapRound); p.SetEndCap(LineCapRound);
            g.DrawPath(&p, &sp);
            g.Restore(st);
            return;
        }

        float hunt = std::clamp(physics.huntIntensity.value, 0.0f, 1.0f);
        float tired = physics.effectiveTiredness();
        g.RotateTransform(sign * (0.06f * (1.0f - hunt * 0.6f) - tired * 0.04f) * RadToDeg);

        float rx = 12.0f + hunt * 1.1f;
        float ry = 10.8f + hunt * 1.8f;

        GraphicsPath eyeClip;
        eyeClip.AddEllipse(-rx, -ry, rx * 2.0f, ry * 2.0f);
        GraphicsState cs = g.Save();
        g.SetClip(&eyeClip);

        SolidBrush irisBrush(eyeCol);
        g.FillRectangle(&irisBrush, -rx - 1.0f, -ry - 1.0f, rx * 2.0f + 2.0f, ry * 2.0f + 2.0f);

        Pt gaze = physics.eyeGaze.point();
        float px = gaze.x * (4.2f - hunt * 1.2f);
        float py = gaze.y * (3.6f - hunt * 1.0f) + tired * 1.2f;
        float pScale = physics.pupilScale.value;
        float normalW = 5.0f * pScale;
        float normalH = 13.5f * std::min(1.12f, pScale);
        float huntDiam = 18.8f;
        float pupilW = normalW + (huntDiam - normalW) * hunt;
        float pupilH = normalH + (huntDiam - normalH) * hunt;

        SolidBrush pupilBrush(catBlack());
        g.FillEllipse(&pupilBrush, px - pupilW * 0.5f, py - pupilH * 0.5f, pupilW, pupilH);

        if (hunt > 0.25f) {
            BYTE ga = (BYTE)(std::min(1.0f, (hunt - 0.25f) / 0.55f) * 235.0f);
            float gr = 2.1f + hunt * 0.9f;
            SolidBrush gb(Color(ga, 255, 255, 255));
            g.FillEllipse(&gb, px - pupilW * 0.22f - gr * 0.5f, py - pupilH * 0.22f - gr * 0.5f, gr * 2.0f, gr * 2.0f);
        }

        // Eyelid closure + heavy 0-6AM tired upper eyelid droop!
        float closure = std::max(physics.effectiveEyeClosure(), tired * 0.36f);
        if (closure > 0.02f) {
            float lidY = -ry + (ry * 2.15f) * closure;
            float slant = tired * 1.8f * sign;
            GraphicsPath lp;
            lp.AddLine(-rx - 2, -ry - 2, rx + 2, -ry - 2);
            lp.AddLine(rx + 2, -ry - 2, rx + 2, lidY + slant);
            addQuadBezier(lp, {rx + 2, lidY + slant}, {0, lidY + tired * 1.6f}, {-rx - 2, lidY - slant});
            lp.CloseFigure();
            RGBColor faceCol = (app.pattern == FurPattern::Colorpoint) ? app.secondaryColor : app.primaryColor;
            SolidBrush lb(toGdi(faceCol));
            g.FillPath(&lb, &lp);
        }

        g.Restore(cs);

        if (!app.isDarkCoat() && app.pattern != FurPattern::Colorpoint) {
            Pen ep(outlineFor(app, 110), 1.0f);
            g.DrawEllipse(&ep, -rx, -ry, rx * 2.0f, ry * 2.0f);
        }

        // 0-6AM tired under-eye bags
        if (tired > 0.15f) {
            Color bc = app.isDarkCoat()
                ? Color((BYTE)(112 * tired), 133, 122, 163)
                : Color((BYTE)(115 * tired), 87, 61, 92);
            Pen bp(bc, 1.45f);
            bp.SetStartCap(LineCapRound); bp.SetEndCap(LineCapRound);
            GraphicsPath bag;
            addQuadBezier(bag, {-rx * 0.72f, ry * 0.92f}, {0, ry + 4.0f}, {rx * 0.72f, ry * 0.92f});
            g.DrawPath(&bp, &bag);
        }

        g.Restore(st);
    }

    static void drawWhiskers3D(Gdiplus::Graphics& g, float yawRad, float pitchRad, const CatPhysics& physics, const CatAppearance& app) {
        using namespace Gdiplus;
        float wiggle = std::sin(physics.time * 4.5f) * (std::max(physics.petHeadIntensity, physics.petBodyIntensity) * 1.2f);
        float faceLum = (app.pattern == FurPattern::Colorpoint) ? app.secondaryColor.luminance() : app.primaryColor.luminance();
        Color wCol = (faceLum < 0.35f) ? whiskerWhite() : toGdi(app.primaryColor.darkened(0.52f), 174);
        Pen pen(wCol, 1.05f);
        pen.SetStartCap(LineCapRound); pen.SetEndCap(LineCapRound);

        const float rows[3][3] = {
            { 10.5f, 36.5f, 8.8f + wiggle },
            { 14.2f, 37.8f, 14.2f + wiggle * 0.5f },
            { 18.0f, 35.5f, 19.6f - wiggle * 0.4f }
        };

        for (float sign : {-1.0f, 1.0f}) {
            for (int i = 0; i < 3; ++i) {
                Pt p0 = projectHead3D(sign * 24.0f, rows[i][0], 23.0f, yawRad, pitchRad);
                Pt p2 = projectHead3D(sign * rows[i][1], rows[i][2], 14.0f, yawRad, pitchRad);
                Pt ctrl = { (p0.x + p2.x) * 0.5f, (p0.y + p2.y) * 0.5f - 0.8f };
                GraphicsPath wp;
                addQuadBezier(wp, p0, ctrl, p2);
                g.DrawPath(&pen, &wp);
            }
        }
    }

    // MARK: - Front Paws

    static void drawFrontPaws(Gdiplus::Graphics& g, float seatX, float seatY, float breath, const CatPhysics& physics, const CatAppearance& app) {
        Pt lPos = physics.leftPaw.point();
        Pt rPos = physics.rightPaw.point();

        float lDist = std::hypot(lPos.x - CatPhysics::LeftPawRest.x, lPos.y - CatPhysics::LeftPawRest.y);
        float rDist = std::hypot(rPos.x - CatPhysics::RightPawRest.x, rPos.y - CatPhysics::RightPawRest.y);

        Pt leftShoulder  = { seatX - 24.0f, seatY - 56.0f + breath };
        Pt rightShoulder = { seatX + 24.0f, seatY - 56.0f + breath };
        float sw = 19.0f + app.furLength * 3.0f;

        if (lDist < 6.0f && !physics.leftPawOnMouse && !physics.leftPawTyping) {
            drawIdleFrontLeg(g, { seatX - 18.0f, seatY - 30.0f }, { seatX - 16.0f, seatY + 12.0f }, true, app);
        } else {
            Pt mid = { (leftShoulder.x + lPos.x) * 0.5f - (physics.leftPawOnMouse ? 8.0f : 4.0f),
                       (leftShoulder.y + lPos.y) * 0.5f - 6.0f };
            drawLimb(g, leftShoulder, mid, lPos, sw, 13.5f, false, 0.78f, app);
        }

        if (rDist < 6.0f && !physics.rightPawTyping) {
            drawIdleFrontLeg(g, { seatX + 18.0f, seatY - 30.0f }, { seatX + 16.0f, seatY + 12.0f }, false, app);
        } else {
            Pt mid = { (rightShoulder.x + rPos.x) * 0.5f + 4.0f, (rightShoulder.y + rPos.y) * 0.5f - 6.0f };
            drawLimb(g, rightShoulder, mid, rPos, sw, 13.5f, true, 0.78f, app);
        }
    }

    static void drawIdleFrontLeg(Gdiplus::Graphics& g, Pt top, Pt bottom, bool isLeft, const CatAppearance& app) {
        using namespace Gdiplus;
        float sign = isLeft ? -1.0f : 1.0f;

        if (app.pattern == FurPattern::Colorpoint) {
            GraphicsPath lp;
            addRoundedRect(lp, bottom.x - 7.5f, top.y, 15.0f, bottom.y - top.y + 1.0f, 6.5f);
            float pad = 10.0f, span = std::max(1.0f, (bottom.y + 2.0f) - top.y), total = span + pad * 2.0f;
            LinearGradientBrush grad(PointF(bottom.x, top.y - pad), PointF(bottom.x, bottom.y + 2.0f + pad), toGdi(app.primaryColor, 0), toGdi(app.secondaryColor, 255));
            grad.SetWrapMode(WrapModeTileFlipXY);
            Color cols[5] = { toGdi(app.primaryColor, 0), toGdi(app.primaryColor, 0), toGdi(app.tertiaryColor, 190), toGdi(app.secondaryColor, 255), toGdi(app.secondaryColor, 255) };
            REAL pos[5] = { 0.0f, pad / total, (pad + span * 0.52f) / total, (pad + span * 0.85f) / total, 1.0f };
            grad.SetInterpolationColors(cols, pos, 5);
            g.FillPath(&grad, &lp);
        } else if (app.pattern == FurPattern::Tuxedo) {
            SolidBrush mb(toGdi(app.secondaryColor));
            g.FillEllipse(&mb, bottom.x - 7.2f, bottom.y - 11.0f, 14.4f, 11.5f);
        }

        Pen p(limbSepColor(app, 185), 1.45f);
        p.SetStartCap(LineCapRound); p.SetEndCap(LineCapRound);

        GraphicsPath p1;
        addQuadBezier(p1, { top.x + sign * 8.5f, top.y }, { top.x + sign * 9.5f, (top.y + bottom.y) * 0.5f }, { bottom.x + sign * 7.5f, bottom.y - 1.0f });
        g.DrawPath(&p, &p1);

        GraphicsPath p2;
        addQuadBezier(p2, { top.x - sign * 7.0f, top.y + 4.0f }, { top.x - sign * 6.5f, (top.y + bottom.y) * 0.5f }, { bottom.x - sign * 6.0f, bottom.y - 1.0f });
        g.DrawPath(&p, &p2);
    }

    static void drawLimb(Gdiplus::Graphics& g, Pt start, Pt ctrl, Pt end, float startW, float endW, bool outlineOnLeft, float outlineAlpha, const CatAppearance& app) {
        using namespace Gdiplus;
        constexpr int steps = 14;
        std::vector<PointF> leftEdge, rightEdge;
        leftEdge.reserve(steps + 1);
        rightEdge.reserve(steps + 1);

        for (int i = 0; i <= steps; ++i) {
            float t = (float)i / (float)steps;
            Pt p = quadPoint(start, ctrl, end, t);
            Pt tan = quadTangent(start, ctrl, end, t);
            float len = std::max(0.001f, std::hypot(tan.x, tan.y));
            float nx = -tan.y / len, ny = tan.x / len;
            float hw = (startW + (endW - startW) * t) * 0.5f;
            leftEdge.push_back(PointF(p.x + nx * hw, p.y + ny * hw));
            rightEdge.push_back(PointF(p.x - nx * hw, p.y - ny * hw));
        }

        std::vector<PointF> poly = leftEdge;
        for (int i = steps; i >= 0; --i) poly.push_back(rightEdge[i]);

        GraphicsPath limbPath;
        limbPath.AddPolygon(poly.data(), (INT)poly.size());

        float pawR = endW * 0.58f;
        RectF pawRect(end.x - pawR, end.y - pawR * 0.85f, pawR * 2.0f, pawR * 1.7f);

        if (app.pattern == FurPattern::Colorpoint) {
            float dx = end.x - start.x, dy = end.y - start.y;
            float dist = std::max(1.0f, std::hypot(dx, dy));
            float ux = dx / dist, uy = dy / dist;
            float padStart = startW + 18.0f, padEnd = endW + 18.0f, totalLen = padStart + dist + padEnd;
            PointF gStart(start.x - ux * padStart, start.y - uy * padStart);
            PointF gEnd(end.x + ux * padEnd, end.y + uy * padEnd);
            LinearGradientBrush grad(gStart, gEnd, toGdi(app.primaryColor, 0), toGdi(app.secondaryColor, 255));
            grad.SetWrapMode(WrapModeTileFlipXY);
            Color cols[6] = { toGdi(app.primaryColor, 0), toGdi(app.primaryColor, 0), toGdi(app.primaryColor, 255), toGdi(app.tertiaryColor, 255), toGdi(app.secondaryColor, 255), toGdi(app.secondaryColor, 255) };
            REAL pos[6] = { 0.0f, padStart / totalLen, (padStart + dist * 0.16f) / totalLen, (padStart + dist * 0.48f) / totalLen, (padStart + dist * 0.78f) / totalLen, 1.0f };
            grad.SetInterpolationColors(cols, pos, 6);
            g.FillPath(&grad, &limbPath);
            SolidBrush pawBrush(toGdi(app.secondaryColor));
            g.FillEllipse(&pawBrush, pawRect);
        } else if (app.pattern == FurPattern::Tuxedo) {
            SolidBrush b(toGdi(app.primaryColor)), pb(toGdi(app.secondaryColor));
            g.FillPath(&b, &limbPath);
            g.FillEllipse(&pb, pawRect);
        } else {
            SolidBrush b(toGdi(app.primaryColor));
            g.FillPath(&b, &limbPath);
            g.FillEllipse(&b, pawRect);
        }

        if (!app.isDarkCoat()) {
            const auto& outerEdge = outlineOnLeft ? rightEdge : leftEdge;
            Pen op(outlineFor(app, 184), 1.25f);
            op.SetStartCap(LineCapRound); op.SetEndCap(LineCapRound); op.SetLineJoin(LineJoinRound);
            g.DrawLines(&op, outerEdge.data() + 3, (INT)outerEdge.size() - 4);
        }

        const auto& hiEdge = outlineOnLeft ? leftEdge : rightEdge;
        int startIdx = 2;
        int endIdx = (int)((hiEdge.size() - 1) * 0.68f);
        if (endIdx > startIdx) {
            Pen hp(limbSepColor(app, (BYTE)(outlineAlpha * 215)), 1.35f);
            hp.SetStartCap(LineCapRound); hp.SetEndCap(LineCapRound); hp.SetLineJoin(LineJoinRound);
            g.DrawLines(&hp, hiEdge.data() + startIdx, endIdx - startIdx + 1);
        }
    }

    // MARK: - Floating Mechanical Keycaps

    static void drawFloatingKeycaps(Gdiplus::Graphics& g, const CatPhysics& physics) {
        using namespace Gdiplus;
        FontFamily ff(L"Segoe UI");
        StringFormat sf;
        sf.SetAlignment(StringAlignmentCenter);
        sf.SetLineAlignment(StringAlignmentCenter);

        for (const auto& b : physics.floatingKeycaps) {
            float prog = b.age / b.lifetime;
            float scale = 1.0f;
            if (b.age < 0.09f) {
                scale = 0.72f + 0.38f * std::sin((b.age / 0.09f) * 3.14159f * 0.65f);
            } else if (b.age < 0.18f) {
                scale = 1.10f - 0.10f * ((b.age - 0.09f) / 0.09f);
            }

            float alphaF = prog < 0.62f ? 1.0f : std::max(0.0f, 1.0f - (prog - 0.62f) / 0.38f);
            BYTE a = (BYTE)(alphaF * 255.0f);
            if (a < 4) continue;

            size_t len = b.label.size();
            float w = len <= 1 ? 23.0f : (len == 2 ? 30.0f : 38.0f);
            float h = 22.0f;

            GraphicsState st = g.Save();
            g.TranslateTransform(b.position.x, b.position.y);
            g.RotateTransform(b.rotation * RadToDeg);
            g.ScaleTransform(scale, scale);

            GraphicsPath basePath;
            addRoundedRect(basePath, -w * 0.5f, -h * 0.5f + 2.5f, w, h, 5.5f);
            SolidBrush baseBrush(Color((BYTE)(alphaF * 242), 38, 38, 43));
            g.FillPath(&baseBrush, &basePath);

            GraphicsPath facePath;
            addRoundedRect(facePath, -w * 0.5f, -h * 0.5f, w, h, 5.2f);
            SolidBrush faceBrush(Color(a, 249, 248, 243));
            Pen facePen(Color(a, 41, 41, 46), 1.45f);
            g.FillPath(&faceBrush, &facePath);
            g.DrawPath(&facePen, &facePath);

            Font font(&ff, len <= 1 ? 11.0f : 9.2f, FontStyleBold, UnitPixel);
            SolidBrush txtBrush(Color(a, 31, 31, 36));
            g.DrawString(b.label.c_str(), -1, &font, RectF(-w * 0.5f, -h * 0.5f, w, h), &sf, &txtBrush);

            g.Restore(st);
        }
    }

    // MARK: - Petting Sparkles & Sleep Z

    static void drawSparkles(Gdiplus::Graphics& g, const CatPhysics& physics, Gdiplus::Color baseCol) {
        using namespace Gdiplus;
        FontFamily ff(L"Segoe UI");

        for (const auto& sp : physics.sparkles) {
            float p = std::min(1.0f, sp.age / sp.lifetime);
            BYTE a = (BYTE)(std::sin(p * 3.14159f) * 215.0f);
            if (a < 4) continue;

            Color c(a, baseCol.GetR(), baseCol.GetG(), baseCol.GetB());
            if (sp.isSleepZ) {
                float baseSz = sp.isBigSleepZ ? 13.0f : 10.0f;
                float swayX = std::sin(sp.age * 3.0f) * 4.5f;
                Font f(&ff, baseSz + p * 3.5f, FontStyleBold, UnitPixel);
                SolidBrush sb(c);
                g.DrawString(sp.isBigSleepZ ? L"Z" : L"z", -1, &f, PointF(sp.position.x + swayX, sp.position.y), &sb);
            } else {
                float r = 3.5f + p * 1.5f;
                GraphicsState st = g.Save();
                g.TranslateTransform(sp.position.x, sp.position.y);
                GraphicsPath star;
                addQuadBezier(star, {0, -r}, {0.8f, -0.8f}, {r, 0});
                addQuadBezier(star, {r, 0}, {0.8f, 0.8f}, {0, r});
                addQuadBezier(star, {0, r}, {-0.8f, 0.8f}, {-r, 0});
                addQuadBezier(star, {-r, 0}, {-0.8f, -0.8f}, {0, -r});
                star.CloseFigure();
                SolidBrush sb(c);
                g.FillPath(&sb, &star);
                g.Restore(st);
            }
        }
    }
};
