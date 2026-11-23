import Foundation
import CoreGraphics
import AppKit

enum CatHitZone {
    case none
    case head
    case body
    case permissionPill
}

enum CatRenderer {
    static let catBlack = NSColor(calibratedRed: 0.085, green: 0.085, blue: 0.095, alpha: 1.0)
    static let contourMint = NSColor(calibratedRed: 0.82, green: 0.92, blue: 0.89, alpha: 0.76)
    static let whiskerColor = NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.92, alpha: 0.72)

    // Siamese Seal-Point Palette (挖煤小暹罗: 暖燕麦奶白躯干 + 浓郁可可焦糖重点色)
    static let siameseCream   = NSColor(calibratedRed: 0.945, green: 0.905, blue: 0.835, alpha: 1.0) // #F1E7D5
    static let siameseLatte   = NSColor(calibratedRed: 0.865, green: 0.795, blue: 0.695, alpha: 1.0) // #DDCBB1
    static let siameseMocha   = NSColor(calibratedRed: 0.45,  green: 0.34,  blue: 0.27,  alpha: 1.0) // #735745
    static let siamesePoint   = NSColor(calibratedRed: 0.175, green: 0.128, blue: 0.105, alpha: 1.0) // #2D211B
    static let siameseOutline = NSColor(calibratedRed: 0.26,  green: 0.19,  blue: 0.155, alpha: 0.88)
    static let siameseWhisker = NSColor(calibratedRed: 0.36,  green: 0.27,  blue: 0.22,  alpha: 0.68)

    static let permissionPillRect = CGRect(x: 92, y: 294, width: 176, height: 22)

    /// Hit test in 360x320 logical canvas coordinates for smart click-through & petting.
    static func hitTest(point p: CGPoint, physics: CatPhysics, showPermissionPill: Bool) -> CatHitZone {
        if showPermissionPill && permissionPillRect.insetBy(dx: -4, dy: -4).contains(p) {
            return .permissionPill
        }

        let cx = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let shiftY = physics.bodyShiftY.value
        let breath = physics.currentBreathOffset
        let headCenter = CGPoint(x: cx + physics.bodyTilt.value * 42, y: 124 + shiftY + physics.headOffsetY.value + breath)

        // Head hit ellipse (generous for cozy petting)
        let hdx = (p.x - headCenter.x) / 48.0
        let hdy = (p.y - headCenter.y) / 42.0
        if hdx * hdx + hdy * hdy <= 1.0 {
            return .head
        }

        // Torso + keyboard area hit check
        let bdx = (p.x - cx) / 58.0
        let bdy = (p.y - (196.0 + shiftY)) / 56.0
        if bdx * bdx + bdy * bdy <= 1.0 {
            return .body
        }

        // Desk peripheral area (only active when keyboard, laptop, or mouse is shown)
        let hw = HardwareMonitor.shared
        if hw.hasAnyKeyboardSurface || hw.shouldShowExternalMouse {
            let kbRect = CGRect(x: 58, y: 232, width: 242, height: 70)
            if kbRect.contains(p) {
                return .body
            }
        }

        return .none
    }

    /// Main 60fps draw routine in flipped 360x320 logical coordinate space.
    static func draw(in ctx: CGContext, physics: CatPhysics, showPermissionPill: Bool, appearance overrideAppearance: CatAppearance? = nil) {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let settings = CatSettings.shared
        let hw = HardwareMonitor.shared
        let appearance = overrideAppearance ?? settings.appearance
        let breath = physics.currentBreathOffset
        let shiftY = physics.bodyShiftY.value
        let seatX = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let seatY = CatPhysics.seatAnchor.y + shiftY

        // 1. External Mouse (only drawn when actually connected or forced in settings)
        if hw.shouldShowExternalMouse {
            drawMouse(in: ctx, physics: physics, theme: settings.keyboardTheme)
        }

        // 2. Desk Keyboard OR Apple Laptop C-Side (matched to MacBook enclosure color)
        if hw.shouldShowLaptop {
            drawLaptopCSide(
                in: ctx,
                physics: physics,
                color: hw.effectiveLaptopColor,
                glowColor: appearance.eyeGlowColor
            )
        } else if hw.shouldShowExternalKeyboard {
            drawKeyboard(in: ctx, physics: physics, theme: settings.keyboardTheme, glowColor: appearance.eyeGlowColor)
        }

        // 3. Cat Tail (behind body — routes to dedicated LongFurRenderer plume pipeline for medium/long fur!)
        let useLongFurPipeline = appearance.furLength >= 0.30
        if useLongFurPipeline {
            LongFurRenderer.drawTail(in: ctx, seatX: seatX, seatY: seatY, physics: physics, appearance: appearance)
        } else {
            drawTail(in: ctx, seatX: seatX, seatY: seatY, physics: physics, appearance: appearance)
        }

        // 4. 3D-Projected Ears (behind crown silhouette — dedicated plush ear pipeline for long fur!)
        let headCenter = CGPoint(
            x: seatX + physics.bodyTilt.value * 36 + physics.headYaw.value * 7.5,
            y: 126 + shiftY + physics.headOffsetY.value + physics.headPitch.value * 4.8 + breath * 1.1
        )
        if useLongFurPipeline {
            LongFurRenderer.drawEarsLayer(in: ctx, center: headCenter, physics: physics, appearance: appearance)
        } else {
            drawEarsLayer(in: ctx, center: headCenter, physics: physics, appearance: appearance)
        }

        // 5. Unified Silhouette (sleek short-hair pipeline OR dedicated continuous LongFurRenderer pipeline!)
        if useLongFurPipeline {
            LongFurRenderer.drawUnifiedSilhouette(
                in: ctx,
                seatX: seatX,
                seatY: seatY,
                headCenter: headCenter,
                breath: breath,
                physics: physics,
                appearance: appearance
            )
        } else {
            drawUnifiedSilhouette(
                in: ctx,
                seatX: seatX,
                seatY: seatY,
                headCenter: headCenter,
                breath: breath,
                physics: physics,
                appearance: appearance
            )
        }

        // 5b. Configurable Necktie / Bow Tie Accessory (drawn on chest, behind front paws)
        if settings.showTie {
            drawTieAccessory(
                in: ctx,
                seatX: seatX,
                headCenter: headCenter,
                breath: breath,
                physics: physics,
                style: settings.tieStyle,
                colorTheme: settings.tieColor,
                pattern: settings.tiePattern,
                appearance: appearance
            )
        }

        // 6. Hind Foot (3rd simultaneous key easter egg!)
        if physics.hindFootActive.value > 0.03 {
            drawHindFoot(in: ctx, seatX: seatX, seatY: seatY, physics: physics, appearance: appearance)
        }

        // 7. 2.5D Turning Head Features: Luminous Eyes (with Sleep / Tired states) & Whiskers
        drawHeadFeatures(in: ctx, center: headCenter, physics: physics, appearance: appearance)

        // 8. Front Arms / Paws (over torso & keyboard/mouse with auto-contrast outlines / pattern socks!)
        drawFrontPaws(in: ctx, seatX: seatX, seatY: seatY, breath: breath, physics: physics, appearance: appearance)

        // 8b. Apple Laptop Transparent A & B Side (open display lid drawn transparently so cat & paws remain unobstructed!)
        if hw.shouldShowLaptop {
            drawLaptopTransparentLid(in: ctx, color: hw.effectiveLaptopColor)
        }

        // 9. Floating Mechanical Keycap Badges
        if settings.showKeyBadges {
            drawFloatingKeycaps(in: ctx, physics: physics)
        }

        // 10. Subtle Petting Sparkles / Sleep Z
        drawSparkles(in: ctx, physics: physics, accentColor: appearance.eyeColor.nsColor)

        // 11. Optional non-intrusive Permission Pill if global monitoring not yet granted
        if showPermissionPill {
            drawPermissionPill(in: ctx)
        }

        ctx.restoreGState()
    }

    // MARK: - Mini White Mouse

    private static func drawMouse(in ctx: CGContext, physics: CatPhysics, theme: KeyboardTheme) {
        let mouseAnchorX = CatPhysics.mouseBaseCenter.x - (HardwareMonitor.shared.shouldShowLaptop ? 12.0 : 0.0)
        let center = CGPoint(
            x: mouseAnchorX + physics.mouseOffset.point.x,
            y: CatPhysics.mouseBaseCenter.y + physics.mouseOffset.point.y
        )
        let pressShift = max(physics.mousePressLeft.value, physics.mousePressRight.value) * 1.6

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y + pressShift)
        ctx.rotate(by: 0.22) // angled naturally for the cat's right paw (facing the cat!)

        // Soft underside shadow
        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.24).cgColor)
        ctx.fillEllipse(in: CGRect(x: -13.5, y: -13.5 + 4.0, width: 27, height: 31))
        ctx.restoreGState()

        let bodyRect = CGRect(x: -13.5, y: -16.5, width: 27, height: 33)
        let bodyColor: NSColor
        let borderColor: NSColor
        let wheelColor: NSColor
        switch theme {
        case .classicMilk:
            bodyColor = NSColor(calibratedRed: 0.955, green: 0.950, blue: 0.925, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.96, green: 0.69, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            bodyColor = NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.78, green: 0.95, blue: 0.25, alpha: 1.0)
        case .retroCream:
            bodyColor = NSColor(calibratedRed: 0.89, green: 0.87, blue: 0.82, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.20, green: 0.19, blue: 0.18, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        // Mouse body (palm-rest dome toward cat at top, click buttons & scroll wheel away from cat at bottom!)
        ctx.setFillColor(bodyColor.cgColor)
        ctx.fillEllipse(in: bodyRect)

        // Subtle click flash highlight (cat-facing: left button = inner right side, right button = outer left side!)
        if physics.mousePressLeft.value > 0.05 {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.setFillColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.38 * physics.mousePressLeft.value).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 14, height: 17))
            ctx.restoreGState()
        }
        if physics.mousePressRight.value > 0.05 {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.setFillColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.38 * physics.mousePressRight.value).cgColor)
            ctx.fill(CGRect(x: -14, y: 0, width: 14, height: 17))
            ctx.restoreGState()
        }

        // Button split seam pointing forward (bottom, away from cat!)
        ctx.setStrokeColor(borderColor.withAlphaComponent(0.32).cgColor)
        ctx.setLineWidth(1.05)
        ctx.move(to: CGPoint(x: 0, y: 16))
        ctx.addLine(to: CGPoint(x: 0, y: 1.5))
        ctx.strokePath()

        // Signature amber scroll wheel on the front (bottom) half facing away from cat
        let wheelRect = CGRect(x: -1.9, y: 2.5, width: 3.8, height: 8.5)
        let wheelPath = CGPath(roundedRect: wheelRect, cornerWidth: 1.9, cornerHeight: 1.9, transform: nil)
        ctx.setFillColor(wheelColor.cgColor)
        ctx.addPath(wheelPath)
        ctx.fillPath()

        // Outer crisp outline
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(1.7)
        ctx.strokeEllipse(in: bodyRect)

        ctx.restoreGState()
    }

    // MARK: - Mini Angled 65% Mechanical Keyboard (facing the cat!)

    private static func drawKeyboard(
        in ctx: CGContext,
        physics: CatPhysics,
        theme: KeyboardTheme,
        glowColor: NSColor
    ) {
        let tl = KeyboardLayout.screenQuadPoint(su: -0.025, sv: -0.08)
        let tr = KeyboardLayout.screenQuadPoint(su: 1.025, sv: -0.08)
        let bl = KeyboardLayout.screenQuadPoint(su: -0.032, sv: 1.08)
        let br = KeyboardLayout.screenQuadPoint(su: 1.032, sv: 1.08)

        let caseDepth: CGFloat = 6.5

        // Soft ambient drop shadow beneath keyboard
        ctx.saveGState()
        let shadowPath = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth + 2),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth + 2),
            br: CGPoint(x: br.x, y: br.y + caseDepth + 3),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth + 3),
            radius: 6
        )
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
        ctx.addPath(shadowPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Dark 3D chassis lower lip
        let baseColor: NSColor
        let deckColor: NSColor
        let keyColor: NSColor
        let keyBorderColor: NSColor
        let accentColor: NSColor

        switch theme {
        case .classicMilk:
            baseColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.968, green: 0.964, blue: 0.942, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.78, green: 0.77, blue: 0.74, alpha: 0.75)
            accentColor = NSColor(calibratedRed: 0.97, green: 0.70, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            baseColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.21, green: 0.22, blue: 0.25, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.95)
            accentColor = NSColor(calibratedRed: 0.77, green: 0.94, blue: 0.25, alpha: 1.0)
        case .retroCream:
            baseColor = NSColor(calibratedRed: 0.25, green: 0.24, blue: 0.22, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.33, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.82, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.68, green: 0.65, blue: 0.60, alpha: 0.85)
            accentColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        let lowerChassis = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth),
            br: CGPoint(x: br.x, y: br.y + caseDepth),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth),
            radius: 5.5
        )
        ctx.setFillColor(baseColor.cgColor)
        ctx.addPath(lowerChassis)
        ctx.fillPath()

        let topChassis = roundedQuadPath(tl: tl, tr: tr, br: br, bl: bl, radius: 5.0)
        ctx.setFillColor(deckColor.cgColor)
        ctx.addPath(topChassis)
        ctx.fillPath()

        // Individual keycaps — tight clean mechanical spacing matching the reference video
        let padU: CGFloat = 0.0028
        let padV: CGFloat = 0.014
        let glowBaseColor = glowColor

        for cap in KeyboardLayout.keycaps {
            let glow = physics.keyGlow[cap.key] ?? 0
            // 180° rotated to face the cat: su = 1 - u, sv = 1 - v
            let su0 = (1.0 - (cap.xUnits + cap.widthUnits)) + padU
            let su1 = (1.0 - cap.xUnits) - padU
            let sv0 = (1.0 - CGFloat(cap.row + 1) / 5.0) + padV
            let sv1 = (1.0 - CGFloat(cap.row) / 5.0) - padV

            let pressDy = glow * 1.9
            let kTL = offsetY(KeyboardLayout.screenQuadPoint(su: su0, sv: sv0), pressDy)
            let kTR = offsetY(KeyboardLayout.screenQuadPoint(su: su1, sv: sv0), pressDy)
            let kBR = offsetY(KeyboardLayout.screenQuadPoint(su: su1, sv: sv1), pressDy)
            let kBL = offsetY(KeyboardLayout.screenQuadPoint(su: su0, sv: sv1), pressDy)

            let kPath = roundedQuadPath(tl: kTL, tr: kTR, br: kBR, bl: kBL, radius: 1.6)

            var fill = cap.isAmberAccent ? accentColor : keyColor
            if glow > 0.02 {
                fill = blendColor(fill, glowBaseColor, t: glow * 0.55)
            }

            ctx.setFillColor(fill.cgColor)
            ctx.addPath(kPath)
            ctx.fillPath()

            ctx.setStrokeColor(keyBorderColor.cgColor)
            ctx.setLineWidth(0.65)
            ctx.addPath(kPath)
            ctx.strokePath()
        }

        // Signature soft chartreuse backlit glow halos on active keys!
        for (key, glow) in physics.keyGlow where glow > 0.05 {
            let center = KeyboardLayout.canvasPoint(for: key)
            drawRadialGlow(
                in: ctx,
                center: center,
                radius: 17.0 + glow * 6.0,
                color: glowBaseColor.withAlphaComponent(0.36 * glow)
            )
        }
    }

    // MARK: - Apple Laptop C-Side (Unibody Deck + Trackpad + Black Scissor Keyboard)

    private static func drawLaptopCSide(
        in ctx: CGContext,
        physics: CatPhysics,
        color: MacBookColor,
        glowColor: NSColor
    ) {
        let pal = color.palette

        // C-side unibody deck extends toward the cat (sv = -0.34) for palm rest & Force Touch trackpad,
        // and slightly wider left/right for MacBook speaker grilles.
        let tl = KeyboardLayout.screenQuadPoint(su: -0.09, sv: -0.34)
        let tr = KeyboardLayout.screenQuadPoint(su: 1.09, sv: -0.34)
        let bl = KeyboardLayout.screenQuadPoint(su: -0.10, sv: 1.09)
        let br = KeyboardLayout.screenQuadPoint(su: 1.10, sv: 1.09)
        let lipDepth: CGFloat = 5.0

        // 1. Soft ambient desk shadow under laptop
        ctx.saveGState()
        let shadowPath = roundedQuadPath(
            tl: offsetY(tl, lipDepth + 2.5),
            tr: offsetY(tr, lipDepth + 2.5),
            br: offsetY(br, lipDepth + 3.5),
            bl: offsetY(bl, lipDepth + 3.5),
            radius: 7.5
        )
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.24).cgColor)
        ctx.addPath(shadowPath)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. Machined aluminum lower 3D lip
        let lowerPath = roundedQuadPath(
            tl: offsetY(tl, lipDepth),
            tr: offsetY(tr, lipDepth),
            br: offsetY(br, lipDepth),
            bl: offsetY(bl, lipDepth),
            radius: 7.0
        )
        ctx.saveGState()
        ctx.setFillColor(pal.chassisSide.cgColor)
        ctx.addPath(lowerPath)
        ctx.fillPath()
        ctx.restoreGState()

        // 3. Anodized aluminum C-side top surface with subtle metallic gradient
        let deckPath = roundedQuadPath(tl: tl, tr: tr, br: br, bl: bl, radius: 6.5)
        ctx.saveGState()
        ctx.addPath(deckPath)
        ctx.clip()
        let cs = CGColorSpaceCreateDeviceRGB()
        let gradColors = [pal.deckTop.cgColor, pal.deckBottom.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: cs, colors: gradColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: (tl.x + tr.x) * 0.5, y: tl.y),
                end: CGPoint(x: (bl.x + br.x) * 0.5, y: br.y),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        // Crisp chamfered aluminum edge
        ctx.saveGState()
        ctx.setStrokeColor(pal.borderEdge.cgColor)
        ctx.setLineWidth(1.1)
        ctx.addPath(deckPath)
        ctx.strokePath()
        ctx.restoreGState()

        // 4. Force Touch Trackpad (centered closest to the cat!)
        let tpTL = KeyboardLayout.screenQuadPoint(su: 0.28, sv: -0.29)
        let tpTR = KeyboardLayout.screenQuadPoint(su: 0.72, sv: -0.29)
        let tpBL = KeyboardLayout.screenQuadPoint(su: 0.275, sv: -0.05)
        let tpBR = KeyboardLayout.screenQuadPoint(su: 0.725, sv: -0.05)
        let tpPath = roundedQuadPath(tl: tpTL, tr: tpTR, br: tpBR, bl: tpBL, radius: 2.5)
        ctx.saveGState()
        let tpClick = max(physics.mousePressLeft.value, physics.mousePressRight.value)
        var tpFill = pal.trackpadFill
        if physics.leftPawOnTrackpad && tpClick > 0.04 {
            tpFill = blendColor(tpFill, glowColor, t: tpClick * 0.28)
        }
        ctx.setFillColor(tpFill.cgColor)
        ctx.addPath(tpPath)
        ctx.fillPath()
        ctx.setStrokeColor(pal.trackpadBorder.cgColor)
        ctx.setLineWidth(0.85)
        ctx.addPath(tpPath)
        ctx.strokePath()
        ctx.restoreGState()

        // 5. Left & Right MacBook speaker grilles flanking the keyboard well
        ctx.saveGState()
        ctx.setFillColor(pal.trackpadBorder.withAlphaComponent(0.45).cgColor)
        for sideU in [-0.055, 1.055] as [CGFloat] {
            for r in 0..<7 {
                let sv = 0.06 + CGFloat(r) * 0.14
                let pt = KeyboardLayout.screenQuadPoint(su: sideU, sv: sv)
                ctx.fillEllipse(in: CGRect(x: pt.x - 1.0, y: pt.y - 0.8, width: 2.0, height: 1.6))
            }
        }
        ctx.restoreGState()

        // 6. Recessed black MacBook keyboard well
        let wTL = KeyboardLayout.screenQuadPoint(su: -0.015, sv: -0.015)
        let wTR = KeyboardLayout.screenQuadPoint(su: 1.015, sv: -0.015)
        let wBL = KeyboardLayout.screenQuadPoint(su: -0.020, sv: 1.015)
        let wBR = KeyboardLayout.screenQuadPoint(su: 1.020, sv: 1.015)
        let wellPath = roundedQuadPath(tl: wTL, tr: wTR, br: wBR, bl: wBL, radius: 3.0)
        ctx.saveGState()
        ctx.setFillColor(pal.keyWell.cgColor)
        ctx.addPath(wellPath)
        ctx.fillPath()
        ctx.restoreGState()

        // 7. Flat black MacBook scissor-switch keycaps with subtle backlit glow when pressed
        let padU: CGFloat = 0.0032
        let padV: CGFloat = 0.016
        let glowBaseColor = glowColor

        for cap in KeyboardLayout.keycaps {
            let glow = physics.keyGlow[cap.key] ?? 0
            let su0 = (1.0 - (cap.xUnits + cap.widthUnits)) + padU
            let su1 = (1.0 - cap.xUnits) - padU
            let sv0 = (1.0 - CGFloat(cap.row + 1) / 5.0) + padV
            let sv1 = (1.0 - CGFloat(cap.row) / 5.0) - padV

            let pressDy = glow * 1.1
            let kTL = offsetY(KeyboardLayout.screenQuadPoint(su: su0, sv: sv0), pressDy)
            let kTR = offsetY(KeyboardLayout.screenQuadPoint(su: su1, sv: sv0), pressDy)
            let kBR = offsetY(KeyboardLayout.screenQuadPoint(su: su1, sv: sv1), pressDy)
            let kBL = offsetY(KeyboardLayout.screenQuadPoint(su: su0, sv: sv1), pressDy)
            let kPath = roundedQuadPath(tl: kTL, tr: kTR, br: kBR, bl: kBL, radius: 1.2)

            var fill = pal.keycap
            if glow > 0.02 {
                fill = blendColor(fill, glowBaseColor, t: glow * 0.62)
            }
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(kPath)
            ctx.fillPath()

            ctx.setStrokeColor(pal.keycapBorder.cgColor)
            ctx.setLineWidth(0.55)
            ctx.addPath(kPath)
            ctx.strokePath()
        }

        // Backlit keycap halo on active keys
        for (key, glow) in physics.keyGlow where glow > 0.05 {
            let center = KeyboardLayout.canvasPoint(for: key)
            drawRadialGlow(
                in: ctx,
                center: center,
                radius: 15.0 + glow * 5.0,
                color: glowBaseColor.withAlphaComponent(0.32 * glow)
            )
        }

        // 8. Dark clutch barrel hinge along the bottom edge (closest to viewer)
        let hTL = KeyboardLayout.screenQuadPoint(su: 0.09, sv: 1.035)
        let hTR = KeyboardLayout.screenQuadPoint(su: 0.91, sv: 1.035)
        let hBL = KeyboardLayout.screenQuadPoint(su: 0.09, sv: 1.095)
        let hBR = KeyboardLayout.screenQuadPoint(su: 0.91, sv: 1.095)
        let hingePath = roundedQuadPath(tl: hTL, tr: hTR, br: hBR, bl: hBL, radius: 1.6)
        ctx.saveGState()
        ctx.setFillColor(pal.hingeColor.cgColor)
        ctx.addPath(hingePath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - Apple Laptop Transparent A & B Side (Open Display Lid)

    /// Drawn translucently over the front hinge so the viewer sees the full open MacBook
    /// (A-side aluminum silhouette + B-side bezel/notch) without obstructing any cat or paw movement!
    private static func drawLaptopTransparentLid(in ctx: CGContext, color: MacBookColor) {
        let pal = color.palette

        // Bottom of lid attaches seamlessly to the C-side hinge edge
        let bl = KeyboardLayout.screenQuadPoint(su: -0.095, sv: 1.08)
        let br = KeyboardLayout.screenQuadPoint(su: 1.095, sv: 1.08)
        // Top of lid rises in front of the keyboard/lower chest (below the cat's head/eyes!)
        let lidHeight: CGFloat = 104.0
        let tl = CGPoint(x: bl.x + 2.0, y: bl.y - lidHeight)
        let tr = CGPoint(x: br.x - 2.0, y: br.y - lidHeight)

        let lidPath = roundedQuadPath(tl: tl, tr: tr, br: br, bl: bl, radius: 8.0)

        ctx.saveGState()

        // 1. Ultra-translucent tinted glass fill (keeps cat & paws 100% crisp underneath)
        ctx.setFillColor(pal.lidTint.cgColor)
        ctx.addPath(lidPath)
        ctx.fillPath()

        // 2. Subtle diagonal glass sheen reflection inside the transparent lid
        ctx.saveGState()
        ctx.addPath(lidPath)
        ctx.clip()
        let sheen = CGMutablePath()
        sheen.move(to: CGPoint(x: tl.x + 26, y: tl.y - 6))
        sheen.addLine(to: CGPoint(x: tl.x + 74, y: tl.y - 6))
        sheen.addLine(to: CGPoint(x: bl.x + 24, y: bl.y + 6))
        sheen.addLine(to: CGPoint(x: bl.x - 14, y: bl.y + 6))
        sheen.closeSubpath()
        ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.065).cgColor)
        ctx.addPath(sheen)
        ctx.fillPath()

        // Subtle B-side inner screen bezel outline + iconic MacBook notch silhouette at top center
        let inset: CGFloat = 5.5
        let bTL = CGPoint(x: tl.x + inset, y: tl.y + inset)
        let bTR = CGPoint(x: tr.x - inset, y: tr.y + inset)
        let bBR = CGPoint(x: br.x - inset, y: br.y - inset * 1.1)
        let bBL = CGPoint(x: bl.x + inset, y: bl.y - inset * 1.1)
        let bezelPath = roundedQuadPath(tl: bTL, tr: bTR, br: bBR, bl: bBL, radius: 4.0)
        ctx.setStrokeColor(pal.lidBorder.withAlphaComponent(0.22).cgColor)
        ctx.setLineWidth(0.9)
        ctx.addPath(bezelPath)
        ctx.strokePath()

        // Subtle camera notch hint at top center of transparent B-side
        let notchMidX = (bTL.x + bTR.x) * 0.5
        let notchMidY = (bTL.y + bTR.y) * 0.5
        let notchRect = CGRect(x: notchMidX - 13, y: notchMidY - 0.5, width: 26, height: 5.0)
        let notchPath = CGPath(roundedRect: notchRect, cornerWidth: 2.0, cornerHeight: 2.0, transform: nil)
        ctx.setFillColor(pal.lidBorder.withAlphaComponent(0.24).cgColor)
        ctx.addPath(notchPath)
        ctx.fillPath()

        // Faint translucent Apple emblem centered on the A-side back
        let logoCenter = CGPoint(
            x: (tl.x + tr.x + bl.x + br.x) * 0.25,
            y: (tl.y + tr.y + bl.y + br.y) * 0.25 - 1.0
        )
        drawTranslucentAppleEmblem(in: ctx, center: logoCenter, color: pal.logoColor)
        ctx.restoreGState()

        // 3. Crisp translucent metallic outer rim of the lid
        ctx.setStrokeColor(pal.lidBorder.cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(lidPath)
        ctx.strokePath()

        ctx.restoreGState()
    }

    private static func drawTranslucentAppleEmblem(in ctx: CGContext, center: CGPoint, color: NSColor) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.setFillColor(color.cgColor)

        // Minimalist stylized apple silhouette (compact & clean at small scale)
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0, y: -5.2))
        body.addCurve(to: CGPoint(x: 7.2, y: -1.5), control1: CGPoint(x: 3.8, y: -6.8), control2: CGPoint(x: 6.8, y: -4.4))
        // Iconic subtle bite on right side
        body.addCurve(to: CGPoint(x: 6.8, y: 4.5), control1: CGPoint(x: 4.6, y: 0.2), control2: CGPoint(x: 4.6, y: 3.4))
        body.addCurve(to: CGPoint(x: 0.2, y: 8.6), control1: CGPoint(x: 5.5, y: 7.8), control2: CGPoint(x: 2.4, y: 9.2))
        body.addCurve(to: CGPoint(x: -7.2, y: 3.0), control1: CGPoint(x: -2.4, y: 9.2), control2: CGPoint(x: -6.2, y: 7.4))
        body.addCurve(to: CGPoint(x: 0, y: -5.2), control1: CGPoint(x: -8.6, y: -2.6), control2: CGPoint(x: -4.2, y: -6.8))
        body.closeSubpath()
        ctx.addPath(body)
        ctx.fillPath()

        // Little tilted leaf on top
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: 0.2, y: -6.2))
        leaf.addQuadCurve(to: CGPoint(x: 3.8, y: -10.0), control: CGPoint(x: 0.6, y: -9.5))
        leaf.addQuadCurve(to: CGPoint(x: 0.2, y: -6.2), control: CGPoint(x: 3.6, y: -6.8))
        leaf.closeSubpath()
        ctx.addPath(leaf)
        ctx.fillPath()

        ctx.restoreGState()
    }

    // MARK: - Tail (with Pattern Markings & Long-Fur Plume Physics!)

    private static func drawTail(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat, physics: CatPhysics, appearance: CatAppearance) {
        let p = physics.tailPhase
        let hunt = max(0, min(1, physics.huntIntensity.value))
        let sleepCalm = 1.0 - physics.sleepiness * 0.65
        let fur = max(0, min(1, appearance.furLength))
        let swayX = physics.furSwayX.value
        let swayY = physics.furSwayY.value

        let wag1 = sin(p) * (8.0 + hunt * 5.5) * sleepCalm
        let wag2 = cos(p * 1.3) * (6.0 + hunt * 4.5) * sleepCalm
        let huntDrop = hunt * 14.0 + physics.sleepiness * 18.0
        let sleepCurlIn = physics.sleepiness * 14.0

        // Signature low sweep out to the right, then playful upward curl at the tip!
        let root = CGPoint(x: seatX + 34, y: seatY - 6)
        let c1 = CGPoint(x: seatX + 64 - sleepCurlIn * 0.3 + swayX * 0.3, y: seatY + 2 + wag1 * 0.35 + huntDrop * 0.4 + swayY * 0.3)
        let c2 = CGPoint(x: seatX + 66 - sleepCurlIn * 0.7 + wag2 * 0.4 + swayX * 0.8, y: seatY - 26 + wag1 * 0.7 + huntDrop + swayY * 0.7)
        let tip = CGPoint(x: seatX + 91 - sleepCurlIn + wag2 * 0.5 + swayX * 1.3, y: seatY - 30 + wag1 * 0.85 + huntDrop + swayY * 1.1)

        let baseColor: NSColor
        switch appearance.pattern {
        case .colorpoint: baseColor = appearance.secondaryColor.nsColor
        case .calico:     baseColor = appearance.tertiaryColor.nsColor
        default:          baseColor = appearance.primaryColor.nsColor
        }

        let tailWidth: CGFloat = 11.0 + fur * 8.5

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Subtle dark outline for light/medium tails
        if let outline = appearance.silhouetteOutlineColor {
            ctx.setStrokeColor(outline.cgColor)
            ctx.setLineWidth(tailWidth + 2.6)
            ctx.move(to: root)
            ctx.addCurve(to: tip, control1: c1, control2: c2)
            ctx.strokePath()
        }

        // Main tail stroke
        ctx.setStrokeColor(baseColor.cgColor)
        ctx.setLineWidth(tailWidth)
        ctx.move(to: root)
        ctx.addCurve(to: tip, control1: c1, control2: c2)
        ctx.strokePath()

        // Fluffy long-fur plume tufts along the tail curve!
        if fur > 0.12 {
            let tuftCount = 6
            let furColor = baseColor.blended(withFraction: 0.12, of: .white) ?? baseColor
            for i in 1...tuftCount {
                let t = CGFloat(i) / CGFloat(tuftCount + 1)
                let pt = cubicPoint(root, c1, c2, tip, t: t)
                let r = (5.2 + t * 5.2) * fur
                let lagX = swayX * (0.4 + t * 0.9)
                let lagY = swayY * (0.4 + t * 0.8) + 2.5 * fur
                let puffRect = CGRect(x: pt.x - r + lagX, y: pt.y - r * 0.85 + lagY, width: r * 2.0, height: r * 1.85)
                if let outline = appearance.silhouetteOutlineColor {
                    ctx.setFillColor(outline.withAlphaComponent(0.35).cgColor)
                    ctx.fillEllipse(in: puffRect.insetBy(dx: -0.9, dy: -0.9))
                }
                ctx.setFillColor(furColor.cgColor)
                ctx.fillEllipse(in: puffRect)
            }
        }

        // Pattern rings / spots on tail (Tabby stripes or Calico/Spotted accents)
        if appearance.pattern == .tabby || appearance.pattern == .spotted {
            ctx.setFillColor(appearance.secondaryColor.nsColor.withAlphaComponent(0.85).cgColor)
            for t in [0.28, 0.50, 0.72, 0.90] as [CGFloat] {
                let pt = cubicPoint(root, c1, c2, tip, t: t)
                let r = tailWidth * 0.36
                ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r * 0.85, width: r * 2.0, height: r * 1.7))
            }
        } else if appearance.pattern == .calico {
            ctx.setFillColor(appearance.secondaryColor.nsColor.cgColor)
            let pt = cubicPoint(root, c1, c2, tip, t: 0.55)
            let r = tailWidth * 0.45
            ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2.0, height: r * 2.0))
        } else if appearance.pattern == .tuxedo {
            // Cute white tail tip on Tuxedo!
            ctx.setFillColor(appearance.secondaryColor.nsColor.cgColor)
            let r = tailWidth * 0.46
            ctx.fillEllipse(in: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2.0, height: r * 2.0))
        }

        ctx.restoreGState()
    }

    // MARK: - Unified C1-Continuous Cat Silhouette + Fur Patterns + Long-Fur Fluff Physics

    private static func drawUnifiedSilhouette(
        in ctx: CGContext,
        seatX: CGFloat,
        seatY: CGFloat,
        headCenter: CGPoint,
        breath: CGFloat,
        physics: CatPhysics,
        appearance: CatAppearance
    ) {
        let yaw = physics.headYaw.value
        let pitch = physics.headPitch.value
        let hTilt = physics.headTilt.value
        let bTilt = physics.bodyTilt.value
        let fur = max(0, min(1, appearance.furLength))

        let cH = cos(hTilt), sH = sin(hTilt)
        func H(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            CGPoint(
                x: headCenter.x + lx * cH - ly * sH,
                y: headCenter.y + lx * sH + ly * cH
            )
        }

        let cB = cos(bTilt), sB = sin(bTilt)
        let sy = physics.bodySquash.value
        let sx = 1.0 + (1.0 - sy) * 0.55
        func B(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            let rx = lx * sx
            let ry = ly * sy
            return CGPoint(
                x: seatX + rx * cB - ry * sB,
                y: seatY + rx * sB + ry * cB
            )
        }

        let cheekShift = yaw * 3.0
        let crownDrop = pitch * 2.0
        // Long fur subtly plumps the cheeks and torso silhouette!
        let fluffW: CGFloat = fur * 4.5
        let leftCheekX: CGFloat = -42.5 - fluffW * 0.85 + cheekShift * 0.4
        let rightCheekX: CGFloat = 42.5 + fluffW * 0.85 + cheekShift * 0.4

        // ONE single tangent-continuous closed cubic Bezier path
        let crown  = H(cheekShift * 0.2, -30 - fur * 1.8 + crownDrop)
        let rCheek = H(rightCheekX, 5)
        let rHip   = B(49.0 + fluffW, -14)
        let rBot   = B(24.0 + fluffW * 0.4, 12)
        let lBot   = B(-24.0 - fluffW * 0.4, 12)
        let lHip   = B(-49.0 - fluffW, -14)
        let lCheek = H(leftCheekX, 5)

        let path = CGMutablePath()
        path.move(to: crown)
        path.addCurve(to: rCheek, control1: H(26 + fluffW * 0.5 + cheekShift * 0.3, -30 + crownDrop), control2: H(rightCheekX + 1.5, -14))
        path.addCurve(to: rHip,   control1: H(rightCheekX - 2.5, 24), control2: B(51.5 + fluffW, -48 + breath * 0.5))
        path.addCurve(to: rBot,   control1: B(47.0 + fluffW, 5), control2: B(36.0 + fluffW * 0.6, 12))
        path.addLine(to: lBot)
        path.addCurve(to: lHip,   control1: B(-36.0 - fluffW * 0.6, 12), control2: B(-47.0 - fluffW, 5))
        path.addCurve(to: lCheek, control1: B(-51.5 - fluffW, -48 + breath * 0.5), control2: H(leftCheekX + 2.5, 24))
        path.addCurve(to: crown,  control1: H(leftCheekX - 1.5, -14), control2: H(-26 - fluffW * 0.5 + cheekShift * 0.3, -30 + crownDrop))
        path.closeSubpath()

        // 1. Base coat fill + clipped pattern markings
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        let cs = CGColorSpaceCreateDeviceRGB()
        if appearance.isDarkCoat {
            ctx.setFillColor(appearance.primaryColor.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 360, height: 320))
        } else {
            let topCol = appearance.primaryColor.nsColor
            let botCol = appearance.primaryColor.darkened(by: 0.09)
            let bodyColors = [topCol.cgColor, botCol.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: bodyColors, locations: [0.15, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: seatX, y: headCenter.y - 34),
                    end: CGPoint(x: seatX, y: seatY + 18),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        }

        drawClippedFurPattern(
            in: ctx,
            headCenter: headCenter,
            hTilt: hTilt,
            yaw: yaw,
            pitch: pitch,
            B: B,
            H: H,
            appearance: appearance
        )

        ctx.restoreGState() // end silhouette clip

        // Crisp subtle outline for medium/light coats so they pop on both light & dark wallpapers!
        if let outline = appearance.silhouetteOutlineColor {
            ctx.saveGState()
            ctx.setStrokeColor(outline.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Tucked hind paws peeking softly along bottom edge
        ctx.saveGState()
        ctx.translateBy(x: seatX, y: seatY)
        ctx.rotate(by: bTilt)
        ctx.scaleBy(x: sx, y: sy)
        let hindPawColor: NSColor
        switch appearance.pattern {
        case .colorpoint, .tuxedo: hindPawColor = appearance.secondaryColor.nsColor
        default:                   hindPawColor = appearance.primaryColor.nsColor
        }
        ctx.setFillColor(hindPawColor.cgColor)

        ctx.fillEllipse(in: CGRect(x: -35, y: 3, width: 17, height: 11))
        if physics.hindFootActive.value < 0.35 {
            ctx.fillEllipse(in: CGRect(x: 18, y: 3, width: 17, height: 11))
        }

        // Subtle bottom rim highlights on tucked haunches
        let rimColor = appearance.limbSeparationColor.withAlphaComponent(0.58)
        ctx.setStrokeColor(rimColor.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: -26.5, y: 8.5), radius: 7.5, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
        ctx.strokePath()
        if physics.hindFootActive.value < 0.35 {
            ctx.addArc(center: CGPoint(x: 26.5, y: 8.5), radius: 7.5, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Shared 2.5D clipped fur-pattern renderer used by both the short-hair and LongFurRenderer pipelines.
    static func drawClippedFurPattern(
        in ctx: CGContext,
        headCenter: CGPoint,
        hTilt: CGFloat,
        yaw: CGFloat,
        pitch: CGFloat,
        B: (CGFloat, CGFloat) -> CGPoint,
        H: (CGFloat, CGFloat) -> CGPoint,
        appearance: CatAppearance
    ) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let yawRad = yaw * 0.50
        let pitchRad = pitch * 0.36

        switch appearance.pattern {
        case .solid:
            break

        case .colorpoint:
            ctx.saveGState()
            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: hTilt)
            let maskCenter = projectHead3D(x: 0, y: 2.5, z: 27.0, yawRad: yawRad, pitchRad: pitchRad).pt
            let maskScaleX = max(0.76, cos(yawRad * 0.7))
            let maskScaleY = max(0.82, cos(pitchRad * 0.7))
            ctx.saveGState()
            ctx.translateBy(x: maskCenter.x, y: maskCenter.y)
            ctx.scaleBy(x: maskScaleX * 1.18, y: maskScaleY * 0.88)
            let ptCol = appearance.secondaryColor.nsColor
            let midCol = appearance.tertiaryColor.nsColor
            let maskColors = [
                ptCol.cgColor,
                ptCol.withAlphaComponent(0.95).cgColor,
                midCol.withAlphaComponent(0.72).cgColor,
                midCol.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let maskGrad = CGGradient(colorsSpace: cs, colors: maskColors, locations: [0.0, 0.44, 0.74, 1.0]) {
                ctx.drawRadialGradient(
                    maskGrad,
                    startCenter: .zero, startRadius: 2,
                    endCenter: .zero, endRadius: 31,
                    options: []
                )
            }
            ctx.restoreGState()
            ctx.restoreGState()

        case .tuxedo:
            let bibCol = appearance.secondaryColor.nsColor
            ctx.saveGState()
            ctx.setFillColor(bibCol.cgColor)
            let bib = CGMutablePath()
            let chestTop = H(yaw * 5.0, 22)
            let bibL = B(-22, -32)
            let bibR = B(22, -32)
            let bibBot = B(0, 14)
            bib.move(to: chestTop)
            bib.addQuadCurve(to: bibR, control: H(20 + yaw * 4.0, 34))
            bib.addQuadCurve(to: bibBot, control: B(26, -4))
            bib.addQuadCurve(to: bibL, control: B(-26, -4))
            bib.addQuadCurve(to: chestTop, control: H(-20 + yaw * 4.0, 34))
            bib.closeSubpath()
            ctx.addPath(bib)
            ctx.fillPath()

            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: hTilt)
            let muzzle = projectHead3D(x: 0, y: 14.0, z: 27.0, yawRad: yawRad, pitchRad: pitchRad).pt
            ctx.fillEllipse(in: CGRect(x: muzzle.x - 16, y: muzzle.y - 8, width: 32, height: 19))
            ctx.restoreGState()

        case .tabby:
            let stripeCol = appearance.secondaryColor.nsColor
            let bellyCol = appearance.tertiaryColor.nsColor

            ctx.saveGState()
            ctx.setFillColor(bellyCol.withAlphaComponent(0.75).cgColor)
            let bellyCenter = B(0, -18)
            ctx.fillEllipse(in: CGRect(x: bellyCenter.x - 24, y: bellyCenter.y - 26, width: 48, height: 58))
            ctx.restoreGState()

            ctx.saveGState()
            ctx.setStrokeColor(stripeCol.withAlphaComponent(0.84).cgColor)
            ctx.setLineCap(.round)
            for side in [-1.0, 1.0] as [CGFloat] {
                for idx in 0..<3 {
                    let yOff = -44.0 + CGFloat(idx) * 16.0
                    let p0 = B(side * 58, yOff)
                    let p1 = B(side * 24, yOff + 5.0)
                    let ctrl = B(side * 38, yOff - 4.0)
                    ctx.setLineWidth(5.4 - CGFloat(idx) * 0.4)
                    ctx.move(to: p0)
                    ctx.addQuadCurve(to: p1, control: ctrl)
                    ctx.strokePath()
                }
            }
            ctx.restoreGState()

            ctx.saveGState()
            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: hTilt)
            ctx.setStrokeColor(stripeCol.withAlphaComponent(0.88).cgColor)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(2.8)
            for dx in [-7.5, 0.0, 7.5] as [CGFloat] {
                let topP = projectHead3D(x: dx * 1.1, y: -25.0, z: 22.0, yawRad: yawRad, pitchRad: pitchRad).pt
                let botP = projectHead3D(x: dx * 0.75, y: -14.5, z: 26.0, yawRad: yawRad, pitchRad: pitchRad).pt
                ctx.move(to: topP)
                ctx.addLine(to: botP)
            }
            ctx.strokePath()
            ctx.setLineWidth(2.5)
            for sign in [-1.0, 1.0] as [CGFloat] {
                for rowY in [4.0, 10.5] as [CGFloat] {
                    let p0 = projectHead3D(x: sign * 39.0, y: rowY - 1.5, z: 10.0, yawRad: yawRad, pitchRad: pitchRad).pt
                    let p1 = projectHead3D(x: sign * 25.0, y: rowY + 1.5, z: 22.0, yawRad: yawRad, pitchRad: pitchRad).pt
                    ctx.move(to: p0)
                    ctx.addLine(to: p1)
                }
            }
            ctx.strokePath()
            ctx.restoreGState()

        case .calico:
            let patch1 = appearance.secondaryColor.nsColor
            let patch2 = appearance.tertiaryColor.nsColor
            ctx.saveGState()
            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: hTilt)
            let pL = projectHead3D(x: -22.0, y: -15.0, z: 18.0, yawRad: yawRad, pitchRad: pitchRad).pt
            ctx.setFillColor(patch1.cgColor)
            ctx.fillEllipse(in: CGRect(x: pL.x - 24, y: pL.y - 20, width: 44, height: 38))
            let pR = projectHead3D(x: 24.0, y: -12.0, z: 17.0, yawRad: yawRad, pitchRad: pitchRad).pt
            ctx.setFillColor(patch2.cgColor)
            ctx.fillEllipse(in: CGRect(x: pR.x - 20, y: pR.y - 18, width: 42, height: 34))
            ctx.restoreGState()

            ctx.saveGState()
            let hipPatch1 = B(32, -26)
            ctx.setFillColor(patch1.cgColor)
            ctx.fillEllipse(in: CGRect(x: hipPatch1.x - 24, y: hipPatch1.y - 22, width: 48, height: 42))
            let hipPatch2 = B(-34, -10)
            ctx.setFillColor(patch2.cgColor)
            ctx.fillEllipse(in: CGRect(x: hipPatch2.x - 22, y: hipPatch2.y - 18, width: 44, height: 36))
            ctx.restoreGState()

        case .spotted:
            let spotCol = appearance.secondaryColor.nsColor
            ctx.saveGState()
            ctx.setFillColor(spotCol.cgColor)
            ctx.saveGState()
            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: hTilt)
            let hs1 = projectHead3D(x: -18, y: -17, z: 20, yawRad: yawRad, pitchRad: pitchRad).pt
            let hs2 = projectHead3D(x: 20, y: -14, z: 19, yawRad: yawRad, pitchRad: pitchRad).pt
            ctx.fillEllipse(in: CGRect(x: hs1.x - 12, y: hs1.y - 10, width: 24, height: 20))
            ctx.fillEllipse(in: CGRect(x: hs2.x - 9, y: hs2.y - 8, width: 18, height: 15))
            ctx.restoreGState()
            let spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (-30, -34, 24, 20), (28, -36, 20, 18), (34, -8, 26, 22), (-24, -4, 18, 16)
            ]
            for (bx, by, bw, bh) in spots {
                let pt = B(bx, by)
                ctx.fillEllipse(in: CGRect(x: pt.x - bw * 0.5, y: pt.y - bh * 0.5, width: bw, height: bh))
            }
            ctx.restoreGState()
        }
    }

    /// Swaying plush cheek tufts for medium/long-haired breeds (Ragdoll, Persian, Maine Coon!)
    private static func drawLongFurCheekTufts(
        in ctx: CGContext,
        headCenter: CGPoint,
        hTilt: CGFloat,
        yaw: CGFloat,
        fur: CGFloat,
        swayX: CGFloat,
        swayY: CGFloat,
        appearance: CatAppearance
    ) {
        ctx.saveGState()
        ctx.translateBy(x: headCenter.x, y: headCenter.y)
        ctx.rotate(by: hTilt)

        let baseCol = appearance.primaryColor.nsColor
        let outline = appearance.silhouetteOutlineColor

        for sign in [-1.0, 1.0] as [CGFloat] {
            let baseX = sign * (38.5 + fur * 2.0) + yaw * 2.0
            let tuftLen = 5.5 + fur * 10.5
            let tuft = CGMutablePath()
            // Soft downward-sweeping plush cheek fluff (rounded, natural feline mane)
            tuft.move(to: CGPoint(x: baseX - sign * 6.0, y: -1.0))
            tuft.addQuadCurve(
                to: CGPoint(x: baseX + sign * tuftLen + swayX * 0.65, y: 11.0 + fur * 2.5 + swayY * 0.65),
                control: CGPoint(x: baseX + sign * (tuftLen * 0.85), y: 2.0)
            )
            tuft.addQuadCurve(
                to: CGPoint(x: baseX + sign * (tuftLen * 0.72) + swayX * 0.85, y: 21.0 + fur * 4.5 + swayY * 0.85),
                control: CGPoint(x: baseX + sign * (tuftLen * 0.95), y: 17.0 + fur * 2.0)
            )
            tuft.addQuadCurve(
                to: CGPoint(x: baseX - sign * 7.0, y: 26.0 + fur * 2.0),
                control: CGPoint(x: baseX + sign * 2.0, y: 27.5 + fur * 2.0)
            )
            tuft.closeSubpath()

            ctx.setFillColor(baseCol.cgColor)
            ctx.addPath(tuft)
            ctx.fillPath()
            if let outline {
                ctx.setStrokeColor(outline.withAlphaComponent(0.75).cgColor)
                ctx.setLineWidth(1.25)
                ctx.addPath(tuft)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    /// Layered fluffy chest ruff / mane below the neck (feathered top, only strokes lower fur tips!)
    private static func drawLongFurChestRuff(
        in ctx: CGContext,
        seatX: CGFloat,
        headCenter: CGPoint,
        breath: CGFloat,
        tilt: CGFloat,
        fur: CGFloat,
        swayX: CGFloat,
        swayY: CGFloat,
        appearance: CatAppearance
    ) {
        let ruffX = seatX * 0.45 + headCenter.x * 0.55
        let ruffY = headCenter.y + 38.0 + breath * 0.4
        let ruffColor: NSColor
        switch appearance.pattern {
        case .tuxedo: ruffColor = appearance.secondaryColor.nsColor
        case .tabby:  ruffColor = appearance.tertiaryColor.nsColor
        default:
            ruffColor = appearance.isDarkCoat
                ? appearance.primaryColor.lightened(by: 0.06)
                : appearance.primaryColor.lightened(by: 0.16)
        }

        ctx.saveGState()
        ctx.translateBy(x: ruffX, y: ruffY)
        ctx.rotate(by: tilt)

        let spread: CGFloat = 20.0 + fur * 9.0
        let drop: CGFloat = 10.0 + fur * 13.0

        // Soft fill shape that melts seamlessly upward into the chest
        let ruffFill = CGMutablePath()
        ruffFill.move(to: CGPoint(x: -spread, y: -6.0))
        ruffFill.addQuadCurve(
            to: CGPoint(x: -spread * 0.52 + swayX * 0.5, y: drop * 0.82 + swayY * 0.6),
            control: CGPoint(x: -spread * 0.92, y: drop * 0.50)
        )
        ruffFill.addQuadCurve(
            to: CGPoint(x: swayX * 0.85, y: drop + swayY * 0.9),
            control: CGPoint(x: -spread * 0.22 + swayX * 0.65, y: drop * 0.68)
        )
        ruffFill.addQuadCurve(
            to: CGPoint(x: spread * 0.52 + swayX * 0.5, y: drop * 0.82 + swayY * 0.6),
            control: CGPoint(x: spread * 0.22 + swayX * 0.65, y: drop * 0.68)
        )
        ruffFill.addQuadCurve(
            to: CGPoint(x: spread, y: -6.0),
            control: CGPoint(x: spread * 0.92, y: drop * 0.50)
        )
        ruffFill.closeSubpath()

        ctx.setFillColor(ruffColor.withAlphaComponent(0.88).cgColor)
        ctx.addPath(ruffFill)
        ctx.fillPath()

        // Stroke ONLY the lower fluffy scalloped fur tips (no hard horizontal top line!)
        let edgeCol = appearance.isDarkCoat
            ? contourMint.withAlphaComponent(0.30 * fur)
            : appearance.primaryColor.darkened(by: 0.35).withAlphaComponent(0.42 * fur)
        ctx.setStrokeColor(edgeCol.cgColor)
        ctx.setLineWidth(1.15)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: -spread * 0.88, y: drop * 0.20))
        ctx.addQuadCurve(
            to: CGPoint(x: -spread * 0.52 + swayX * 0.5, y: drop * 0.82 + swayY * 0.6),
            control: CGPoint(x: -spread * 0.82, y: drop * 0.62)
        )
        ctx.addQuadCurve(
            to: CGPoint(x: swayX * 0.85, y: drop + swayY * 0.9),
            control: CGPoint(x: -spread * 0.22 + swayX * 0.65, y: drop * 0.68)
        )
        ctx.addQuadCurve(
            to: CGPoint(x: spread * 0.52 + swayX * 0.5, y: drop * 0.82 + swayY * 0.6),
            control: CGPoint(x: spread * 0.22 + swayX * 0.65, y: drop * 0.68)
        )
        ctx.addQuadCurve(
            to: CGPoint(x: spread * 0.88, y: drop * 0.20),
            control: CGPoint(x: spread * 0.82, y: drop * 0.62)
        )
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Configurable Necktie / Bow Tie Accessory (Style + Color + Scottish Tartan / Stripes / Polka Dots / Solid)

    private static func drawTieAccessory(
        in ctx: CGContext,
        seatX: CGFloat,
        headCenter: CGPoint,
        breath: CGFloat,
        physics: CatPhysics,
        style: TieStyle,
        colorTheme: TieColorTheme,
        pattern: TiePattern,
        appearance: CatAppearance
    ) {
        let pal = colorTheme.palette
        let yaw = physics.headYaw.value
        let neckX = seatX * 0.45 + headCenter.x * 0.55 + yaw * 4.5
        let neckY = headCenter.y + 30.5 + breath * 0.35
        let tilt = physics.bodyTilt.value * 0.65 + physics.headTilt.value * 0.35
        let outlineColor = (appearance.silhouetteOutlineColor ?? NSColor(calibratedWhite: 0.04, alpha: 0.86)).cgColor

        ctx.saveGState()
        ctx.translateBy(x: neckX, y: neckY)
        ctx.rotate(by: tilt)

        // 1. Subtle collar band curving naturally around the neck
        let collarPath = CGMutablePath()
        collarPath.move(to: CGPoint(x: -24.5, y: -3.5))
        collarPath.addQuadCurve(to: CGPoint(x: 24.5, y: -3.5), control: CGPoint(x: 0, y: 4.5))
        collarPath.addLine(to: CGPoint(x: 23.0, y: 1.5))
        collarPath.addQuadCurve(to: CGPoint(x: -23.0, y: 1.5), control: CGPoint(x: 0, y: 8.8))
        collarPath.closeSubpath()

        fillTieFabric(in: ctx, path: collarPath, bounds: CGRect(x: -26, y: -6, width: 52, height: 18), palette: pal, pattern: pattern)
        ctx.setStrokeColor(outlineColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(collarPath)
        ctx.strokePath()

        switch style {
        case .necktie:
            // Classic tapered necktie blade hanging down the chest
            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: -3.6, y: 5.5))
            blade.addLine(to: CGPoint(x: 3.6, y: 5.5))
            blade.addLine(to: CGPoint(x: 8.2, y: 27.0))
            blade.addLine(to: CGPoint(x: 0.0, y: 35.5))
            blade.addLine(to: CGPoint(x: -8.2, y: 27.0))
            blade.closeSubpath()

            // Subtle soft drop shadow beneath tie blade
            ctx.saveGState()
            ctx.translateBy(x: 0.6, y: 1.4)
            ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.25).cgColor)
            ctx.addPath(blade)
            ctx.fillPath()
            ctx.restoreGState()

            fillTieFabric(in: ctx, path: blade, bounds: CGRect(x: -10, y: 4, width: 20, height: 34), palette: pal, pattern: pattern)

            // Subtle 3D cylindrical silk sheen along the tie blade
            ctx.saveGState()
            ctx.addPath(blade)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let shadeColors = [
                NSColor(calibratedWhite: 0.0, alpha: 0.08).cgColor,
                NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor,
                NSColor(calibratedWhite: 0.0, alpha: 0.10).cgColor
            ] as CFArray
            if let shadeGrad = CGGradient(colorsSpace: cs, colors: shadeColors, locations: [0.0, 0.36, 1.0]) {
                ctx.drawLinearGradient(
                    shadeGrad,
                    start: CGPoint(x: -8.5, y: 20),
                    end: CGPoint(x: 8.5, y: 20),
                    options: []
                )
            }
            ctx.restoreGState()

            ctx.setStrokeColor(outlineColor)
            ctx.setLineWidth(1.1)
            ctx.setLineJoin(.round)
            ctx.addPath(blade)
            ctx.strokePath()

            // Rounded-trapezoid tie knot at the top center
            let knot = CGMutablePath()
            knot.move(to: CGPoint(x: -5.4, y: -1.0))
            knot.addQuadCurve(to: CGPoint(x: 5.4, y: -1.0), control: CGPoint(x: 0, y: -2.4))
            knot.addLine(to: CGPoint(x: 3.8, y: 6.4))
            knot.addQuadCurve(to: CGPoint(x: -3.8, y: 6.4), control: CGPoint(x: 0, y: 7.4))
            knot.closeSubpath()

            fillTieFabric(in: ctx, path: knot, bounds: CGRect(x: -7, y: -3, width: 14, height: 12), palette: pal, pattern: pattern)
            ctx.setStrokeColor(outlineColor)
            ctx.setLineWidth(1.05)
            ctx.addPath(knot)
            ctx.strokePath()

        case .bowTie:
            // Symmetrical left & right pleated bow tie wings
            for sign in [-1.0, 1.0] as [CGFloat] {
                let wing = CGMutablePath()
                wing.move(to: CGPoint(x: sign * 3.0, y: 0.2))
                wing.addQuadCurve(
                    to: CGPoint(x: sign * 16.5, y: -5.2),
                    control: CGPoint(x: sign * 10.2, y: -4.8)
                )
                wing.addQuadCurve(
                    to: CGPoint(x: sign * 17.5, y: 3.2),
                    control: CGPoint(x: sign * 19.2, y: -1.0)
                )
                wing.addQuadCurve(
                    to: CGPoint(x: sign * 15.2, y: 11.0),
                    control: CGPoint(x: sign * 18.6, y: 8.2)
                )
                wing.addQuadCurve(
                    to: CGPoint(x: sign * 3.0, y: 5.8),
                    control: CGPoint(x: sign * 9.5, y: 10.6)
                )
                wing.closeSubpath()

                // Soft shadow beneath wing
                ctx.saveGState()
                ctx.translateBy(x: 0.4, y: 1.3)
                ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.24).cgColor)
                ctx.addPath(wing)
                ctx.fillPath()
                ctx.restoreGState()

                fillTieFabric(
                    in: ctx,
                    path: wing,
                    bounds: CGRect(x: sign > 0 ? 1 : -20, y: -7, width: 19, height: 20),
                    palette: pal,
                    pattern: pattern
                )

                // Subtle pleat crease line radiating from center knot
                ctx.saveGState()
                ctx.addPath(wing)
                ctx.clip()
                ctx.setStrokeColor(NSColor(calibratedWhite: 0.0, alpha: 0.26).cgColor)
                ctx.setLineWidth(1.0)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: sign * 4.0, y: 3.0))
                ctx.addLine(to: CGPoint(x: sign * 11.5, y: 1.6))
                ctx.move(to: CGPoint(x: sign * 4.0, y: 3.6))
                ctx.addLine(to: CGPoint(x: sign * 11.0, y: 5.6))
                ctx.strokePath()
                ctx.restoreGState()

                ctx.setStrokeColor(outlineColor)
                ctx.setLineWidth(1.1)
                ctx.setLineJoin(.round)
                ctx.addPath(wing)
                ctx.strokePath()
            }

            // Plump rounded center bow-tie knot
            let bowKnotRect = CGRect(x: -4.4, y: -1.6, width: 8.8, height: 9.4)
            let bowKnot = CGPath(roundedRect: bowKnotRect, cornerWidth: 3.2, cornerHeight: 3.2, transform: nil)
            fillTieFabric(in: ctx, path: bowKnot, bounds: bowKnotRect.insetBy(dx: -1, dy: -1), palette: pal, pattern: pattern)
            ctx.setStrokeColor(outlineColor)
            ctx.setLineWidth(1.1)
            ctx.addPath(bowKnot)
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    private static func fillTieFabric(
        in ctx: CGContext,
        path: CGPath,
        bounds: CGRect,
        palette: TieColorTheme.Palette,
        pattern: TiePattern
    ) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        // Base color
        ctx.setFillColor(palette.base.cgColor)
        ctx.fill(bounds)

        switch pattern {
        case .scottishGrid:
            // Authentic 45° bias-cut Scottish Tartan plaid
            ctx.saveGState()
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.rotate(by: .pi / 4.0)
            let span: CGFloat = max(bounds.width, bounds.height) * 1.6
            let cell: CGFloat = 7.6

            // Wide dark-tone tartan bands (horizontal & vertical in rotated space)
            ctx.setFillColor(palette.dark.withAlphaComponent(0.54).cgColor)
            var pos = -span
            while pos <= span {
                ctx.fill(CGRect(x: pos, y: -span, width: 2.8, height: span * 2))
                ctx.fill(CGRect(x: -span, y: pos, width: span * 2, height: 2.8))
                pos += cell
            }

            // Soft accent intersections for crisp Scottish sett depth
            ctx.setFillColor(palette.accent.withAlphaComponent(0.42).cgColor)
            var xPos = -span
            while xPos <= span {
                var yPos = -span
                while yPos <= span {
                    ctx.fill(CGRect(x: xPos, y: yPos, width: 2.8, height: 2.8))
                    yPos += cell
                }
                xPos += cell
            }

            // Crisp thin light-ice over-check grid lines centered between dark bands
            ctx.setStrokeColor(palette.light.withAlphaComponent(0.88).cgColor)
            ctx.setLineWidth(0.75)
            pos = -span + cell * 0.5 + 1.4
            while pos <= span {
                ctx.move(to: CGPoint(x: pos, y: -span))
                ctx.addLine(to: CGPoint(x: pos, y: span))
                ctx.move(to: CGPoint(x: -span, y: pos))
                ctx.addLine(to: CGPoint(x: span, y: pos))
                pos += cell
            }
            ctx.strokePath()
            ctx.restoreGState()

        case .diagonalStripe:
            ctx.saveGState()
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.rotate(by: .pi / 4.0)
            let span: CGFloat = max(bounds.width, bounds.height) * 1.6
            let step: CGFloat = 7.2
            var pos = -span
            while pos <= span {
                ctx.setFillColor(palette.dark.withAlphaComponent(0.82).cgColor)
                ctx.fill(CGRect(x: pos, y: -span, width: 2.8, height: span * 2))
                ctx.setFillColor(palette.light.withAlphaComponent(0.90).cgColor)
                ctx.fill(CGRect(x: pos + 3.4, y: -span, width: 0.9, height: span * 2))
                pos += step
            }
            ctx.restoreGState()

        case .polkaDot:
            ctx.setFillColor(palette.light.withAlphaComponent(0.92).cgColor)
            let dx: CGFloat = 5.2
            let dy: CGFloat = 4.6
            var row = 0
            var y = bounds.minY - 2
            while y <= bounds.maxY + 2 {
                let offsetX: CGFloat = (row % 2 == 0) ? 0 : dx * 0.5
                var x = bounds.minX - 2 + offsetX
                while x <= bounds.maxX + 2 {
                    ctx.fillEllipse(in: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
                    x += dx
                }
                y += dy
                row += 1
            }

        case .solid:
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [palette.base.cgColor, palette.dark.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.1, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: bounds.midX, y: bounds.minY),
                    end: CGPoint(x: bounds.midX, y: bounds.maxY),
                    options: []
                )
            }
        }

        ctx.restoreGState()
    }

    private static func drawHindFoot(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat, physics: CatPhysics, appearance: CatAppearance) {
        let hip = CGPoint(x: seatX + 26, y: seatY + 2)
        let target = physics.hindFoot.point
        let mid = CGPoint(
            x: (hip.x + target.x) * 0.5 + 10,
            y: (hip.y + target.y) * 0.5 - 8
        )

        drawLimb(
            in: ctx,
            start: hip,
            control: mid,
            end: target,
            startWidth: 15.0,
            endWidth: 12.0,
            outlineOnLeftSide: true,
            outlineAlpha: 0.85 * physics.hindFootActive.value,
            appearance: appearance
        )
    }

    // MARK: - 2.5D Spherical Head Projection Helper

    /// Projects a 3D point on the cat's head ellipsoid rotated by (yawRad, pitchRad)
    /// into 2D head-local coordinates — creating true Live2D-style 2.5D head turning!
    static func projectHead3D(
        x: CGFloat, y: CGFloat, z: CGFloat,
        yawRad: CGFloat, pitchRad: CGFloat
    ) -> (pt: CGPoint, z: CGFloat) {
        // 1. Yaw around Y axis (positive yaw = turning right toward viewer's right)
        let cy = cos(yawRad)
        let sy = sin(yawRad)
        let x1 = x * cy + z * sy
        let z1 = -x * sy + z * cy

        // 2. Pitch around X axis (positive pitch = nodding down)
        let cp = cos(pitchRad)
        let sp = sin(pitchRad)
        let y2 = y * cp + z1 * sp
        let z2 = -y * sp + z1 * cp

        return (CGPoint(x: x1, y: y2), z2)
    }

    // MARK: - 2.5D Ears Layer (drawn behind unified silhouette so Siamese seal-point ears emerge organically!)

    private static func drawEarsLayer(
        in ctx: CGContext,
        center: CGPoint,
        physics: CatPhysics,
        appearance: CatAppearance
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: physics.headTilt.value)

        let yawRad = physics.headYaw.value * 0.50
        let pitchRad = physics.headPitch.value * 0.36
        let fold = physics.earFold.value
        let twitch = physics.earTwitch.value * 0.045

        drawEar3D(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: twitch, physics: physics, appearance: appearance)
        drawEar3D(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: -twitch, physics: physics, appearance: appearance)

        ctx.restoreGState()
    }

    // MARK: - 2.5D Head Features (Luminous Eyes & Whiskers)

    private static func drawHeadFeatures(
        in ctx: CGContext,
        center: CGPoint,
        physics: CatPhysics,
        appearance: CatAppearance
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: physics.headTilt.value)

        let yaw = physics.headYaw.value      // -1 (left) .. +1 (right)
        let pitch = physics.headPitch.value  // -1 (up)   .. +1 (down)
        let yawRad = yaw * 0.50              // ~±28.5° authentic head turn
        let pitchRad = pitch * 0.36          // ~±20.5° authentic head nod

        // 1. 3D-Projected Eyes with authentic spherical foreshortening & parallax!
        drawEye3D(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, physics: physics, appearance: appearance)
        drawEye3D(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, physics: physics, appearance: appearance)

        // 2. 3D-Projected Whiskers (outer-side whiskers poke out past silhouette when turning!)
        drawWhiskers3D(in: ctx, yawRad: yawRad, pitchRad: pitchRad, physics: physics, appearance: appearance)

        ctx.restoreGState()
    }

    private static func drawEar3D(
        in ctx: CGContext,
        isLeft: Bool,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        fold: CGFloat,
        twitch: CGFloat,
        physics: CatPhysics,
        appearance: CatAppearance
    ) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        let foldAngle = sign * (0.06 + fold * 0.34) + twitch
        let fur = max(0, min(1, appearance.furLength))

        let tipDx = sin(foldAngle) * 32.0
        let tipDy = -cos(foldAngle) * 32.0

        // Bases anchored comfortably inside the upper skull contour so they merge seamlessly at every yaw/pitch!
        let innerBase3D = projectHead3D(x: sign * 9.0, y: -16.0, z: 0.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let outerBase3D = projectHead3D(x: sign * 35.0, y: -5.0, z: -2.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let tip3D       = projectHead3D(x: sign * 24.5 + tipDx, y: -20.0 + tipDy, z: -3.0, yawRad: yawRad, pitchRad: pitchRad).pt

        // Soft plush rounded-tip feline ear
        let tipLeft  = CGPoint(x: tip3D.x - sign * 3.8, y: tip3D.y + 2.8)
        let tipRight = CGPoint(x: tip3D.x + sign * 3.8, y: tip3D.y + 3.2)

        let ear = CGMutablePath()
        ear.move(to: innerBase3D)
        ear.addQuadCurve(
            to: tipLeft,
            control: CGPoint(x: (innerBase3D.x + tipLeft.x) * 0.5 - sign * 1.5, y: (innerBase3D.y + tipLeft.y) * 0.5 - 2.0)
        )
        ear.addQuadCurve(to: tipRight, control: CGPoint(x: tip3D.x, y: tip3D.y - 2.2))
        ear.addQuadCurve(
            to: outerBase3D,
            control: CGPoint(x: (outerBase3D.x + tipRight.x) * 0.5 + sign * 2.5, y: (outerBase3D.y + tipRight.y) * 0.5 - 2.0)
        )
        ear.closeSubpath()

        let earColor: NSColor
        switch appearance.pattern {
        case .colorpoint:
            earColor = appearance.secondaryColor.nsColor
        case .calico:
            earColor = isLeft ? appearance.secondaryColor.nsColor : appearance.tertiaryColor.nsColor
        default:
            earColor = appearance.primaryColor.nsColor
        }

        ctx.saveGState()
        ctx.setFillColor(earColor.cgColor)
        ctx.addPath(ear)
        ctx.fillPath()
        if let outline = appearance.silhouetteOutlineColor {
            ctx.setStrokeColor(outline.cgColor)
            ctx.setLineWidth(1.3)
            ctx.addPath(ear)
            ctx.strokePath()
        }

        // Long-fur lynx ear-tips & fluffy inner ear tufts (sway softly with furSway!)
        if fur > 0.2 {
            let swayX = physics.furSwayX.value * 0.45
            let swayY = physics.furSwayY.value * 0.35
            let tipTuft = CGMutablePath()
            tipTuft.move(to: CGPoint(x: tip3D.x - sign * 2.5, y: tip3D.y + 1.5))
            tipTuft.addLine(to: CGPoint(x: tip3D.x + sign * (2.5 * fur) + swayX, y: tip3D.y - 6.5 * fur + swayY))
            tipTuft.addLine(to: CGPoint(x: tip3D.x + sign * 2.5, y: tip3D.y + 2.0))
            tipTuft.closeSubpath()
            ctx.setFillColor(earColor.cgColor)
            ctx.addPath(tipTuft)
            ctx.fillPath()
        }

        ctx.restoreGState()
    }

    private static func drawEye3D(
        in ctx: CGContext,
        isLeft: Bool,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        appearance: CatAppearance
    ) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        let eyeColor = appearance.eyeColor.nsColor

        // Eye sits on the front surface of the 3D head sphere at (±17.5, -2.0, +28.0)
        let proj = projectHead3D(x: sign * 17.2, y: -2.0, z: 27.5, yawRad: yawRad, pitchRad: pitchRad)

        // Authentic spherical foreshortening: the eye turning away toward the edge narrows horizontally!
        let eyeNormalAngle = yawRad + sign * 0.34
        let foreshortenX = max(0.64, min(1.06, cos(eyeNormalAngle) / cos(0.34)))
        let foreshortenY = max(0.78, min(1.03, cos(pitchRad * 0.85)))

        ctx.saveGState()
        ctx.translateBy(x: proj.pt.x, y: proj.pt.y)
        ctx.scaleBy(x: foreshortenX, y: foreshortenY)

        // Mode 1: Happy closed glowing curved line eyes (petting head!)
        if physics.isHappyClosedEyes {
            ctx.setStrokeColor(eyeColor.cgColor)
            ctx.setLineWidth(2.6)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: -11.5, y: 1.0))
            ctx.addQuadCurve(
                to: CGPoint(x: 11.5, y: 1.0),
                control: CGPoint(x: sign * 1.5, y: 3.4)
            )
            ctx.strokePath()
            ctx.restoreGState()
            return
        }

        // Mode 2: Blissful half-squint glowing slits (petting back/body!)
        if physics.isBlissfulSquint {
            ctx.setFillColor(eyeColor.cgColor)
            let slit = CGMutablePath()
            slit.move(to: CGPoint(x: -11.5, y: -0.5))
            slit.addQuadCurve(to: CGPoint(x: 11.5, y: -0.5), control: CGPoint(x: 0, y: 0.6))
            slit.addQuadCurve(to: CGPoint(x: -11.5, y: -0.5), control: CGPoint(x: 0, y: 4.8))
            slit.closeSubpath()
            ctx.addPath(slit)
            ctx.fillPath()
            ctx.restoreGState()
            return
        }

        // Mode 3: Peaceful Sleeping Eyes (idle / late-night nap!)
        if physics.isSleeping {
            let sleepAlpha = min(1.0, (physics.sleepiness - 0.65) / 0.25)
            let lidStroke = appearance.sleepingEyeColor.withAlphaComponent(sleepAlpha * 0.88)
            ctx.setStrokeColor(lidStroke.cgColor)
            ctx.setLineWidth(2.3)
            ctx.setLineCap(.round)
            // Soft relaxed downward-curved sleeping arc (◡)
            ctx.move(to: CGPoint(x: -10.5, y: 1.5))
            ctx.addQuadCurve(
                to: CGPoint(x: 10.5, y: 1.5),
                control: CGPoint(x: 0, y: 7.2)
            )
            ctx.strokePath()
            ctx.restoreGState()
            return
        }

        let hunt = max(0, min(1, physics.huntIntensity.value))
        let tired = physics.effectiveTiredness

        // Subtle feline eye angle (straightens slightly when wide-eyed hunting, droops subtly when tired!)
        ctx.rotate(by: sign * (0.06 * (1.0 - hunt * 0.6) - tired * 0.04))

        // Eyes grow rounder & slightly larger in full hunting focus!
        let rx: CGFloat = 12.0 + hunt * 1.1
        let ry: CGFloat = 10.8 + hunt * 1.8
        let eyeRect = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)

        // Clip inside eye oval
        ctx.saveGState()
        ctx.addEllipse(in: eyeRect)
        ctx.clip()

        // Luminous iris
        ctx.setFillColor(eyeColor.cgColor)
        ctx.fill(eyeRect)

        // Pupil morphs smoothly from vertical almond slit -> HUGE round black boba pupil when hunting!
        let gaze = physics.eyeGaze.point
        let px = gaze.x * (4.2 - hunt * 1.2)
        let py = gaze.y * (3.6 - hunt * 1.0) + tired * 1.2
        let pScale = physics.pupilScale.value
        let normalW: CGFloat = 5.0 * pScale
        let normalH: CGFloat = 13.5 * min(1.12, pScale)
        let huntDiameter: CGFloat = 18.8
        let pupilW = normalW + (huntDiameter - normalW) * hunt
        let pupilH = normalH + (huntDiameter - normalH) * hunt
        let pupilRect = CGRect(x: px - pupilW * 0.5, y: py - pupilH * 0.5, width: pupilW, height: pupilH)
        ctx.setFillColor(catBlack.cgColor)
        ctx.fillEllipse(in: pupilRect)

        // Tiny crisp white specular sparkle dot as hunting boba pupils dilate!
        if hunt > 0.25 {
            let glintAlpha = min(1.0, (hunt - 0.25) / 0.55) * 0.92
            ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: glintAlpha).cgColor)
            let glintR: CGFloat = 2.1 + hunt * 0.9
            ctx.fillEllipse(in: CGRect(
                x: px - pupilW * 0.22 - glintR * 0.5,
                y: py - pupilH * 0.22 - glintR * 0.5,
                width: glintR * 2,
                height: glintR * 2
            ))
        }

        // Eyelid closure mask (blinks, drowsy sleepiness, AND heavy 0:00–6:00 AM tired upper eyelids!)
        let tiredDroop: CGFloat = tired * 0.36
        let closure = max(physics.effectiveEyeClosure, tiredDroop)
        let faceMaskColor = appearance.faceEyelidColor
        if closure > 0.02 {
            let lidY = -ry + (ry * 2.15) * closure
            let slant: CGFloat = tired * 1.8 * sign
            let lidPath = CGMutablePath()
            lidPath.move(to: CGPoint(x: -rx - 2, y: -ry - 2))
            lidPath.addLine(to: CGPoint(x: rx + 2, y: -ry - 2))
            lidPath.addLine(to: CGPoint(x: rx + 2, y: lidY + slant))
            lidPath.addQuadCurve(
                to: CGPoint(x: -rx - 2, y: lidY - slant),
                control: CGPoint(x: 0, y: lidY + tired * 1.6)
            )
            lidPath.closeSubpath()
            ctx.setFillColor(faceMaskColor.cgColor)
            ctx.addPath(lidPath)
            ctx.fillPath()

            // Subtle tired upper-lid crease line
            if tired > 0.2 && physics.effectiveEyeClosure < 0.55 {
                let lidRim = appearance.sleepingEyeColor.withAlphaComponent(0.45 * tired)
                ctx.setStrokeColor(lidRim.cgColor)
                ctx.setLineWidth(1.1)
                ctx.move(to: CGPoint(x: -rx, y: lidY - slant))
                ctx.addQuadCurve(
                    to: CGPoint(x: rx, y: lidY + slant),
                    control: CGPoint(x: 0, y: lidY + tired * 1.6)
                )
                ctx.strokePath()
            }
        }

        ctx.restoreGState()

        // Subtle crisp eye rim on very light coats (like White Persian!) so bright eyes still pop cleanly
        if !appearance.isDarkCoat && appearance.pattern != .colorpoint {
            ctx.setStrokeColor(appearance.primaryColor.darkened(by: 0.48).withAlphaComponent(0.42).cgColor)
            ctx.setLineWidth(1.0)
            ctx.strokeEllipse(in: eyeRect)
        }

        // Late-night (0:00–6:00 AM) tired under-eye bags / dark-circle crescents beneath each eye
        if tired > 0.15 {
            let bagColor = appearance.isDarkCoat
                ? NSColor(calibratedRed: 0.52, green: 0.48, blue: 0.64, alpha: 0.44 * tired)
                : NSColor(calibratedRed: 0.34, green: 0.24, blue: 0.36, alpha: 0.45 * tired)
            ctx.setStrokeColor(bagColor.cgColor)
            ctx.setLineWidth(1.45)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: -rx * 0.72, y: ry * 0.92))
            ctx.addQuadCurve(
                to: CGPoint(x: rx * 0.72, y: ry * 0.92),
                control: CGPoint(x: 0, y: ry + 4.0)
            )
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    private static func drawWhiskers3D(
        in ctx: CGContext,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        appearance: CatAppearance
    ) {
        let wiggle = sin(physics.time * 4.5) * (max(physics.petHeadIntensity, physics.petBodyIntensity) * 1.2)
        ctx.saveGState()
        let wColor = appearance.whiskerColor
        ctx.setStrokeColor(wColor.cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)

        // 3D cheek whiskers — when turning left, left whiskers naturally poke past silhouette
        // while right whiskers sweep inward across the cheek (exact Xiaohongshu effect!)
        for sign in [-1.0, 1.0] as [CGFloat] {
            let rows: [(CGFloat, CGFloat, CGFloat)] = [
                (10.5, 36.5, 8.8 + wiggle),
                (14.2, 37.8, 14.2 + wiggle * 0.5),
                (18.0, 35.5, 19.6 - wiggle * 0.4)
            ]
            for (y0, xEnd, yEnd) in rows {
                let p0 = projectHead3D(x: sign * 24.0, y: y0, z: 23.0, yawRad: yawRad, pitchRad: pitchRad).pt
                let p2 = projectHead3D(x: sign * xEnd, y: yEnd, z: 14.0, yawRad: yawRad, pitchRad: pitchRad).pt
                let ctrl = CGPoint(x: (p0.x + p2.x) * 0.5, y: (p0.y + p2.y) * 0.5 - 0.8)
                ctx.move(to: p0)
                ctx.addQuadCurve(to: p2, control: ctrl)
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Front Paws (Idle Sitting & Dynamic Reaching with Signature Outlines / Siamese Socks)

    private static func drawFrontPaws(
        in ctx: CGContext,
        seatX: CGFloat,
        seatY: CGFloat,
        breath: CGFloat,
        physics: CatPhysics,
        appearance: CatAppearance
    ) {
        let lPos = physics.leftPaw.point
        let rPos = physics.rightPaw.point

        let lDist = hypot(lPos.x - CatPhysics.leftPawRest.x, lPos.y - CatPhysics.leftPawRest.y)
        let rDist = hypot(rPos.x - CatPhysics.rightPawRest.x, rPos.y - CatPhysics.rightPawRest.y)

        let leftShoulder = CGPoint(x: seatX - 24, y: seatY - 56 + breath)
        let rightShoulder = CGPoint(x: seatX + 24, y: seatY - 56 + breath)

        // Left arm
        if lDist < 6.0 && !physics.leftPawOnMouse && !physics.leftPawOnTrackpad && !physics.leftPawTyping {
            drawIdleFrontLeg(in: ctx, top: CGPoint(x: seatX - 18, y: seatY - 30), bottom: CGPoint(x: seatX - 16, y: seatY + 12), isLeft: true, appearance: appearance)
        } else {
            let mid = CGPoint(
                x: (leftShoulder.x + lPos.x) * 0.5 - (physics.leftPawOnMouse ? 8 : 4),
                y: (leftShoulder.y + lPos.y) * 0.5 - 6
            )
            drawLimb(
                in: ctx,
                start: leftShoulder,
                control: mid,
                end: lPos,
                startWidth: 19.0 + appearance.furLength * 3.0,
                endWidth: 13.5,
                outlineOnLeftSide: false,
                outlineAlpha: 0.78,
                appearance: appearance
            )
        }

        // Right arm
        if rDist < 6.0 && !physics.rightPawTyping {
            drawIdleFrontLeg(in: ctx, top: CGPoint(x: seatX + 18, y: seatY - 30), bottom: CGPoint(x: seatX + 16, y: seatY + 12), isLeft: false, appearance: appearance)
        } else {
            let mid = CGPoint(
                x: (rightShoulder.x + rPos.x) * 0.5 + 4,
                y: (rightShoulder.y + rPos.y) * 0.5 - 6
            )
            drawLimb(
                in: ctx,
                start: rightShoulder,
                control: mid,
                end: rPos,
                startWidth: 19.0 + appearance.furLength * 3.0,
                endWidth: 13.5,
                outlineOnLeftSide: true,
                outlineAlpha: 0.78,
                appearance: appearance
            )
        }
    }

    /// Signature tucked sitting front legs (adapts to Colorpoint socks, Tuxedo mittens, or Solid/Tabby/Calico!)
    private static func drawIdleFrontLeg(in ctx: CGContext, top: CGPoint, bottom: CGPoint, isLeft: Bool, appearance: CatAppearance) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        ctx.saveGState()

        if appearance.pattern == .colorpoint {
            let legRect = CGRect(x: bottom.x - 7.5, y: top.y, width: 15.0, height: bottom.y - top.y + 1.0)
            let legPath = CGPath(roundedRect: legRect, cornerWidth: 6.5, cornerHeight: 6.5, transform: nil)
            ctx.saveGState()
            ctx.addPath(legPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                appearance.primaryColor.nsColor.withAlphaComponent(0.0).cgColor,
                appearance.tertiaryColor.nsColor.withAlphaComponent(0.75).cgColor,
                appearance.secondaryColor.nsColor.cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.05, 0.52, 0.85]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: top.x, y: top.y),
                    end: CGPoint(x: bottom.x, y: bottom.y + 2),
                    options: []
                )
            }
            ctx.restoreGState()
        } else if appearance.pattern == .tuxedo {
            // Cute tuxedo little white mittens at bottom of resting legs
            ctx.setFillColor(appearance.secondaryColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: bottom.x - 7.2, y: bottom.y - 11.0, width: 14.4, height: 11.5))
        }

        let lineColor = appearance.limbSeparationColor
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(1.45)
        ctx.setLineCap(.round)

        // Outer separation crease
        ctx.move(to: CGPoint(x: top.x + sign * 8.5, y: top.y))
        ctx.addQuadCurve(
            to: CGPoint(x: bottom.x + sign * 7.5, y: bottom.y - 1),
            control: CGPoint(x: top.x + sign * 9.5, y: (top.y + bottom.y) * 0.5)
        )
        // Inner separation crease
        ctx.move(to: CGPoint(x: top.x - sign * 7.0, y: top.y + 4))
        ctx.addQuadCurve(
            to: CGPoint(x: bottom.x - sign * 6.0, y: bottom.y - 1),
            control: CGPoint(x: top.x - sign * 6.5, y: (top.y + bottom.y) * 0.5)
        )
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Smooth tapered limb + plump rounded paw (adapts to every fur pattern & coat brightness!)
    private static func drawLimb(
        in ctx: CGContext,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat,
        outlineOnLeftSide: Bool,
        outlineAlpha: CGFloat,
        appearance: CatAppearance
    ) {
        let steps = 14
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = quadPoint(start, control, end, t: t)
            let tan = quadTangent(start, control, end, t: t)
            let len = max(0.001, hypot(tan.x, tan.y))
            let nx = -tan.y / len
            let ny = tan.x / len
            let halfW = (startWidth + (endWidth - startWidth) * t) * 0.5
            leftEdge.append(CGPoint(x: p.x + nx * halfW, y: p.y + ny * halfW))
            rightEdge.append(CGPoint(x: p.x - nx * halfW, y: p.y - ny * halfW))
        }

        let limbPath = CGMutablePath()
        limbPath.move(to: leftEdge[0])
        for pt in leftEdge.dropFirst() { limbPath.addLine(to: pt) }
        for pt in rightEdge.reversed() { limbPath.addLine(to: pt) }
        limbPath.closeSubpath()

        let pawR = endWidth * 0.58
        let pawRect = CGRect(x: end.x - pawR, y: end.y - pawR * 0.85, width: pawR * 2, height: pawR * 1.7)

        ctx.saveGState()
        if appearance.pattern == .colorpoint {
            // Colorpoint dipped socks gradient along the limb!
            ctx.saveGState()
            ctx.addPath(limbPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                appearance.primaryColor.nsColor.withAlphaComponent(0.0).cgColor,
                appearance.primaryColor.cgColor,
                appearance.tertiaryColor.cgColor,
                appearance.secondaryColor.cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 0.16, 0.48, 0.78]) {
                ctx.drawLinearGradient(grad, start: start, end: end, options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()
            ctx.setFillColor(appearance.secondaryColor.cgColor)
            ctx.fillEllipse(in: pawRect)
        } else if appearance.pattern == .tuxedo {
            ctx.setFillColor(appearance.primaryColor.cgColor)
            ctx.addPath(limbPath)
            ctx.fillPath()
            // Crisp tuxedo white paw mittens!
            ctx.setFillColor(appearance.secondaryColor.cgColor)
            ctx.fillEllipse(in: pawRect)
        } else {
            ctx.setFillColor(appearance.primaryColor.cgColor)
            ctx.addPath(limbPath)
            ctx.fillPath()
            ctx.fillEllipse(in: pawRect)
            // Subtle tabby wrist bands
            if appearance.pattern == .tabby {
                ctx.saveGState()
                ctx.addPath(limbPath)
                ctx.clip()
                ctx.setStrokeColor(appearance.secondaryColor.nsColor.withAlphaComponent(0.75).cgColor)
                ctx.setLineWidth(2.6)
                for idx in [5, 9] {
                    ctx.move(to: leftEdge[idx])
                    ctx.addLine(to: rightEdge[idx])
                }
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        // Clean outer edge outline on light/medium coats so the arm reads crisply over light backgrounds
        if let outline = appearance.silhouetteOutlineColor {
            ctx.setStrokeColor(outline.withAlphaComponent(0.72).cgColor)
            ctx.setLineWidth(1.25)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let outerEdge = outlineOnLeftSide ? rightEdge : leftEdge
            if outerEdge.count > 4 {
                ctx.move(to: outerEdge[3])
                for idx in 4..<(outerEdge.count - 1) { ctx.addLine(to: outerEdge[idx]) }
                ctx.strokePath()
            }
        }

        // Crisp separation stroke along upper-to-mid arm where it crosses the torso
        let highlightEdge = outlineOnLeftSide ? leftEdge : rightEdge
        if highlightEdge.count > 6 {
            let strokeColor = appearance.limbSeparationColor.withAlphaComponent(outlineAlpha * 0.88)
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.setLineWidth(1.35)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let startIdx = 2
            let endIdx = Int(CGFloat(highlightEdge.count - 1) * 0.68)
            ctx.move(to: highlightEdge[startIdx])
            for idx in (startIdx + 1)...endIdx {
                ctx.addLine(to: highlightEdge[idx])
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - Floating Mechanical Keycap Popups

    private static func drawFloatingKeycaps(in ctx: CGContext, physics: CatPhysics) {
        for badge in physics.floatingKeycaps {
            let progress = badge.age / badge.lifetime
            // Spring pop-in scale (starts crisp and readable immediately!)
            let scale: CGFloat
            if badge.age < 0.09 {
                let t = badge.age / 0.09
                scale = 0.72 + 0.38 * sin(t * .pi * 0.65)
            } else if badge.age < 0.18 {
                let t = (badge.age - 0.09) / 0.09
                scale = 1.10 - 0.10 * t
            } else {
                scale = 1.0
            }

            let alpha: CGFloat = progress < 0.62 ? 1.0 : max(0, 1.0 - (progress - 0.62) / 0.38)

            let charCount = badge.label.count
            let w: CGFloat = charCount <= 1 ? 23 : (charCount == 2 ? 30 : 38)
            let h: CGFloat = 22

            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: badge.position.x, y: badge.position.y)
            ctx.rotate(by: badge.rotation)
            ctx.scaleBy(x: scale, y: scale)

            // 3D bottom keycap edge / shadow
            let baseRect = CGRect(x: -w * 0.5, y: -h * 0.5 + 2.5, width: w, height: h)
            let basePath = CGPath(roundedRect: baseRect, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
            ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 0.95).cgColor)
            ctx.addPath(basePath)
            ctx.fillPath()

            // Crisp white mechanical keycap top face
            let faceRect = CGRect(x: -w * 0.5, y: -h * 0.5, width: w, height: h)
            let facePath = CGPath(roundedRect: faceRect, cornerWidth: 5.2, cornerHeight: 5.2, transform: nil)
            ctx.setFillColor(NSColor(calibratedRed: 0.975, green: 0.972, blue: 0.952, alpha: 1.0).cgColor)
            ctx.addPath(facePath)
            ctx.fillPath()

            ctx.setStrokeColor(NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1.0).cgColor)
            ctx.setLineWidth(1.45)
            ctx.addPath(facePath)
            ctx.strokePath()

            // Centered bold key label
            let fontSize: CGFloat = charCount <= 1 ? 11.5 : 10.0
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
            ]
            let attrStr = NSAttributedString(string: badge.label, attributes: attrs)
            let strSize = attrStr.size()
            let drawPt = CGPoint(x: -strSize.width * 0.5, y: -strSize.height * 0.5 - 0.5)
            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.current = nsCtx
            attrStr.draw(at: drawPt)
            NSGraphicsContext.restoreGraphicsState()

            ctx.restoreGState()
        }
    }

    // MARK: - Subtle Petting Sparkles & Sleep Z

    private static func drawSparkles(in ctx: CGContext, physics: CatPhysics, accentColor: NSColor) {
        for sp in physics.sparkles {
            let p = sp.age / sp.lifetime
            let alpha = sin(min(1.0, p) * .pi)
            ctx.saveGState()
            ctx.setAlpha(alpha * 0.85)
            if sp.isSleepZ {
                let baseSize: CGFloat = sp.isBigSleepZ ? 13.0 : 10.0
                let swayX = sin(sp.age * 3.0) * 4.5
                let label = sp.isBigSleepZ ? "Z" : "z"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: baseSize + p * 3.5, weight: .bold),
                    .foregroundColor: accentColor
                ]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSAttributedString(string: label, attributes: attrs)
                    .draw(at: CGPoint(x: sp.position.x + swayX, y: sp.position.y))
                NSGraphicsContext.restoreGraphicsState()
            } else {
                // Tiny glowing 4-point star
                let r: CGFloat = 3.5 + p * 1.5
                ctx.translateBy(x: sp.position.x, y: sp.position.y)
                ctx.setFillColor(accentColor.cgColor)
                let star = CGMutablePath()
                star.move(to: CGPoint(x: 0, y: -r))
                star.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0.8, y: -0.8))
                star.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: 0.8, y: 0.8))
                star.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -0.8, y: 0.8))
                star.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -0.8, y: -0.8))
                star.closeSubpath()
                ctx.addPath(star)
                ctx.fillPath()
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Non-Intrusive Permission Pill

    private static func drawPermissionPill(in ctx: CGContext) {
        let r = permissionPillRect
        let path = CGPath(roundedRect: r, cornerWidth: 11, cornerHeight: 11, transform: nil)

        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.90).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.90).cgColor)
        ctx.setLineWidth(1.2)
        ctx.addPath(path)
        ctx.strokePath()

        let text = L10n.tr("Click to Enable Input Monitoring 🔑", "点击开启全局/游戏键盘监听 🔑")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.90, alpha: 1.0)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(at: CGPoint(x: r.midX - sz.width * 0.5, y: r.midY - sz.height * 0.5 - 0.5))
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }

    // MARK: - Geometry & Color Helpers

    private static func offsetY(_ pt: CGPoint, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: pt.x, y: pt.y + dy)
    }

    private static func quadPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        )
    }

    private static func cubicPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t
        return CGPoint(
            x: mt2 * mt * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t2 * t * p3.x,
            y: mt2 * mt * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t2 * t * p3.y
        )
    }

    private static func quadTangent(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
            y: 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        )
    }

    private static func roundedQuadPath(
        tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint, radius: CGFloat
    ) -> CGPath {
        let p = CGMutablePath()
        let midTop = CGPoint(x: (tl.x + tr.x) * 0.5, y: (tl.y + tr.y) * 0.5)
        p.move(to: midTop)
        p.addArc(tangent1End: tr, tangent2End: br, radius: radius)
        p.addArc(tangent1End: br, tangent2End: bl, radius: radius)
        p.addArc(tangent1End: bl, tangent2End: tl, radius: radius)
        p.addArc(tangent1End: tl, tangent2End: tr, radius: radius)
        p.closeSubpath()
        return p
    }

    private static func blendColor(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
        let ca = a.usingColorSpace(.deviceRGB) ?? a
        let cb = b.usingColorSpace(.deviceRGB) ?? b
        let clamped = max(0, min(1, t))
        return NSColor(
            calibratedRed: ca.redComponent + (cb.redComponent - ca.redComponent) * clamped,
            green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * clamped,
            blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * clamped,
            alpha: ca.alphaComponent + (cb.alphaComponent - ca.alphaComponent) * clamped
        )
    }

    private static func drawRadialGlow(in ctx: CGContext, center: CGPoint, radius: CGFloat, color: NSColor) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [color.cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
        let locs: [CGFloat] = [0.0, 1.0]
        if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
            ctx.saveGState()
            ctx.drawRadialGradient(
                grad,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius,
                options: []
            )
            ctx.restoreGState()
        }
    }
}
