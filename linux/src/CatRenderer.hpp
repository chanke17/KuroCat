#pragma once
#include <cairo.h>
#include <cmath>
#include <vector>
#include <algorithm>
#include "CatPhysics.hpp"

enum class CatHitZone {
    None,
    Head,
    Body
};

struct RGBA {
    double r, g, b, a;
};

class CatRenderer {
public:
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

    static void draw(cairo_t* cr, const CatPhysics& physics, const CatSettings& settings) {
        cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);

        const CatAppearance& app = settings.appearance;
        float breath = physics.currentBreathOffset();
        float seatX = CatPhysics::SeatAnchor.x + physics.bodyShiftX.value;
        float seatY = CatPhysics::SeatAnchor.y;

        Pt headCenter = {
            seatX + physics.bodyTilt.value * 36.0f + physics.headYaw.value * 7.5f,
            126.0f + physics.headOffsetY.value + physics.headPitch.value * 4.8f + breath * 1.1f
        };

        drawMouse(cr, physics, settings.keyboardTheme);
        drawKeyboard(cr, physics, settings.keyboardTheme, toRgba(app.eyeColor));
        if (app.useLongFurPipeline()) drawLongFurTail(cr, seatX, seatY, physics, app);
        else drawTail(cr, seatX, seatY, physics, app);
        drawEarsLayer(cr, headCenter, physics, app);
        drawUnifiedSilhouette(cr, seatX, seatY, headCenter, breath, physics, app);

        if (settings.showTie) {
            drawTieAccessory(cr, seatX, headCenter, breath, physics, settings, app);
        }

        if (physics.hindFootActive.value > 0.03f) {
            drawHindFoot(cr, seatX, seatY, physics, app);
        }

        drawHeadFeatures(cr, headCenter, physics, app);
        drawFrontPaws(cr, seatX, seatY, breath, physics, app);

        if (settings.showKeyBadges) {
            drawFloatingKeycaps(cr, physics);
        }
        drawSparkles(cr, physics, toRgba(app.eyeColor));
    }

private:
    static constexpr double PI = 3.14159265358979323846;

    static constexpr RGBA catBlack     = { 0.085, 0.085, 0.095, 1.0 };
    static constexpr RGBA contourMint  = { 0.82,  0.92,  0.89,  0.76 };
    static constexpr RGBA whiskerWhite = { 0.88,  0.90,  0.92,  0.68 };

    static RGBA toRgba(RGBColor c, double a = 1.0) { return { c.r / 255.0, c.g / 255.0, c.b / 255.0, a }; }
    static RGBA outlineFor(const CatAppearance& app, double a = 0.84) { return toRgba(app.primaryColor.darkened(0.58f), a); }
    static RGBA limbSepColor(const CatAppearance& app, double a = 0.78) {
        return app.isDarkCoat() ? RGBA{contourMint.r, contourMint.g, contourMint.b, a} : toRgba(app.primaryColor.darkened(0.55f), a);
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

    static void setCol(cairo_t* cr, RGBA c, double alphaMul = 1.0) {
        cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a * alphaMul);
    }

    static RGBA blend(RGBA a, RGBA b, double t) {
        t = std::clamp(t, 0.0, 1.0);
        return { a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t };
    }

    static void quadCurveTo(cairo_t* cr, double x0, double y0, double cx, double cy, double x2, double y2) {
        double c1x = x0 + (2.0 / 3.0) * (cx - x0);
        double c1y = y0 + (2.0 / 3.0) * (cy - y0);
        double c2x = x2 + (2.0 / 3.0) * (cx - x2);
        double c2y = y2 + (2.0 / 3.0) * (cy - y2);
        cairo_curve_to(cr, c1x, c1y, c2x, c2y, x2, y2);
    }

    static void roundedRect(cairo_t* cr, double x, double y, double w, double h, double r) {
        r = std::min(r, std::min(w * 0.5, h * 0.5));
        cairo_new_sub_path(cr);
        cairo_arc(cr, x + w - r, y + r, r, -PI * 0.5, 0);
        cairo_arc(cr, x + w - r, y + h - r, r, 0, PI * 0.5);
        cairo_arc(cr, x + r, y + h - r, r, PI * 0.5, PI);
        cairo_arc(cr, x + r, y + r, r, PI, PI * 1.5);
        cairo_close_path(cr);
    }

    static void fillEllipse(cairo_t* cr, double cx, double cy, double rx, double ry) {
        cairo_save(cr);
        cairo_translate(cr, cx, cy);
        cairo_scale(cr, rx, ry);
        cairo_arc(cr, 0, 0, 1.0, 0, PI * 2.0);
        cairo_restore(cr);
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

    static void drawMouse(cairo_t* cr, const CatPhysics& physics, KeyboardTheme theme) {
        Pt center = { CatPhysics::MouseBaseCenter.x + physics.mouseOffset.point().x,
                      CatPhysics::MouseBaseCenter.y + physics.mouseOffset.point().y };
        float pressShift = std::max(physics.mousePressLeft.value, physics.mousePressRight.value) * 1.6f;

        cairo_save(cr);
        cairo_translate(cr, center.x, center.y + pressShift);
        cairo_rotate(cr, 0.22);

        // Shadow
        cairo_new_path(cr);
        fillEllipse(cr, 0, 4.0, 13.5, 15.5);
        cairo_set_source_rgba(cr, 0, 0, 0, 0.24);
        cairo_fill(cr);

        RGBA bodyCol, borderCol, wheelCol;
        if (theme == KeyboardTheme::MidnightHacker) {
            bodyCol = {0.20, 0.21, 0.24, 1.0}; borderCol = {0.08, 0.08, 0.10, 1.0}; wheelCol = {0.78, 0.95, 0.25, 1.0};
        } else if (theme == KeyboardTheme::RetroCream) {
            bodyCol = {0.89, 0.87, 0.82, 1.0}; borderCol = {0.20, 0.19, 0.18, 1.0}; wheelCol = {0.88, 0.42, 0.24, 1.0};
        } else {
            bodyCol = {0.955, 0.950, 0.925, 1.0}; borderCol = {0.14, 0.14, 0.16, 1.0}; wheelCol = {0.96, 0.69, 0.16, 1.0};
        }

        cairo_new_path(cr);
        fillEllipse(cr, 0, 0, 13.5, 16.5);
        setCol(cr, bodyCol);
        cairo_fill_preserve(cr);

        if (physics.mousePressLeft.value > 0.05f || physics.mousePressRight.value > 0.05f) {
            cairo_save(cr);
            cairo_clip(cr);
            if (physics.mousePressLeft.value > 0.05f) {
                cairo_set_source_rgba(cr, 0.79, 0.95, 0.25, 0.38 * physics.mousePressLeft.value);
                cairo_rectangle(cr, 0, 0, 14, 17);
                cairo_fill(cr);
            }
            if (physics.mousePressRight.value > 0.05f) {
                cairo_set_source_rgba(cr, 0.79, 0.95, 0.25, 0.38 * physics.mousePressRight.value);
                cairo_rectangle(cr, -14, 0, 14, 17);
                cairo_fill(cr);
            }
            cairo_restore(cr);
        } else {
            cairo_new_path(cr);
        }

        // Front button split seam pointing away from cat (bottom)
        setCol(cr, borderCol, 0.32);
        cairo_set_line_width(cr, 1.05);
        cairo_move_to(cr, 0, 16.0);
        cairo_line_to(cr, 0, 1.5);
        cairo_stroke(cr);

        // Amber scroll wheel
        roundedRect(cr, -1.9, 2.5, 3.8, 8.5, 1.9);
        setCol(cr, wheelCol);
        cairo_fill(cr);

        // Outer border
        cairo_new_path(cr);
        fillEllipse(cr, 0, 0, 13.5, 16.5);
        setCol(cr, borderCol);
        cairo_set_line_width(cr, 1.7);
        cairo_stroke(cr);

        cairo_restore(cr);
    }

    // MARK: - Mini 65% Mechanical Keyboard (180° facing the cat)

    static void drawQuadPath(cairo_t* cr, Pt tl, Pt tr, Pt br, Pt bl) {
        cairo_new_path(cr);
        cairo_move_to(cr, tl.x, tl.y);
        cairo_line_to(cr, tr.x, tr.y);
        cairo_line_to(cr, br.x, br.y);
        cairo_line_to(cr, bl.x, bl.y);
        cairo_close_path(cr);
    }

    static void drawKeyboard(cairo_t* cr, const CatPhysics& physics, KeyboardTheme theme, RGBA glowColInput) {
        Pt tl = KeyboardLayout::screenQuadPoint(-0.025f, -0.08f);
        Pt tr = KeyboardLayout::screenQuadPoint(1.025f, -0.08f);
        Pt bl = KeyboardLayout::screenQuadPoint(-0.032f, 1.08f);
        Pt br = KeyboardLayout::screenQuadPoint(1.032f, 1.08f);
        constexpr float depth = 6.5f;

        drawQuadPath(cr, {tl.x, tl.y + depth + 2}, {tr.x, tr.y + depth + 2},
                         {br.x, br.y + depth + 3}, {bl.x, bl.y + depth + 3});
        cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
        cairo_fill(cr);

        RGBA baseCol, deckCol, keyCol, borderCol, accentCol;
        if (theme == KeyboardTheme::MidnightHacker) {
            baseCol = {0.06, 0.06, 0.08, 1}; deckCol = {0.10, 0.11, 0.13, 1};
            keyCol = {0.21, 0.22, 0.25, 1}; borderCol = {0.11, 0.11, 0.13, 0.95}; accentCol = {0.77, 0.94, 0.25, 1};
        } else if (theme == KeyboardTheme::RetroCream) {
            baseCol = {0.25, 0.24, 0.22, 1}; deckCol = {0.38, 0.36, 0.33, 1};
            keyCol = {0.90, 0.88, 0.82, 1}; borderCol = {0.68, 0.65, 0.60, 0.85}; accentCol = {0.88, 0.42, 0.24, 1};
        } else {
            baseCol = {0.10, 0.10, 0.12, 1}; deckCol = {0.14, 0.14, 0.16, 1};
            keyCol = {0.968, 0.964, 0.942, 1}; borderCol = {0.78, 0.77, 0.74, 0.75}; accentCol = {0.97, 0.70, 0.16, 1};
        }

        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
        drawQuadPath(cr, {tl.x, tl.y + depth}, {tr.x, tr.y + depth}, {br.x, br.y + depth}, {bl.x, bl.y + depth});
        setCol(cr, baseCol);
        cairo_fill_preserve(cr);
        cairo_set_line_width(cr, 5.0);
        cairo_stroke(cr);

        drawQuadPath(cr, tl, tr, br, bl);
        setCol(cr, deckCol);
        cairo_fill_preserve(cr);
        cairo_set_line_width(cr, 4.0);
        cairo_stroke(cr);

        constexpr float padU = 0.0028f;
        constexpr float padV = 0.014f;
        RGBA glowCol = glowColInput;

        for (const auto& cap : KeyboardLayout::keycaps()) {
            float glow = 0.0f;
            auto it = physics.keyGlow.find(cap.key);
            if (it != physics.keyGlow.end()) glow = it->second;

            float su0 = (1.0f - (cap.xUnits + cap.widthUnits)) + padU;
            float su1 = (1.0f - cap.xUnits) - padU;
            float sv0 = (1.0f - (cap.row + 1) / 5.0f) + padV;
            float sv1 = (1.0f - cap.row / 5.0f) - padV;

            float dy = glow * 1.9f;
            Pt kTL = KeyboardLayout::screenQuadPoint(su0, sv0); kTL.y += dy;
            Pt kTR = KeyboardLayout::screenQuadPoint(su1, sv0); kTR.y += dy;
            Pt kBR = KeyboardLayout::screenQuadPoint(su1, sv1); kBR.y += dy;
            Pt kBL = KeyboardLayout::screenQuadPoint(su0, sv1); kBL.y += dy;

            drawQuadPath(cr, kTL, kTR, kBR, kBL);
            RGBA fill = cap.isAmberAccent ? accentCol : keyCol;
            if (glow > 0.02f) fill = blend(fill, glowCol, glow * 0.55);

            setCol(cr, fill);
            cairo_fill_preserve(cr);
            setCol(cr, borderCol);
            cairo_set_line_width(cr, 0.7);
            cairo_stroke(cr);
        }

        // Backlit keycap glow halos
        for (const auto& kv : physics.keyGlow) {
            if (kv.second <= 0.05f) continue;
            Pt c = KeyboardLayout::canvasPointForKey(kv.first);
            double r = 17.0 + kv.second * 6.0;
            cairo_pattern_t* pat = cairo_pattern_create_radial(c.x, c.y, 0, c.x, c.y, r);
            cairo_pattern_add_color_stop_rgba(pat, 0.0, glowCol.r, glowCol.g, glowCol.b, 0.36 * kv.second);
            cairo_pattern_add_color_stop_rgba(pat, 1.0, glowCol.r, glowCol.g, glowCol.b, 0.0);
            cairo_set_source(cr, pat);
            cairo_arc(cr, c.x, c.y, r, 0, PI * 2.0);
            cairo_fill(cr);
            cairo_pattern_destroy(pat);
        }
    }

    // MARK: - Tail (Short-Hair & Dedicated Long-Fur Plume Pipeline)

    static void drawTail(cairo_t* cr, float seatX, float seatY, const CatPhysics& physics, const CatAppearance& app) {
        float p = physics.tailPhase;
        float hunt = std::clamp(physics.huntIntensity.value, 0.0f, 1.0f);
        float sleepCalm = 1.0f - physics.sleepiness * 0.65f;
        float wag1 = std::sin(p) * (8.0f + hunt * 5.5f) * sleepCalm;
        float wag2 = std::cos(p * 1.3f) * (6.0f + hunt * 4.5f) * sleepCalm;
        float huntDrop = hunt * 14.0f + physics.sleepiness * 18.0f;
        float sleepCurl = physics.sleepiness * 14.0f;

        Pt root = { seatX + 34.0f, seatY - 6.0f };
        Pt c1   = { seatX + 64.0f - sleepCurl * 0.3f, seatY + 2.0f + wag1 * 0.35f + huntDrop * 0.4f };
        Pt c2   = { seatX + 66.0f - sleepCurl * 0.7f + wag2 * 0.4f, seatY - 26.0f + wag1 * 0.7f + huntDrop };
        Pt tip  = { seatX + 91.0f - sleepCurl + wag2 * 0.5f, seatY - 30.0f + wag1 * 0.85f + huntDrop };

        RGBColor baseCol = app.primaryColor;
        if (app.pattern == FurPattern::Colorpoint) baseCol = app.secondaryColor;
        else if (app.pattern == FurPattern::Calico) baseCol = app.tertiaryColor;

        cairo_save(cr);
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
        if (!app.isDarkCoat()) {
            setCol(cr, outlineFor(app));
            cairo_set_line_width(cr, 13.6);
            cairo_move_to(cr, root.x, root.y);
            cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, tip.x, tip.y);
            cairo_stroke(cr);
        }
        setCol(cr, toRgba(baseCol));
        cairo_set_line_width(cr, 11.0);
        cairo_move_to(cr, root.x, root.y);
        cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, tip.x, tip.y);
        cairo_stroke(cr);

        if (app.pattern == FurPattern::Tabby || app.pattern == FurPattern::Spotted) {
            setCol(cr, toRgba(app.secondaryColor, 0.85));
            for (float t : {0.28f, 0.50f, 0.72f, 0.90f}) {
                Pt pt = cubicPoint(root, c1, c2, tip, t);
                cairo_new_path(cr);
                fillEllipse(cr, pt.x, pt.y, 4.0, 3.4);
                cairo_fill(cr);
            }
        } else if (app.pattern == FurPattern::Calico) {
            setCol(cr, toRgba(app.secondaryColor));
            Pt pt = cubicPoint(root, c1, c2, tip, 0.55f);
            cairo_new_path(cr);
            fillEllipse(cr, pt.x, pt.y, 5.0, 5.0);
            cairo_fill(cr);
        } else if (app.pattern == FurPattern::Tuxedo) {
            setCol(cr, toRgba(app.secondaryColor));
            cairo_new_path(cr);
            fillEllipse(cr, tip.x, tip.y, 5.0, 5.0);
            cairo_fill(cr);
        }
        cairo_restore(cr);
    }

    static void drawLongFurTail(cairo_t* cr, float seatX, float seatY, const CatPhysics& physics, const CatAppearance& app) {
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
        std::vector<Pt> upper, lower;
        upper.reserve(steps + 1); lower.reserve(steps + 1);
        for (int i = 0; i <= steps; ++i) {
            float t = (float)i / (float)steps;
            Pt pt = cubicPoint(root, c1, c2, tip, t);
            Pt tan = cubicTangent(root, c1, c2, tip, t);
            float len = std::max(0.001f, std::hypot(tan.x, tan.y));
            float nx = -tan.y / len, ny = tan.x / len;
            float env = std::sin(std::pow(t, 0.78f) * (float)PI);
            float baseHW = (4.5f + 10.5f * fluff * env) * (1.0f - 0.15f * t);
            float lockU = std::max(0.0f, std::sin(t * (float)PI * 4.5f)) * (2.2f * fluff * env);
            float lockL = std::max(0.0f, std::sin(t * (float)PI * 5.5f + 0.8f)) * (4.2f * fluff * env);
            float lagX = swayX * (0.25f + t * 0.75f) * fluff;
            float lagY = (2.8f * fluff * env) + swayY * (0.25f + t * 0.65f) * fluff;
            upper.push_back({ pt.x - nx * (baseHW * 0.78f + lockU) + lagX * 0.35f, pt.y - ny * (baseHW * 0.78f + lockU) + lagY * 0.25f });
            lower.push_back({ pt.x + nx * (baseHW * 1.15f + lockL) + lagX, pt.y + ny * (baseHW * 1.15f + lockL) + lagY });
        }

        auto tracePlume = [&]() {
            cairo_new_path(cr);
            cairo_move_to(cr, upper[0].x, upper[0].y);
            for (int i = 1; i <= steps; ++i) cairo_line_to(cr, upper[i].x, upper[i].y);
            cairo_line_to(cr, tip.x + 5.5f * fluff + swayX * 0.6f, tip.y - 2.0f * fluff + swayY * 0.5f);
            for (int i = steps; i >= 0; --i) cairo_line_to(cr, lower[i].x, lower[i].y);
            cairo_close_path(cr);
        };

        RGBColor baseCol = app.primaryColor;
        if (app.pattern == FurPattern::Colorpoint) baseCol = app.secondaryColor;
        else if (app.pattern == FurPattern::Calico) baseCol = app.tertiaryColor;

        cairo_save(cr);
        tracePlume();
        cairo_clip(cr);
        setCol(cr, toRgba(baseCol));
        cairo_paint(cr);
        if (app.pattern == FurPattern::Tabby || app.pattern == FurPattern::Spotted) {
            setCol(cr, toRgba(app.secondaryColor, 0.76));
            cairo_set_line_width(cr, 5.2);
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
            for (float t : {0.25f, 0.48f, 0.70f, 0.88f}) {
                Pt pt = cubicPoint(root, c1, c2, tip, t);
                Pt tan = cubicTangent(root, c1, c2, tip, t);
                float len = std::max(0.001f, std::hypot(tan.x, tan.y));
                float nx = -tan.y / len, ny = tan.x / len;
                cairo_move_to(cr, pt.x - nx * 18, pt.y - ny * 18);
                cairo_line_to(cr, pt.x + nx * 18, pt.y + ny * 18);
                cairo_stroke(cr);
            }
        } else if (app.pattern == FurPattern::Calico) {
            setCol(cr, toRgba(app.secondaryColor));
            Pt pt = cubicPoint(root, c1, c2, tip, 0.54f);
            cairo_new_path(cr);
            fillEllipse(cr, pt.x, pt.y, 14, 14);
            cairo_fill(cr);
        } else if (app.pattern == FurPattern::Tuxedo) {
            setCol(cr, toRgba(app.secondaryColor));
            cairo_new_path(cr);
            fillEllipse(cr, tip.x + 2, tip.y + 1, 14, 13);
            cairo_fill(cr);
        }
        cairo_restore(cr);

        tracePlume();
        setCol(cr, app.isDarkCoat() ? RGBA{contourMint.r, contourMint.g, contourMint.b, 0.26} : outlineFor(app, 0.82));
        cairo_set_line_width(cr, app.isDarkCoat() ? 1.0 : 1.4);
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
        cairo_stroke(cr);
    }

    // MARK: - 3D-Projected Ears

    static void drawEarsLayer(cairo_t* cr, Pt center, const CatPhysics& physics, const CatAppearance& app) {
        cairo_save(cr);
        cairo_translate(cr, center.x, center.y);
        cairo_rotate(cr, physics.headTilt.value);

        float yawRad = physics.headYaw.value * 0.50f;
        float pitchRad = physics.headPitch.value * 0.36f;
        float fold = physics.earFold.value;
        float twitch = physics.earTwitch.value * 0.045f;

        drawEar3D(cr, true, yawRad, pitchRad, fold, twitch, physics, app);
        drawEar3D(cr, false, yawRad, pitchRad, fold, -twitch, physics, app);
        cairo_restore(cr);
    }

    static void drawEar3D(cairo_t* cr, bool isLeft, float yawRad, float pitchRad, float fold, float twitch, const CatPhysics& physics, const CatAppearance& app) {
        float sign = isLeft ? -1.0f : 1.0f;
        float foldAngle = sign * (0.06f + fold * 0.34f) + twitch;
        bool longFur = app.useLongFurPipeline();
        float fluff = longFur ? std::clamp(app.furLength, 0.3f, 1.0f) : 0.0f;
        float tipDx = std::sin(foldAngle) * (32.0f + fluff * 3.0f);
        float tipDy = -std::cos(foldAngle) * (32.0f + fluff * 3.0f);

        Pt inB  = projectHead3D(sign * 9.0f, -16.0f, 0.0f, yawRad, pitchRad);
        Pt outB = projectHead3D(sign * (longFur ? 36.5f : 35.0f), -4.5f, -2.0f, yawRad, pitchRad);
        Pt tip  = projectHead3D(sign * 24.5f + tipDx, -20.0f + tipDy, -3.0f, yawRad, pitchRad);

        cairo_new_path(cr);
        cairo_move_to(cr, inB.x, inB.y);
        if (longFur) {
            Pt lynx = { tip.x + sign * (1.8f * fluff) + physics.furSwayX.value * 0.35f,
                        tip.y - (5.0f * fluff) + physics.furSwayY.value * 0.25f };
            quadCurveTo(cr, inB.x, inB.y, (inB.x + tip.x)*0.5 - sign*3.0, (inB.y + tip.y)*0.5 - 3.5, lynx.x, lynx.y);
            quadCurveTo(cr, lynx.x, lynx.y, (outB.x + tip.x)*0.5 + sign*4.5, (outB.y + tip.y)*0.5 - 1.5, outB.x, outB.y);
        } else {
            Pt tipL = { tip.x - sign * 3.8f, tip.y + 2.8f };
            Pt tipR = { tip.x + sign * 3.8f, tip.y + 3.2f };
            quadCurveTo(cr, inB.x, inB.y, (inB.x + tipL.x) * 0.5 - sign * 1.5, (inB.y + tipL.y) * 0.5 - 2.0, tipL.x, tipL.y);
            quadCurveTo(cr, tipL.x, tipL.y, tip.x, tip.y - 2.2, tipR.x, tipR.y);
            quadCurveTo(cr, tipR.x, tipR.y, (outB.x + tipR.x) * 0.5 + sign * 2.5, (outB.y + tipR.y) * 0.5 - 2.0, outB.x, outB.y);
        }
        cairo_close_path(cr);

        RGBColor earCol = app.primaryColor;
        if (app.pattern == FurPattern::Colorpoint) earCol = app.secondaryColor;
        else if (app.pattern == FurPattern::Calico) earCol = isLeft ? app.secondaryColor : app.tertiaryColor;

        setCol(cr, toRgba(earCol));
        if (!app.isDarkCoat()) {
            cairo_fill_preserve(cr);
            setCol(cr, outlineFor(app));
            cairo_set_line_width(cr, 1.35);
            cairo_stroke(cr);
        } else {
            cairo_fill(cr);
        }

        if (longFur) {
            Pt fb = projectHead3D(sign * 17.5f, -18.5f, 3.0f, yawRad, pitchRad);
            setCol(cr, app.isDarkCoat() ? RGBA{0.85, 0.85, 0.85, 0.28 * fluff} : toRgba(app.primaryColor.lightened(0.45f), 0.75 * fluff));
            cairo_set_line_width(cr, 1.5);
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
            for (int i = 0; i < 2; ++i) {
                double off = i * 4.0;
                cairo_move_to(cr, fb.x, fb.y + off);
                quadCurveTo(cr, fb.x, fb.y + off, fb.x + sign * 5.5 * fluff, fb.y - 4.5 + off, fb.x + sign * 10.5 * fluff, fb.y - 6.0 + off);
            }
            cairo_stroke(cr);
        }
    }

    // MARK: - Unified Silhouette (Short-Hair & Dedicated Long-Fur Pipeline + All 6 Fur Patterns)

    static void drawUnifiedSilhouette(cairo_t* cr, float seatX, float seatY, Pt headCenter, float breath, const CatPhysics& physics, const CatAppearance& app) {
        float yaw = physics.headYaw.value;
        float pitch = physics.headPitch.value;
        float hTilt = physics.headTilt.value;
        float bTilt = physics.bodyTilt.value;
        bool longFur = app.useLongFurPipeline();
        float f = longFur ? std::clamp(app.furLength, 0.3f, 1.0f) : 0.0f;
        float swayX = physics.furSwayX.value;
        float swayY = physics.furSwayY.value;

        float cH = std::cos(hTilt), sH = std::sin(hTilt);
        auto H = [&](float lx, float ly) -> Pt {
            return { headCenter.x + lx * cH - ly * sH, headCenter.y + lx * sH + ly * cH };
        };

        float cB = std::cos(bTilt), sB = std::sin(bTilt);
        float sy = physics.bodySquash.value;
        float sx = 1.0f + (1.0f - sy) * 0.55f;
        auto B = [&](float lx, float ly) -> Pt {
            float rx = lx * sx, ry = ly * sy;
            return { seatX + rx * cB - ry * sB, seatY + rx * sB + ry * cB };
        };

        float cheekShift = yaw * 3.0f;
        float crownDrop = pitch * 2.0f;

        auto buildPath = [&]() {
            cairo_new_path(cr);
            if (longFur) {
                Pt crownL = H(-12 + cheekShift * 0.2f, -31.0f - f * 2.5f + crownDrop);
                Pt crownT = H(cheekShift * 0.2f + swayX * 0.35f, -34.5f - f * 4.5f + crownDrop + swayY * 0.25f);
                Pt crownR = H(12 + cheekShift * 0.2f, -31.0f - f * 2.5f + crownDrop);
                Pt rT  = H(38.0f + f*3.0f + cheekShift*0.4f, -14.0f);
                Pt rC1 = H(47.5f + f*9.5f + cheekShift*0.4f + swayX*0.55f, 2.0f + swayY*0.45f);
                Pt rCI = H(43.0f + f*5.5f + cheekShift*0.35f + swayX*0.35f, 9.5f + swayY*0.35f);
                Pt rC2 = H(49.0f + f*11.0f + cheekShift*0.35f + swayX*0.80f, 18.0f + f*3.5f + swayY*0.65f);
                Pt rN  = H(41.0f + f*5.0f + cheekShift*0.25f + swayX*0.45f, 28.0f + f*2.0f);
                Pt rF1 = B(53.0f + f*8.5f + swayX*0.55f, -52.0f + breath*0.4f + swayY*0.45f);
                Pt rFI = B(50.5f + f*5.5f + swayX*0.35f, -36.0f + breath*0.3f);
                Pt rH  = B(55.0f + f*8.0f + swayX*0.45f, -14.0f + swayY*0.35f);
                Pt rBot = B(26.0f + f*3.0f, 12.5f);
                Pt lBot = B(-26.0f - f*3.0f, 12.5f);
                Pt lH  = B(-55.0f - f*8.0f + swayX*0.45f, -14.0f + swayY*0.35f);
                Pt lFI = B(-50.5f - f*5.5f + swayX*0.35f, -36.0f + breath*0.3f);
                Pt lF1 = B(-53.0f - f*8.5f + swayX*0.55f, -52.0f + breath*0.4f + swayY*0.45f);
                Pt lN  = H(-41.0f - f*5.0f + cheekShift*0.25f + swayX*0.45f, 28.0f + f*2.0f);
                Pt lC2 = H(-49.0f - f*11.0f + cheekShift*0.35f + swayX*0.80f, 18.0f + f*3.5f + swayY*0.65f);
                Pt lCI = H(-43.0f - f*5.5f + cheekShift*0.35f + swayX*0.35f, 9.5f + swayY*0.35f);
                Pt lC1 = H(-47.5f - f*9.5f + cheekShift*0.4f + swayX*0.55f, 2.0f + swayY*0.45f);
                Pt lT  = H(-38.0f - f*3.0f + cheekShift*0.4f, -14.0f);

                auto q = [&](Pt p0, Pt ctrl, Pt p2) { quadCurveTo(cr, p0.x, p0.y, ctrl.x, ctrl.y, p2.x, p2.y); };
                cairo_move_to(cr, crownL.x, crownL.y);
                q(crownL, H(-4 + cheekShift*0.2f, -33.5f - f*3.5f + crownDrop), crownT);
                q(crownT, H(5 + cheekShift*0.2f, -33.5f - f*3.5f + crownDrop), crownR);
                q(crownR, H(29 + f*2 + cheekShift*0.3f, -29 + crownDrop), rT);
                q(rT, H(45.5f + f*7.5f + cheekShift*0.4f, -7), rC1);
                q(rC1, H(46.5f + f*7.5f + cheekShift*0.4f, 7), rCI);
                q(rCI, H(49.5f + f*10 + cheekShift*0.35f, 13), rC2);
                q(rC2, H(46.5f + f*8 + cheekShift*0.3f, 25 + f*2), rN);
                q(rN, B(52 + f*7.5f, -62), rF1);
                q(rF1, B(53 + f*7.5f, -42), rFI);
                q(rFI, B(55.5f + f*8, -25), rH);
                Pt rc1 = B(52 + f*6.5f, 6), rc2 = B(40 + f*4.5f, 12.5f);
                cairo_curve_to(cr, rc1.x, rc1.y, rc2.x, rc2.y, rBot.x, rBot.y);
                cairo_line_to(cr, lBot.x, lBot.y);
                Pt lc1 = B(-40 - f*4.5f, 12.5f), lc2 = B(-52 - f*6.5f, 6);
                cairo_curve_to(cr, lc1.x, lc1.y, lc2.x, lc2.y, lH.x, lH.y);
                q(lH, B(-55.5f - f*8, -25), lFI);
                q(lFI, B(-53 - f*7.5f, -42), lF1);
                q(lF1, B(-52 - f*7.5f, -62), lN);
                q(lN, H(-46.5f - f*8 + cheekShift*0.3f, 25 + f*2), lC2);
                q(lC2, H(-49.5f - f*10 + cheekShift*0.35f, 13), lCI);
                q(lCI, H(-46.5f - f*7.5f + cheekShift*0.4f, 7), lC1);
                q(lC1, H(-45.5f - f*7.5f + cheekShift*0.4f, -7), lT);
                q(lT, H(-29 - f*2 + cheekShift*0.3f, -29 + crownDrop), crownL);
                cairo_close_path(cr);
            } else {
                float lCX = -42.5f + cheekShift * 0.4f;
                float rCX =  42.5f + cheekShift * 0.4f;
                Pt crown  = H(cheekShift * 0.2f, -30.0f + crownDrop);
                Pt rCheek = H(rCX, 5.0f);
                Pt rHip   = B(49.0f, -14.0f);
                Pt rBot   = B(24.0f, 12.0f);
                Pt lBot   = B(-24.0f, 12.0f);
                Pt lHip   = B(-49.0f, -14.0f);
                Pt lCheek = H(lCX, 5.0f);
                Pt c1, c2;
                cairo_move_to(cr, crown.x, crown.y);
                c1 = H(26.0f + cheekShift * 0.3f, -30.0f + crownDrop); c2 = H(rCX + 1.5f, -14.0f);
                cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, rCheek.x, rCheek.y);
                c1 = H(rCX - 2.5f, 24.0f); c2 = B(51.5f, -48.0f + breath * 0.5f);
                cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, rHip.x, rHip.y);
                c1 = B(47.0f, 5.0f); c2 = B(36.0f, 12.0f);
                cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, rBot.x, rBot.y);
                cairo_line_to(cr, lBot.x, lBot.y);
                c1 = B(-36.0f, 12.0f); c2 = B(-47.0f, 5.0f);
                cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, lHip.x, lHip.y);
                c1 = B(-51.5f, -48.0f + breath * 0.5f); c2 = H(lCX + 2.5f, 24.0f);
                cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, lCheek.x, lCheek.y);
                c1 = H(lCX - 1.5f, -14.0f); c2 = H(-26.0f + cheekShift * 0.3f, -30.0f + crownDrop);
                cairo_curve_to(cr, c1.x, c1.y, c2.x, c2.y, crown.x, crown.y);
                cairo_close_path(cr);
            }
        };

        cairo_save(cr);
        buildPath();
        cairo_clip(cr);

        if (app.isDarkCoat()) {
            setCol(cr, toRgba(app.primaryColor));
            cairo_paint(cr);
        } else {
            RGBA cTop = toRgba(app.primaryColor), cBot = toRgba(app.primaryColor.darkened(0.09f));
            cairo_pattern_t* bg = cairo_pattern_create_linear(seatX, headCenter.y - 34.0, seatX, seatY + 18.0);
            cairo_pattern_add_color_stop_rgba(bg, 0.15, cTop.r, cTop.g, cTop.b, 1.0);
            cairo_pattern_add_color_stop_rgba(bg, 1.0,  cBot.r, cBot.g, cBot.b, 1.0);
            cairo_set_source(cr, bg);
            cairo_paint(cr);
            cairo_pattern_destroy(bg);
        }

        float yawRad = yaw * 0.50f, pitchRad = pitch * 0.36f;
        if (app.pattern == FurPattern::Colorpoint) {
            Pt maskC = projectHead3D(0.0f, 2.5f, 27.0f, yawRad, pitchRad);
            double maskSX = std::max(0.76, std::cos((double)yawRad * 0.7)) * 1.18;
            double maskSY = std::max(0.82, std::cos((double)pitchRad * 0.7)) * 0.88;
            RGBA pt = toRgba(app.secondaryColor), mid = toRgba(app.tertiaryColor);
            cairo_save(cr);
            cairo_translate(cr, headCenter.x, headCenter.y);
            cairo_rotate(cr, hTilt);
            cairo_translate(cr, maskC.x, maskC.y);
            cairo_scale(cr, maskSX, maskSY);
            cairo_pattern_t* mp = cairo_pattern_create_radial(0, 0, 2.0, 0, 0, 31.0);
            cairo_pattern_add_color_stop_rgba(mp, 0.0,  pt.r, pt.g, pt.b, 1.0);
            cairo_pattern_add_color_stop_rgba(mp, 0.44, pt.r, pt.g, pt.b, 0.96);
            cairo_pattern_add_color_stop_rgba(mp, 0.74, mid.r, mid.g, mid.b, 0.70);
            cairo_pattern_add_color_stop_rgba(mp, 1.0,  mid.r, mid.g, mid.b, 0.0);
            cairo_set_source(cr, mp);
            cairo_arc(cr, 0, 0, 31.0, 0, PI * 2.0);
            cairo_fill(cr);
            cairo_pattern_destroy(mp);
            cairo_restore(cr);
        } else if (app.pattern == FurPattern::Tuxedo) {
            setCol(cr, toRgba(app.secondaryColor));
            Pt cTop = H(yaw * 5.0f, 22.0f), bR = B(22, -32), bBot = B(0, 14), bL = B(-22, -32);
            cairo_new_path(cr);
            cairo_move_to(cr, cTop.x, cTop.y);
            Pt q1 = H(20 + yaw*4, 34), q2 = B(26, -4), q3 = B(-26, -4), q4 = H(-20 + yaw*4, 34);
            quadCurveTo(cr, cTop.x, cTop.y, q1.x, q1.y, bR.x, bR.y);
            quadCurveTo(cr, bR.x, bR.y, q2.x, q2.y, bBot.x, bBot.y);
            quadCurveTo(cr, bBot.x, bBot.y, q3.x, q3.y, bL.x, bL.y);
            quadCurveTo(cr, bL.x, bL.y, q4.x, q4.y, cTop.x, cTop.y);
            cairo_close_path(cr);
            cairo_fill(cr);
            cairo_save(cr);
            cairo_translate(cr, headCenter.x, headCenter.y);
            cairo_rotate(cr, hTilt);
            Pt muz = projectHead3D(0.0f, 14.0f, 27.0f, yawRad, pitchRad);
            cairo_new_path(cr);
            fillEllipse(cr, muz.x, muz.y + 1.5, 16, 9.5);
            cairo_fill(cr);
            cairo_restore(cr);
        } else if (app.pattern == FurPattern::Tabby) {
            setCol(cr, toRgba(app.tertiaryColor, 0.75));
            Pt bc = B(0, -18);
            cairo_new_path(cr);
            fillEllipse(cr, bc.x, bc.y + 3, 24, 29);
            cairo_fill(cr);

            setCol(cr, toRgba(app.secondaryColor, 0.84));
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
            for (float side : {-1.0f, 1.0f}) {
                for (int idx = 0; idx < 3; ++idx) {
                    float yOff = -44.0f + idx * 16.0f;
                    Pt p0 = B(side * 58, yOff), ctrl = B(side * 38, yOff - 4), p1 = B(side * 24, yOff + 5);
                    cairo_set_line_width(cr, 5.4 - idx * 0.4);
                    cairo_move_to(cr, p0.x, p0.y);
                    quadCurveTo(cr, p0.x, p0.y, ctrl.x, ctrl.y, p1.x, p1.y);
                    cairo_stroke(cr);
                }
            }
            cairo_save(cr);
            cairo_translate(cr, headCenter.x, headCenter.y);
            cairo_rotate(cr, hTilt);
            cairo_set_line_width(cr, 2.8);
            for (float dx : {-7.5f, 0.0f, 7.5f}) {
                Pt tP = projectHead3D(dx * 1.1f, -25.0f, 22.0f, yawRad, pitchRad);
                Pt bP = projectHead3D(dx * 0.75f, -14.5f, 26.0f, yawRad, pitchRad);
                cairo_move_to(cr, tP.x, tP.y); cairo_line_to(cr, bP.x, bP.y);
            }
            cairo_stroke(cr);
            cairo_set_line_width(cr, 2.5);
            for (float sign : {-1.0f, 1.0f}) {
                for (float ry : {4.0f, 10.5f}) {
                    Pt p0 = projectHead3D(sign * 39.0f, ry - 1.5f, 10.0f, yawRad, pitchRad);
                    Pt p1 = projectHead3D(sign * 25.0f, ry + 1.5f, 22.0f, yawRad, pitchRad);
                    cairo_move_to(cr, p0.x, p0.y); cairo_line_to(cr, p1.x, p1.y);
                }
            }
            cairo_stroke(cr);
            cairo_restore(cr);
        } else if (app.pattern == FurPattern::Calico) {
            cairo_save(cr);
            cairo_translate(cr, headCenter.x, headCenter.y);
            cairo_rotate(cr, hTilt);
            Pt pL = projectHead3D(-22.0f, -15.0f, 18.0f, yawRad, pitchRad);
            setCol(cr, toRgba(app.secondaryColor));
            cairo_new_path(cr); fillEllipse(cr, pL.x - 2, pL.y - 1, 22, 19); cairo_fill(cr);
            Pt pR = projectHead3D(24.0f, -12.0f, 17.0f, yawRad, pitchRad);
            setCol(cr, toRgba(app.tertiaryColor));
            cairo_new_path(cr); fillEllipse(cr, pR.x + 1, pR.y - 1, 21, 17); cairo_fill(cr);
            cairo_restore(cr);
            Pt hp1 = B(32, -26), hp2 = B(-34, -10);
            setCol(cr, toRgba(app.secondaryColor));
            cairo_new_path(cr); fillEllipse(cr, hp1.x, hp1.y, 24, 21); cairo_fill(cr);
            setCol(cr, toRgba(app.tertiaryColor));
            cairo_new_path(cr); fillEllipse(cr, hp2.x, hp2.y, 22, 18); cairo_fill(cr);
        } else if (app.pattern == FurPattern::Spotted) {
            setCol(cr, toRgba(app.secondaryColor));
            cairo_save(cr);
            cairo_translate(cr, headCenter.x, headCenter.y);
            cairo_rotate(cr, hTilt);
            Pt s1 = projectHead3D(-18, -17, 20, yawRad, pitchRad);
            Pt s2 = projectHead3D(20, -14, 19, yawRad, pitchRad);
            cairo_new_path(cr); fillEllipse(cr, s1.x, s1.y, 12, 10); cairo_fill(cr);
            cairo_new_path(cr); fillEllipse(cr, s2.x, s2.y, 9, 7.5); cairo_fill(cr);
            cairo_restore(cr);
            const float spots[4][4] = { {-30,-34,12,10}, {28,-36,10,9}, {34,-8,13,11}, {-24,-4,9,8} };
            for (auto& sp : spots) {
                Pt pt = B(sp[0], sp[1]);
                cairo_new_path(cr); fillEllipse(cr, pt.x, pt.y, sp[2], sp[3]); cairo_fill(cr);
            }
        }

        // Soft fading layered chest mane for long-fur cats
        if (longFur) {
            cairo_save(cr);
            cairo_translate(cr, seatX * 0.45 + headCenter.x * 0.55, headCenter.y + 34.0 + breath * 0.45);
            cairo_rotate(cr, bTilt * 0.65 + hTilt * 0.35);
            double mw = 26.0 + f * 14.0, mh = 15.0 + f * 18.0;
            RGBColor mCol = (app.pattern == FurPattern::Tuxedo) ? app.secondaryColor
                : ((app.pattern == FurPattern::Tabby) ? app.tertiaryColor : app.primaryColor.lightened(app.isDarkCoat() ? 0.08f : 0.22f));
            RGBA mc = toRgba(mCol);
            cairo_new_path(cr);
            cairo_move_to(cr, -mw, -10);
            quadCurveTo(cr, -mw, -10, -mw*0.92, mh*0.35, -mw*0.48 + swayX*0.5, mh*0.72 + swayY*0.5);
            quadCurveTo(cr, -mw*0.48 + swayX*0.5, mh*0.72 + swayY*0.5, -mw*0.18 + swayX*0.65, mh*0.92, swayX*0.85, mh + swayY*0.85);
            quadCurveTo(cr, swayX*0.85, mh + swayY*0.85, mw*0.18 + swayX*0.65, mh*0.92, mw*0.48 + swayX*0.5, mh*0.72 + swayY*0.5);
            quadCurveTo(cr, mw*0.48 + swayX*0.5, mh*0.72 + swayY*0.5, mw*0.92, mh*0.35, mw, -10);
            cairo_close_path(cr);
            cairo_pattern_t* mg = cairo_pattern_create_linear(0, -10, 0, mh + 2);
            cairo_pattern_add_color_stop_rgba(mg, 0.0, mc.r, mc.g, mc.b, 0.0);
            cairo_pattern_add_color_stop_rgba(mg, 0.38, mc.r, mc.g, mc.b, 0.88);
            cairo_pattern_add_color_stop_rgba(mg, 1.0, mc.r, mc.g, mc.b, 0.96);
            cairo_set_source(cr, mg);
            cairo_fill(cr);
            cairo_pattern_destroy(mg);
            cairo_restore(cr);
        }

        cairo_restore(cr);

        if (!app.isDarkCoat()) {
            buildPath();
            setCol(cr, outlineFor(app));
            cairo_set_line_width(cr, 1.5);
            cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
            cairo_stroke(cr);
        }

        // Tucked hind paws at bottom
        cairo_save(cr);
        cairo_translate(cr, seatX, seatY);
        cairo_rotate(cr, bTilt);
        cairo_scale(cr, sx, sy);

        RGBColor hpCol = (app.pattern == FurPattern::Colorpoint || app.pattern == FurPattern::Tuxedo) ? app.secondaryColor : app.primaryColor;
        setCol(cr, toRgba(hpCol));
        cairo_new_path(cr); fillEllipse(cr, -26.5, 8.5, 8.5, 5.5); cairo_fill(cr);
        if (physics.hindFootActive.value < 0.35f) {
            cairo_new_path(cr); fillEllipse(cr, 26.5, 8.5, 8.5, 5.5); cairo_fill(cr);
        }

        setCol(cr, limbSepColor(app, 0.56));
        cairo_set_line_width(cr, 1.3);
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
        cairo_new_path(cr); cairo_arc(cr, -26.5, 8.5, 7.5, 0.25, PI - 0.25); cairo_stroke(cr);
        if (physics.hindFootActive.value < 0.35f) {
            cairo_new_path(cr); cairo_arc(cr, 26.5, 8.5, 7.5, 0.25, PI - 0.25); cairo_stroke(cr);
        }
        cairo_restore(cr);
    }

    // MARK: - Configurable Necktie / Bow Tie Accessory

    static void fillTieFabric(cairo_t* cr, double bx, double by, double bw, double bh, const TiePalette& pal, TiePattern pat) {
        cairo_save(cr);
        cairo_clip_preserve(cr);
        setCol(cr, toRgba(pal.base));
        cairo_rectangle(cr, bx, by, bw, bh);
        cairo_fill(cr);

        if (pat == TiePattern::ScottishGrid) {
            cairo_save(cr);
            cairo_translate(cr, bx + bw * 0.5, by + bh * 0.5);
            cairo_rotate(cr, PI / 4.0);
            double span = std::max(bw, bh) * 1.6, cell = 7.6;
            setCol(cr, toRgba(pal.dark, 0.54));
            for (double pos = -span; pos <= span; pos += cell) {
                cairo_rectangle(cr, pos, -span, 2.8, span * 2.0);
                cairo_rectangle(cr, -span, pos, span * 2.0, 2.8);
            }
            cairo_fill(cr);
            setCol(cr, toRgba(pal.light, 0.88));
            cairo_set_line_width(cr, 0.75);
            for (double pos = -span + cell * 0.5 + 1.4; pos <= span; pos += cell) {
                cairo_move_to(cr, pos, -span); cairo_line_to(cr, pos, span);
                cairo_move_to(cr, -span, pos); cairo_line_to(cr, span, pos);
            }
            cairo_stroke(cr);
            cairo_restore(cr);
        } else if (pat == TiePattern::DiagonalStripe) {
            cairo_save(cr);
            cairo_translate(cr, bx + bw * 0.5, by + bh * 0.5);
            cairo_rotate(cr, PI / 4.0);
            double span = std::max(bw, bh) * 1.6;
            for (double pos = -span; pos <= span; pos += 7.2) {
                setCol(cr, toRgba(pal.dark, 0.78));
                cairo_rectangle(cr, pos, -span, 2.8, span * 2.0);
                cairo_fill(cr);
                setCol(cr, toRgba(pal.light, 0.88));
                cairo_rectangle(cr, pos + 3.4, -span, 0.9, span * 2.0);
                cairo_fill(cr);
            }
            cairo_restore(cr);
        } else if (pat == TiePattern::PolkaDot) {
            setCol(cr, toRgba(pal.light, 0.92));
            int row = 0;
            for (double y = by - 2.0; y <= by + bh + 2.0; y += 4.6, ++row) {
                double ox = (row % 2 == 0) ? 0.0 : 2.6;
                for (double x = bx - 2.0 + ox; x <= bx + bw + 2.0; x += 5.2) {
                    cairo_new_path(cr);
                    cairo_arc(cr, x, y, 1.1, 0, PI * 2.0);
                    cairo_fill(cr);
                }
            }
        }
        cairo_restore(cr);
    }

    static void drawTieAccessory(cairo_t* cr, float seatX, Pt headCenter, float breath, const CatPhysics& physics, const CatSettings& settings, const CatAppearance& app) {
        TiePalette pal = getTiePalette(settings.tieColor);
        double neckX = seatX * 0.45 + headCenter.x * 0.55 + physics.headYaw.value * 4.5;
        double neckY = headCenter.y + 30.5 + breath * 0.35;
        double tilt = physics.bodyTilt.value * 0.65 + physics.headTilt.value * 0.35;
        RGBA outCol = app.isDarkCoat() ? RGBA{0.05, 0.05, 0.06, 0.86} : outlineFor(app);

        cairo_save(cr);
        cairo_translate(cr, neckX, neckY);
        cairo_rotate(cr, tilt);

        // Collar band
        cairo_new_path(cr);
        cairo_move_to(cr, -24.5, -3.5);
        quadCurveTo(cr, -24.5, -3.5, 0, 4.5, 24.5, -3.5);
        cairo_line_to(cr, 23.0, 1.5);
        quadCurveTo(cr, 23.0, 1.5, 0, 8.8, -23.0, 1.5);
        cairo_close_path(cr);
        fillTieFabric(cr, -26, -6, 52, 18, pal, settings.tiePattern);
        setCol(cr, outCol); cairo_set_line_width(cr, 1.05); cairo_stroke(cr);

        if (settings.tieStyle == TieStyle::Necktie) {
            cairo_new_path(cr);
            cairo_move_to(cr, -3.6, 5.5); cairo_line_to(cr, 3.6, 5.5);
            cairo_line_to(cr, 8.2, 27.0); cairo_line_to(cr, 0.0, 35.5); cairo_line_to(cr, -8.2, 27.0);
            cairo_close_path(cr);
            fillTieFabric(cr, -10, 4, 20, 34, pal, settings.tiePattern);
            setCol(cr, outCol); cairo_set_line_width(cr, 1.1); cairo_stroke(cr);

            cairo_new_path(cr);
            cairo_move_to(cr, -5.4, -1.0);
            quadCurveTo(cr, -5.4, -1.0, 0, -2.4, 5.4, -1.0);
            cairo_line_to(cr, 3.8, 6.4);
            quadCurveTo(cr, 3.8, 6.4, 0, 7.4, -3.8, 6.4);
            cairo_close_path(cr);
            fillTieFabric(cr, -7, -3, 14, 12, pal, settings.tiePattern);
            setCol(cr, outCol); cairo_set_line_width(cr, 1.05); cairo_stroke(cr);
        } else {
            for (double sign : {-1.0, 1.0}) {
                cairo_new_path(cr);
                cairo_move_to(cr, sign*3.0, 0.2);
                quadCurveTo(cr, sign*3.0, 0.2, sign*10.2, -4.8, sign*16.5, -5.2);
                quadCurveTo(cr, sign*16.5, -5.2, sign*19.2, -1.0, sign*17.5, 3.2);
                quadCurveTo(cr, sign*17.5, 3.2, sign*18.6, 8.2, sign*15.2, 11.0);
                quadCurveTo(cr, sign*15.2, 11.0, sign*9.5, 10.6, sign*3.0, 5.8);
                cairo_close_path(cr);
                fillTieFabric(cr, sign > 0 ? 1.0 : -20.0, -7.0, 19.0, 20.0, pal, settings.tiePattern);
                setCol(cr, outCol); cairo_set_line_width(cr, 1.1); cairo_stroke(cr);
            }
            roundedRect(cr, -4.4, -1.6, 8.8, 9.4, 3.2);
            fillTieFabric(cr, -6, -3, 12, 12, pal, settings.tiePattern);
            setCol(cr, outCol); cairo_set_line_width(cr, 1.1); cairo_stroke(cr);
        }
        cairo_restore(cr);
    }

    // MARK: - 3rd Key Hind Foot

    static void drawHindFoot(cairo_t* cr, float seatX, float seatY, const CatPhysics& physics, const CatAppearance& app) {
        Pt hip = { seatX + 26.0f, seatY + 2.0f };
        Pt target = physics.hindFoot.point();
        Pt mid = { (hip.x + target.x) * 0.5f + 10.0f, (hip.y + target.y) * 0.5f - 8.0f };
        drawLimb(cr, hip, mid, target, 15.0f, 12.0f, true, 0.85f * physics.hindFootActive.value, app);
    }

    // MARK: - 2.5D Eyes & Whiskers

    static void drawHeadFeatures(cairo_t* cr, Pt center, const CatPhysics& physics, const CatAppearance& app) {
        cairo_save(cr);
        cairo_translate(cr, center.x, center.y);
        cairo_rotate(cr, physics.headTilt.value);

        float yawRad = physics.headYaw.value * 0.50f;
        float pitchRad = physics.headPitch.value * 0.36f;

        drawEye3D(cr, true, yawRad, pitchRad, physics, app);
        drawEye3D(cr, false, yawRad, pitchRad, physics, app);
        drawWhiskers3D(cr, yawRad, pitchRad, physics, app);
        cairo_restore(cr);
    }

    static void drawEye3D(cairo_t* cr, bool isLeft, float yawRad, float pitchRad, const CatPhysics& physics, const CatAppearance& app) {
        float sign = isLeft ? -1.0f : 1.0f;
        RGBA eyeCol = toRgba(app.eyeColor);
        bool lightFace = app.primaryColor.luminance() > 0.42f && app.pattern != FurPattern::Colorpoint;
        RGBA lidCol = (app.pattern == FurPattern::Colorpoint) ? toRgba(app.secondaryColor) : toRgba(app.primaryColor);
        RGBA closedArcCol = lightFace ? toRgba(app.primaryColor.darkened(0.35f), 0.90) : eyeCol;

        Pt proj = projectHead3D(sign * 17.2f, -2.0f, 27.5f, yawRad, pitchRad);

        float eyeNormal = yawRad + sign * 0.34f;
        double foreX = std::clamp((double)std::cos(eyeNormal) / std::cos(0.34), 0.64, 1.06);
        double foreY = std::clamp((double)std::cos(pitchRad * 0.85f), 0.78, 1.03);

        cairo_save(cr);
        cairo_translate(cr, proj.x, proj.y);
        cairo_scale(cr, foreX, foreY);

        // Mode 1: Petting / happy closed eyes
        if (physics.isHappyClosedEyes()) {
            setCol(cr, closedArcCol);
            cairo_set_line_width(cr, 2.6);
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
            cairo_move_to(cr, -11.5, 1.0);
            quadCurveTo(cr, -11.5, 1.0, sign * 1.5, 3.4, 11.5, 1.0);
            cairo_stroke(cr);
            cairo_restore(cr);
            return;
        }

        // Mode 2: Blissful squint
        if (physics.isBlissfulSquint()) {
            setCol(cr, eyeCol);
            cairo_new_path(cr);
            cairo_move_to(cr, -11.5, -0.5);
            quadCurveTo(cr, -11.5, -0.5, 0.0, 0.6, 11.5, -0.5);
            quadCurveTo(cr, 11.5, -0.5, 0.0, 4.8, -11.5, -0.5);
            cairo_close_path(cr);
            cairo_fill(cr);
            cairo_restore(cr);
            return;
        }

        // Mode 3: Peaceful sleeping closed eyes (◡ ◡)
        if (physics.isSleepingEyes()) {
            setCol(cr, closedArcCol, 0.88);
            cairo_set_line_width(cr, 2.5);
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
            cairo_move_to(cr, -10.8, 1.2);
            quadCurveTo(cr, -10.8, 1.2, 0.0, 5.4, 10.8, 1.2);
            cairo_stroke(cr);
            // Tiny outer eyelash tick
            cairo_set_line_width(cr, 1.55);
            cairo_move_to(cr, sign * 10.2, 1.4);
            cairo_line_to(cr, sign * 12.6, 2.8);
            cairo_stroke(cr);
            cairo_restore(cr);
            return;
        }

        float hunt = std::clamp(physics.huntIntensity.value, 0.0f, 1.0f);
        float tired = std::clamp(physics.tiredness.value, 0.0f, 1.0f);
        cairo_rotate(cr, sign * (0.06f * (1.0f - hunt * 0.6f)));

        double rx = 12.0 + hunt * 1.1;
        double ry = 10.8 + hunt * 1.8;

        // Under-eye dark circles when tired (0:00-6:00 AM)
        if (tired > 0.05f) {
            cairo_save(cr);
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
            if (lightFace) {
                cairo_set_source_rgba(cr, 0.34, 0.25, 0.36, 0.36 * tired);
            } else {
                cairo_set_source_rgba(cr, 0.48, 0.44, 0.56, 0.40 * tired);
            }
            cairo_set_line_width(cr, 2.6);
            cairo_move_to(cr, -rx * 0.72, ry * 0.86);
            quadCurveTo(cr, -rx * 0.72, ry * 0.86, 0.0, ry * 1.22, rx * 0.72, ry * 0.86);
            cairo_stroke(cr);

            if (lightFace) {
                cairo_set_source_rgba(cr, 0.32, 0.22, 0.34, 0.24 * tired);
            } else {
                cairo_set_source_rgba(cr, 0.40, 0.36, 0.48, 0.28 * tired);
            }
            cairo_set_line_width(cr, 1.5);
            cairo_move_to(cr, -rx * 0.52, ry * 1.12);
            quadCurveTo(cr, -rx * 0.52, ry * 1.12, 0.0, ry * 1.40, rx * 0.52, ry * 1.12);
            cairo_stroke(cr);
            cairo_restore(cr);
        }

        cairo_save(cr);
        cairo_new_path(cr);
        fillEllipse(cr, 0, 0, rx, ry);
        cairo_clip(cr);

        setCol(cr, eyeCol);
        cairo_rectangle(cr, -rx - 1, -ry - 1, rx * 2 + 2, ry * 2 + 2);
        cairo_fill(cr);

        Pt gaze = physics.eyeGaze.point();
        double px = gaze.x * (4.2 - hunt * 1.2);
        double py = gaze.y * (3.6 - hunt * 1.0);
        double pScale = physics.pupilScale.value;
        double normalW = 5.0 * pScale;
        double normalH = 13.5 * std::min(1.12, pScale);
        double pupilW = normalW + (18.8 - normalW) * hunt;
        double pupilH = normalH + (18.8 - normalH) * hunt;

        setCol(cr, catBlack);
        cairo_new_path(cr);
        fillEllipse(cr, px, py, pupilW * 0.5, pupilH * 0.5);
        cairo_fill(cr);

        if (hunt > 0.25f) {
            double ga = std::min(1.0, (hunt - 0.25) / 0.55) * 0.92;
            double gr = 2.1 + hunt * 0.9;
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, ga);
            cairo_arc(cr, px - pupilW * 0.22, py - pupilH * 0.22, gr, 0, PI * 2.0);
            cairo_fill(cr);
        }

        float closure = physics.effectiveEyeClosure();
        if (closure > 0.02f) {
            double lidBottom = -ry - 2.0 + (ry * 2.2) * closure;
            setCol(cr, lidCol);
            if (tired > 0.1f && closure < 0.72f) {
                // Slightly slanted heavy droopy upper eyelid
                double slope = sign * 2.2 * tired;
                cairo_new_path(cr);
                cairo_move_to(cr, -rx - 3.0, -ry - 3.0);
                cairo_line_to(cr, rx + 3.0, -ry - 3.0);
                cairo_line_to(cr, rx + 3.0, lidBottom + slope);
                quadCurveTo(cr, rx + 3.0, lidBottom + slope, 0.0, lidBottom + 1.5, -rx - 3.0, lidBottom - slope);
                cairo_close_path(cr);
                cairo_fill(cr);

                setCol(cr, lightFace ? toRgba(app.primaryColor.darkened(0.45f), 0.75) : RGBA{0.78, 0.86, 0.84, 0.42 * tired});
                cairo_set_line_width(cr, 1.25);
                cairo_move_to(cr, -rx - 1.0, lidBottom - slope);
                quadCurveTo(cr, -rx - 1.0, lidBottom - slope, 0.0, lidBottom + 1.5, rx + 1.0, lidBottom + slope);
                cairo_stroke(cr);
            } else {
                cairo_rectangle(cr, -rx - 2, -ry - 2, rx * 2 + 4, (ry * 2.2) * closure);
                cairo_fill(cr);
            }
        }

        cairo_restore(cr);

        // Subtle eye rim for light coats so bright eyes stay crisp
        if (lightFace) {
            setCol(cr, outlineFor(app, 0.55));
            cairo_set_line_width(cr, 1.0);
            cairo_new_path(cr);
            fillEllipse(cr, 0, 0, rx, ry);
            cairo_stroke(cr);
        }

        cairo_restore(cr);
    }

    static void drawWhiskers3D(cairo_t* cr, float yawRad, float pitchRad, const CatPhysics& physics, const CatAppearance& app) {
        float wiggle = std::sin(physics.time * 4.5f) * (std::max(physics.petHeadIntensity, physics.petBodyIntensity) * 1.2f);
        if (app.isDarkCoat()) setCol(cr, whiskerWhite);
        else setCol(cr, toRgba(app.primaryColor.darkened(0.42f), 0.58));
        cairo_set_line_width(cr, 1.05);
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);

        const float rows[3][3] = {
            { 10.5f, 36.5f, 8.8f + wiggle },
            { 14.2f, 37.8f, 14.2f + wiggle * 0.5f },
            { 18.0f, 35.5f, 19.6f - wiggle * 0.4f }
        };

        for (float sign : {-1.0f, 1.0f}) {
            for (int i = 0; i < 3; ++i) {
                Pt p0 = projectHead3D(sign * 24.0f, rows[i][0], 23.0f, yawRad, pitchRad);
                Pt p2 = projectHead3D(sign * rows[i][1], rows[i][2], 14.0f, yawRad, pitchRad);
                cairo_move_to(cr, p0.x, p0.y);
                quadCurveTo(cr, p0.x, p0.y, (p0.x + p2.x) * 0.5, (p0.y + p2.y) * 0.5 - 0.8, p2.x, p2.y);
            }
        }
        cairo_stroke(cr);
    }

    // MARK: - Front Paws

    static void drawFrontPaws(cairo_t* cr, float seatX, float seatY, float breath, const CatPhysics& physics, const CatAppearance& app) {
        Pt lPos = physics.leftPaw.point();
        Pt rPos = physics.rightPaw.point();
        float lDist = std::hypot(lPos.x - CatPhysics::LeftPawRest.x, lPos.y - CatPhysics::LeftPawRest.y);
        float rDist = std::hypot(rPos.x - CatPhysics::RightPawRest.x, rPos.y - CatPhysics::RightPawRest.y);

        Pt lSh = { seatX - 24.0f, seatY - 56.0f + breath };
        Pt rSh = { seatX + 24.0f, seatY - 56.0f + breath };

        if (lDist < 6.0f && !physics.leftPawOnMouse && !physics.leftPawTyping) {
            drawIdleFrontLeg(cr, { seatX - 18.0f, seatY - 30.0f }, { seatX - 16.0f, seatY + 12.0f }, true, app);
        } else {
            Pt mid = { (lSh.x + lPos.x) * 0.5f - (physics.leftPawOnMouse ? 8.0f : 4.0f), (lSh.y + lPos.y) * 0.5f - 6.0f };
            drawLimb(cr, lSh, mid, lPos, 19.0f, 13.5f, false, 0.78f, app);
        }

        if (rDist < 6.0f && !physics.rightPawTyping) {
            drawIdleFrontLeg(cr, { seatX + 18.0f, seatY - 30.0f }, { seatX + 16.0f, seatY + 12.0f }, false, app);
        } else {
            Pt mid = { (rSh.x + rPos.x) * 0.5f + 4.0f, (rSh.y + rPos.y) * 0.5f - 6.0f };
            drawLimb(cr, rSh, mid, rPos, 19.0f, 13.5f, true, 0.78f, app);
        }
    }

    static void drawIdleFrontLeg(cairo_t* cr, Pt top, Pt bottom, bool isLeft, const CatAppearance& app) {
        float sign = isLeft ? -1.0f : 1.0f;
        if (app.pattern == FurPattern::Colorpoint) {
            RGBA base = toRgba(app.primaryColor);
            RGBA mid  = toRgba(app.primaryColor.blended(app.secondaryColor, 0.55f));
            RGBA pt   = toRgba(app.secondaryColor);
            cairo_save(cr);
            roundedRect(cr, bottom.x - 7.5, top.y, 15.0, bottom.y - top.y + 1.0, 6.5);
            cairo_pattern_t* grad = cairo_pattern_create_linear(top.x, top.y, bottom.x, bottom.y + 2.0);
            cairo_pattern_add_color_stop_rgba(grad, 0.05, base.r, base.g, base.b, 0.0);
            cairo_pattern_add_color_stop_rgba(grad, 0.52, mid.r, mid.g, mid.b, 0.75);
            cairo_pattern_add_color_stop_rgba(grad, 0.85, pt.r, pt.g, pt.b, 1.0);
            cairo_set_source(cr, grad);
            cairo_fill(cr);
            cairo_pattern_destroy(grad);
            cairo_restore(cr);
        } else if (app.pattern == FurPattern::Tuxedo) {
            setCol(cr, toRgba(app.secondaryColor));
            roundedRect(cr, bottom.x - 6.8, bottom.y - 10.0, 13.6, 11.5, 5.5);
            cairo_fill(cr);
        }

        setCol(cr, limbSepColor(app, app.isDarkCoat() ? 0.90 : 0.65));
        cairo_set_line_width(cr, 1.45);
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);

        cairo_move_to(cr, top.x + sign * 8.5, top.y);
        quadCurveTo(cr, top.x + sign * 8.5, top.y, top.x + sign * 9.5, (top.y + bottom.y) * 0.5, bottom.x + sign * 7.5, bottom.y - 1.0);
        cairo_move_to(cr, top.x - sign * 7.0, top.y + 4.0);
        quadCurveTo(cr, top.x - sign * 7.0, top.y + 4.0, top.x - sign * 6.5, (top.y + bottom.y) * 0.5, bottom.x - sign * 6.0, bottom.y - 1.0);
        cairo_stroke(cr);
    }

    static void drawLimb(cairo_t* cr, Pt start, Pt ctrl, Pt end, float startW, float endW, bool outlineOnLeft, float outlineAlpha, const CatAppearance& app) {
        constexpr int steps = 14;
        std::vector<Pt> leftEdge, rightEdge;
        leftEdge.reserve(steps + 1); rightEdge.reserve(steps + 1);

        for (int i = 0; i <= steps; ++i) {
            float t = (float)i / (float)steps;
            Pt p = quadPoint(start, ctrl, end, t);
            Pt tan = quadTangent(start, ctrl, end, t);
            float len = std::max(0.001f, std::hypot(tan.x, tan.y));
            float nx = -tan.y / len, ny = tan.x / len;
            float hw = (startW + (endW - startW) * t) * 0.5f;
            leftEdge.push_back({ p.x + nx * hw, p.y + ny * hw });
            rightEdge.push_back({ p.x - nx * hw, p.y - ny * hw });
        }

        auto traceLimb = [&]() {
            cairo_new_path(cr);
            cairo_move_to(cr, leftEdge[0].x, leftEdge[0].y);
            for (int i = 1; i <= steps; ++i) cairo_line_to(cr, leftEdge[i].x, leftEdge[i].y);
            for (int i = steps; i >= 0; --i) cairo_line_to(cr, rightEdge[i].x, rightEdge[i].y);
            cairo_close_path(cr);
        };

        double pawR = endW * 0.58;
        if (app.pattern == FurPattern::Colorpoint) {
            RGBA base = toRgba(app.primaryColor);
            RGBA mid  = toRgba(app.primaryColor.blended(app.secondaryColor, 0.55f));
            RGBA pt   = toRgba(app.secondaryColor);

            cairo_save(cr);
            traceLimb();
            cairo_pattern_t* grad = cairo_pattern_create_linear(start.x, start.y, end.x, end.y);
            cairo_pattern_add_color_stop_rgba(grad, 0.0,  base.r, base.g, base.b, 0.0);
            cairo_pattern_add_color_stop_rgba(grad, 0.16, base.r, base.g, base.b, 1.0);
            cairo_pattern_add_color_stop_rgba(grad, 0.48, mid.r,  mid.g,  mid.b,  1.0);
            cairo_pattern_add_color_stop_rgba(grad, 0.78, pt.r,   pt.g,   pt.b,   1.0);
            cairo_set_source(cr, grad);
            cairo_fill(cr);
            cairo_pattern_destroy(grad);
            cairo_restore(cr);

            setCol(cr, pt);
            cairo_new_path(cr);
            fillEllipse(cr, end.x, end.y, pawR, pawR * 0.85);
            cairo_fill(cr);
        } else {
            traceLimb();
            setCol(cr, toRgba(app.primaryColor));
            cairo_fill(cr);
            RGBA pawCol = (app.pattern == FurPattern::Tuxedo) ? toRgba(app.secondaryColor) : toRgba(app.primaryColor);
            setCol(cr, pawCol);
            cairo_new_path(cr);
            fillEllipse(cr, end.x, end.y, pawR, pawR * 0.85);
            cairo_fill(cr);
        }

        if (!app.isDarkCoat()) {
            const auto& outerEdge = outlineOnLeft ? rightEdge : leftEdge;
            setCol(cr, outlineFor(app, 0.78));
            cairo_set_line_width(cr, 1.25);
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
            cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
            cairo_move_to(cr, outerEdge[3].x, outerEdge[3].y);
            for (int i = 4; i < steps; ++i) cairo_line_to(cr, outerEdge[i].x, outerEdge[i].y);
            cairo_stroke(cr);
        }

        const auto& hiEdge = outlineOnLeft ? leftEdge : rightEdge;
        int sIdx = 2, eIdx = (int)(steps * 0.68f);
        setCol(cr, limbSepColor(app, outlineAlpha * 0.9));
        cairo_set_line_width(cr, 1.35);
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
        cairo_move_to(cr, hiEdge[sIdx].x, hiEdge[sIdx].y);
        for (int i = sIdx + 1; i <= eIdx; ++i) cairo_line_to(cr, hiEdge[i].x, hiEdge[i].y);
        cairo_stroke(cr);
    }

    // MARK: - Floating Keycaps

    static void drawFloatingKeycaps(cairo_t* cr, const CatPhysics& physics) {
        cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);

        for (const auto& b : physics.floatingKeycaps) {
            float prog = b.age / b.lifetime;
            double scale = 1.0;
            if (b.age < 0.09f) scale = 0.72 + 0.38 * std::sin((b.age / 0.09) * PI * 0.65);
            else if (b.age < 0.18f) scale = 1.10 - 0.10 * ((b.age - 0.09) / 0.09);

            double alpha = prog < 0.62f ? 1.0 : std::max(0.0, 1.0 - (prog - 0.62) / 0.38);
            if (alpha < 0.02) continue;

            // Estimate display glyph count (UTF-8 multi-byte symbols count as 1 char)
            size_t glyphLen = 0;
            for (unsigned char c : b.label) if ((c & 0xC0) != 0x80) glyphLen++;
            double w = glyphLen <= 1 ? 23.0 : (glyphLen == 2 ? 30.0 : 38.0);
            double h = 22.0;

            cairo_save(cr);
            cairo_translate(cr, b.position.x, b.position.y);
            cairo_rotate(cr, b.rotation);
            cairo_scale(cr, scale, scale);

            roundedRect(cr, -w * 0.5, -h * 0.5 + 2.5, w, h, 5.5);
            cairo_set_source_rgba(cr, 0.15, 0.15, 0.17, 0.95 * alpha);
            cairo_fill(cr);

            roundedRect(cr, -w * 0.5, -h * 0.5, w, h, 5.2);
            cairo_set_source_rgba(cr, 0.975, 0.972, 0.952, alpha);
            cairo_fill_preserve(cr);
            cairo_set_source_rgba(cr, 0.16, 0.16, 0.18, alpha);
            cairo_set_line_width(cr, 1.45);
            cairo_stroke(cr);

            cairo_set_font_size(cr, glyphLen <= 1 ? 11.5 : 9.8);
            cairo_text_extents_t ext;
            cairo_text_extents(cr, b.label.c_str(), &ext);
            cairo_set_source_rgba(cr, 0.12, 0.12, 0.14, alpha);
            cairo_move_to(cr, -(ext.width * 0.5 + ext.x_bearing), -(ext.height * 0.5 + ext.y_bearing));
            cairo_show_text(cr, b.label.c_str());

            cairo_restore(cr);
        }
    }

    // MARK: - Sparkles & Sleep Z

    static void drawSparkles(cairo_t* cr, const CatPhysics& physics, RGBA c) {
        for (const auto& sp : physics.sparkles) {
            double p = std::min(1.0, (double)(sp.age / sp.lifetime));
            double alpha = std::sin(p * PI) * 0.85;
            if (alpha < 0.02) continue;

            cairo_save(cr);
            setCol(cr, c, alpha);
            if (sp.isSleepZ) {
                double swayX = std::sin(p * PI * 2.2) * 5.0;
                cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
                cairo_set_font_size(cr, (sp.isLargeZ ? 13.0 : 10.5) + p * 3.5);
                cairo_move_to(cr, sp.position.x + swayX, sp.position.y);
                cairo_show_text(cr, sp.isLargeZ ? "Z" : "z");
            } else {
                double r = 3.5 + p * 1.5;
                cairo_translate(cr, sp.position.x, sp.position.y);
                cairo_move_to(cr, 0, -r);
                quadCurveTo(cr, 0, -r, 0.8, -0.8, r, 0);
                quadCurveTo(cr, r, 0, 0.8, 0.8, 0, r);
                quadCurveTo(cr, 0, r, -0.8, 0.8, -r, 0);
                quadCurveTo(cr, -r, 0, -0.8, -0.8, 0, -r);
                cairo_close_path(cr);
                cairo_fill(cr);
            }
            cairo_restore(cr);
        }
    }
};
