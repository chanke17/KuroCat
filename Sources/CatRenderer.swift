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
    private static func patterned(_ coat: CatCoatTheme) -> Bool {
        coat == .shorthair || coat == .orangeWhite || coat == .tabby
    }
    private static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: CGFloat((hex >> 16) & 255)/255,
                green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: alpha)
    }
    private static func bodyColor(_ coat: CatCoatTheme) -> NSColor {
        switch coat {
        case .shorthair: return rgb(0xC2C5C1)
        case .orangeWhite: return rgb(0xF2EEE4)
        case .tabby: return rgb(0x6F695D)
        default: return catBlack
        }
    }
    private static func limbColor(_ coat: CatCoatTheme) -> NSColor {
        coat == .orangeWhite ? rgb(0xD8AA73) : bodyColor(coat)
    }
    private static func pawColor(_ coat: CatCoatTheme) -> NSColor {
        if coat == .tabby { return rgb(0x564A3E) }
        return patterned(coat) ? rgb(0xF2EEE4) : (coat == .siamese ? siamesePoint : catBlack)
    }
    private static func earTailColor(_ coat: CatCoatTheme) -> NSColor {
        coat == .siamese ? siamesePoint : limbColor(coat)
    }
    private static func creaseColor(_ coat: CatCoatTheme) -> NSColor {
        if coat == .tabby { return rgb(0x554638, 0.70) }
        return patterned(coat) ? rgb(0x8B8171, 0.60) : contourMint
    }

    private static let tabbyStripe = rgb(0x373129)
    static let catBlack = NSColor(calibratedRed: 0.085, green: 0.085, blue: 0.095, alpha: 1.0)
    private static let blackOutlineWidth: CGFloat = 1.6
    private static let blackOutlineColor = NSColor(calibratedWhite: 1.0, alpha: 0.94)
    static let contourMint = NSColor(calibratedRed: 0.82, green: 0.92, blue: 0.89, alpha: 0.76)
    static let whiskerColor = NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.92, alpha: 0.72)

    // Siamese Seal-Point Palette (小豆泥风暖奶白躯干 + 柔和丝绒焦糖可可重点色)
    static let siameseCream    = NSColor(calibratedRed: 0.965, green: 0.937, blue: 0.894, alpha: 1.0) // #F6EFE4
    static let siameseLatte    = NSColor(calibratedRed: 0.918, green: 0.859, blue: 0.784, alpha: 1.0) // #EADBC8
    static let siameseMocha    = NSColor(calibratedRed: 0.416, green: 0.314, blue: 0.255, alpha: 1.0) // #6A5041
    static let siamesePoint    = NSColor(calibratedRed: 0.208, green: 0.149, blue: 0.122, alpha: 1.0) // #35261F
    static let siameseInnerEar = NSColor(calibratedRed: 0.365, green: 0.275, blue: 0.228, alpha: 1.0) // #5D463A
    static let siameseOutline  = NSColor(calibratedRed: 0.68,  green: 0.59,  blue: 0.50,  alpha: 0.42) // soft plush rim
    static let siameseCrease   = NSColor(calibratedRed: 0.553, green: 0.471, blue: 0.404, alpha: 0.54) // #8D7867
    static let siameseWhisker  = NSColor(calibratedRed: 0.478, green: 0.388, blue: 0.325, alpha: 0.62) // #7A6353

    static let permissionPillRect = CGRect(x: 92, y: 294, width: 176, height: 22)
    static let editFlipButtonRect = CGRect(x: 94, y: 12, width: 82, height: 24)
    static let editDoneButtonRect = CGRect(x: 184, y: 12, width: 82, height: 24)
    static let editCorners: [CGPoint] = [
        CGPoint(x: 10, y: 10),   // 0: top-left
        CGPoint(x: 350, y: 10),  // 1: top-right
        CGPoint(x: 10, y: 310),  // 2: bottom-left
        CGPoint(x: 350, y: 310)  // 3: bottom-right
    ]

    /// Edit-mode hit test in unflipped 360x320 canvas coordinates:
    /// 0..3 = corner resize handles, 10 = flip button, 11 = done button, 12 = inside edit box, -1 = outside.
    static func hitTestEditOverlay(point p: CGPoint) -> Int {
        if editFlipButtonRect.insetBy(dx: -2, dy: -2).contains(p) { return 10 }
        if editDoneButtonRect.insetBy(dx: -2, dy: -2).contains(p) { return 11 }
        for (idx, c) in editCorners.enumerated() {
            if hypot(p.x - c.x, p.y - c.y) <= 18.0 { return idx }
        }
        if CGRect(x: 6, y: 6, width: 348, height: 308).contains(p) { return 12 }
        return -1
    }

    /// Hit test in 360x320 logical canvas coordinates for smart click-through & petting.
    static func hitTest(point p: CGPoint, physics: CatPhysics, showPermissionPill: Bool) -> CatHitZone {
        if showPermissionPill && permissionPillRect.insetBy(dx: -4, dy: -4).contains(p) {
            return .permissionPill
        }

        let cx = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let breath = physics.breathingOffset
        let siameseLift: CGFloat = (CatSettings.shared.coatTheme == .siamese) ? -3.0 : 0.0
        let headCenter = CGPoint(x: cx + physics.bodyTilt.value * 42, y: 124 + siameseLift + physics.headOffsetY.value + breath)

        // Head hit ellipse (strictly on the cat's head — never overlaps keyboard)
        let hdx = (p.x - headCenter.x) / 44.0
        let hdy = (p.y - headCenter.y) / 38.0
        if hdx * hdx + hdy * hdy <= 1.0 {
            return .head
        }

        // Torso + keyboard area hit check
        let bdx = (p.x - cx) / 58.0
        let bdy = (p.y - 196.0) / 56.0
        if bdx * bdx + bdy * bdy <= 1.0 {
            return .body
        }

        // Mini keyboard & mouse area (allows dragging by grabbing keyboard too)
        let kbRect = CGRect(x: 58, y: 232, width: 236, height: 64)
        if kbRect.contains(p) {
            return .body
        }

        return .none
    }

    /// Main 60fps draw routine in flipped 360x320 logical coordinate space.
    static func draw(in ctx: CGContext, physics: CatPhysics, showPermissionPill: Bool,
                     permissionPillText: String = "点击开启全局/游戏键盘监听 🔑") {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let settings = CatSettings.shared
        if settings.obsCaptureMode == 2 {
            ctx.setFillColor(NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0).cgColor)
            ctx.fill(CGRect(origin: .zero, size: CatPhysics.canvasSize))
        }
        let flipped = settings.flipHorizontal
        if flipped {
            ctx.saveGState()
            ctx.translateBy(x: CatPhysics.canvasSize.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        let coat = settings.coatTheme
        let breath = physics.breathingOffset
        let scruff = max(0, min(1, physics.scruffDrag.value))
        let lie = max(0, min(1, physics.lieIntensity.value))
        let dizzy = max(0, min(1, physics.dizzyIntensity.value))
        let lieS = lie * lie * (3.0 - 2.0 * lie)
        // Dizzy has 2 stages: [0.12..0.50] upright stars + spiral eyes + wobble; [0.50..1.0] smooth sideways collapse onto keyboard!
        let dizzyFallRaw = max(0, min(1, (dizzy - 0.50) / 0.50))
        let dizzyFall = dizzyFallRaw * dizzyFallRaw * (3.0 - 2.0 * dizzyFallRaw)
        let preWobble = max(0, min(1, (dizzy - 0.12) / 0.38)) * (1.0 - dizzyFall)

        let seatX = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let seatY = CatPhysics.seatAnchor.y - scruff * 22.0 + lieS * 10.0

        // 1. Mini White Mouse (left of keyboard)
        drawMouse(in: ctx, physics: physics, theme: settings.keyboardTheme)

        // 2. Mini Angled 65% Mechanical Keyboard + Dynamic Keycap Glow
        drawKeyboard(in: ctx, physics: physics, theme: settings.keyboardTheme, eyeTheme: settings.eyeTheme, showLegends: settings.showKeyLegends, flipped: flipped, marquee: settings.keyboardMarquee)

        // Rigid-body wobble (pre-dizzy) -> natural sideways collapse onto the keyboard (dizzy >= 0.5)
        let fallAngle: CGFloat = -dizzyFall * 1.46 + sin(physics.time * 9.5) * 0.16 * preWobble
        let fallShiftX: CGFloat = dizzyFall * 56.0
        let fallShiftY: CGFloat = dizzyFall * 20.0
        let baseHead = headPosition(physics, coat: coat)
        let localHeadCenter = CGPoint(x: baseHead.x - lieS * 4.0, y: baseHead.y + lieS * 60.0)
        let drawBlackRim = (coat == .classicBlack)
        let tailInFront = (physics.tailTyping.value >= 0.5) || (lieS >= 0.45)

        ctx.saveGState()
        if dizzy > 0.01 {
            ctx.translateBy(x: seatX + fallShiftX, y: seatY + fallShiftY)
            ctx.rotate(by: fallAngle)
            ctx.translateBy(x: -seatX, y: -seatY)
        }

        // Pass 1: crisp outer white outline for Classic Black Cat so it pops cleanly on dark backgrounds with zero internal seams
        if drawBlackRim {
            if !tailInFront {
                drawTail(in: ctx, physics: physics, coat: coat, outlineOnly: true)
            }
            drawEarsLayer(in: ctx, center: localHeadCenter, physics: physics, coat: coat, outlineOnly: true)
            drawUnifiedSilhouette(
                in: ctx,
                seatX: seatX,
                seatY: seatY,
                headCenter: localHeadCenter,
                breath: breath,
                physics: physics,
                coat: coat,
                outlineOnly: true
            )
        }

        if !tailInFront {
            drawTail(in: ctx, physics: physics, coat: coat)
        }

        // 4. 3D-Projected Ears (behind crown silhouette so Siamese seal-point ears emerge cleanly from cream skull!)
        drawEarsLayer(in: ctx, center: localHeadCenter, physics: physics, coat: coat)

        // 5. Unified C1-Continuous Head + Neck + Pear Torso Silhouette + Siamese 2.5D Face Mask
        drawUnifiedSilhouette(
            in: ctx,
            seatX: seatX,
            seatY: seatY,
            headCenter: localHeadCenter,
            breath: breath,
            physics: physics,
            coat: coat
        )

        // 6. Hind Foot (3rd simultaneous key easter egg!)
        if physics.hindFootActive.value > 0.03 {
            drawHindFoot(in: ctx, seatX: seatX, seatY: seatY, physics: physics, coat: coat)
        }

        // 7. 2.5D Turning Head Features: Luminous Eyes & Whiskers
        drawHeadFeatures(in: ctx, center: localHeadCenter, physics: physics, eyeTheme: settings.eyeTheme, coat: coat)

        // 8. Front Arms / Paws (over torso & keyboard/mouse with crisp separation outlines / Siamese chocolate socks!)
        drawFrontPaws(in: ctx, seatX: seatX, seatY: seatY, breath: breath, physics: physics, coat: coat)

        if tailInFront {
            if drawBlackRim { drawTail(in: ctx, physics: physics, coat: coat, outlineOnly: true) }
            drawTail(in: ctx, physics: physics, coat: coat)
        }

        ctx.restoreGState()

        // Upright orbiting golden dizzy stars floating right above the head (appear FIRST before falling!)
        if dizzy > 0.10 {
            let relX = localHeadCenter.x - seatX
            let relY = localHeadCenter.y - seatY
            let worldHeadX = seatX + fallShiftX + relX * cos(fallAngle) - relY * sin(fallAngle)
            let worldHeadY = seatY + fallShiftY + relX * sin(fallAngle) + relY * cos(fallAngle)
            let dAlpha = min(1.0, (dizzy - 0.10) / 0.22)
            let starLift: CGFloat = 42.0 + dizzyFall * 10.0
            ctx.saveGState()
            ctx.translateBy(x: worldHeadX, y: worldHeadY - starLift)
            for i in 0..<3 {
                let ang = physics.dizzyPhase * 0.85 + CGFloat(i) * (.pi * 2.0 / 3.0)
                let sx = cos(ang) * 26.0
                let sy = sin(ang) * 6.5
                let r: CGFloat = 4.4 * (0.75 + 0.25 * sin(ang))
                ctx.saveGState()
                ctx.translateBy(x: sx, y: sy)
                ctx.rotate(by: physics.dizzyPhase + CGFloat(i))
                ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.22, alpha: 0.96 * dAlpha).cgColor)
                let star = CGMutablePath()
                for k in 0..<8 {
                    let rad = (k % 2 == 0) ? r : r * 0.42
                    let a = CGFloat(k) * .pi * 0.25
                    let pt = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
                    if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
                }
                star.closeSubpath()
                ctx.addPath(star)
                ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.restoreGState()
        }

        // 8. Floating Mechanical Keycap Badges (keyboard + mouse clicks)
        if !physics.floatingKeycaps.isEmpty {
            drawFloatingKeycaps(in: ctx, physics: physics)
        }

        // 9. Subtle Petting Sparkles / Sleep Z
        drawSparkles(in: ctx, physics: physics, eyeTheme: settings.eyeTheme)

        if flipped {
            ctx.restoreGState()
        }

        // 10. Interactive Resize & Flip Edit Box (drawn unflipped on top)
        if settings.isEditMode {
            drawEditOverlay(in: ctx, isEnglish: settings.isEnglish, scale: settings.scale)
        }

        // 11. Optional non-intrusive Permission Pill if global monitoring not yet granted
        if showPermissionPill {
            drawPermissionPill(in: ctx, text: permissionPillText)
        }

        ctx.restoreGState()
    }

    private static func drawEditOverlay(in ctx: CGContext, isEnglish: Bool, scale: CGFloat) {
        ctx.saveGState()
        let boxRect = CGRect(x: 10, y: 10, width: 340, height: 300)
        let boxPath = CGPath(roundedRect: boxRect, cornerWidth: 12, cornerHeight: 12, transform: nil)

        ctx.setFillColor(NSColor(calibratedRed: 0.16, green: 0.56, blue: 0.98, alpha: 0.07).cgColor)
        ctx.addPath(boxPath)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor(calibratedRed: 0.20, green: 0.62, blue: 1.0, alpha: 0.92).cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.addPath(boxPath)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        for c in editCorners {
            let r: CGFloat = 6.5
            let hRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: hRect)
            ctx.setStrokeColor(NSColor(calibratedRed: 0.14, green: 0.52, blue: 0.96, alpha: 1.0).cgColor)
            ctx.setLineWidth(2.0)
            ctx.strokeEllipse(in: hRect)
        }

        func drawBtn(_ rect: CGRect, title: String, primary: Bool) {
            let p = CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil)
            let fill = primary
                ? NSColor(calibratedRed: 0.16, green: 0.54, blue: 0.96, alpha: 0.95)
                : NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.19, alpha: 0.88)
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(p)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.28).cgColor)
            ctx.setLineWidth(0.9)
            ctx.addPath(p)
            ctx.strokePath()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let ns = NSAttributedString(string: title, attributes: attrs)
            let sz = ns.size()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            ns.draw(at: CGPoint(x: rect.midX - sz.width * 0.5, y: rect.midY - sz.height * 0.5))
            NSGraphicsContext.restoreGraphicsState()
        }

        drawBtn(editFlipButtonRect, title: isEnglish ? "⇄ Flip" : "⇄ 翻转", primary: false)
        drawBtn(editDoneButtonRect, title: isEnglish ? "✓ Done" : "✓ 完成", primary: true)

        let scaleStr = String(format: "%.0f%%", scale * 100)
        let sAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let sns = NSAttributedString(string: scaleStr, attributes: sAttrs)
        let ssz = sns.size()
        let pill = CGRect(x: 180 - (ssz.width + 12) * 0.5, y: 298 - (ssz.height + 4) * 0.5, width: ssz.width + 12, height: ssz.height + 4)
        ctx.setFillColor(NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 0.82).cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        sns.draw(at: CGPoint(x: pill.midX - ssz.width * 0.5, y: pill.midY - ssz.height * 0.5))
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }

    static func headPosition(_ physics: CatPhysics, coat: CatCoatTheme) -> CGPoint {
        let siameseLift: CGFloat = coat == .siamese ? -3 : 0
        let scruff = max(0, min(1, physics.scruffDrag.value))
        return CGPoint(
            x: CatPhysics.seatAnchor.x + physics.bodyShiftX.value + physics.bodyTilt.value * 36 + physics.headYaw.value * 7.5,
            y: 126 + siameseLift + physics.headOffsetY.value + physics.headPitch.value * 4.8 + physics.breathingOffset * 1.1 - scruff * 22.0
        )
    }

    // MARK: - Mini White Mouse

    private static func drawMouse(in ctx: CGContext, physics: CatPhysics, theme: KeyboardTheme) {
        let center = CGPoint(
            x: CatPhysics.mouseBaseCenter.x + physics.mouseOffset.point.x,
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

    private struct KeyboardBitmap {
        let image: CGImage
        let bounds: CGRect

        init?(bounds: CGRect, scale: CGSize, draw: (CGContext) -> Void) {
            let pixels = CGRect(x: bounds.minX * scale.width, y: bounds.minY * scale.height,
                                width: bounds.width * scale.width, height: bounds.height * scale.height).integral
            guard let ctx = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.translateBy(x: -pixels.minX, y: pixels.maxY)
            ctx.scaleBy(x: scale.width, y: -scale.height)
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            draw(ctx)
            guard let image = ctx.makeImage() else { return nil }
            self.image = image
            self.bounds = CGRect(x: pixels.minX / scale.width, y: pixels.minY / scale.height,
                                 width: pixels.width / scale.width, height: pixels.height / scale.height)
        }

        func draw(in ctx: CGContext) {
            ctx.saveGState()
            ctx.translateBy(x: bounds.minX, y: bounds.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: bounds.size))
            ctx.restoreGState()
        }
    }

    private struct KeyboardStyle: Equatable {
        let theme: KeyboardTheme
        let showLegends: Bool
        let flipped: Bool
        let scale: CGSize
    }

    private struct KeyboardArtwork {
        let style: KeyboardStyle
        let chassis: KeyboardBitmap?
        let idle: KeyboardBitmap?
        let keys: [KeyboardKeyArtwork]
        let deckPath: CGPath
        let deckStart: CGPoint
        let deckEnd: CGPoint
    }

    private struct KeyboardKeyArtwork {
        let key: PhysicalKey
        let center: CGPoint
        let path: CGPath
        let fill: NSColor
        let border: CGColor
        let legend: KeyboardBitmap?
        let resting: KeyboardBitmap?
    }

    // Keep only the currently displayed keyboard. Retina scale can change when the window moves screens.
    private static var keyboardArtwork: KeyboardArtwork?

    private static func drawKeyboard(
        in ctx: CGContext,
        physics: CatPhysics,
        theme: KeyboardTheme,
        eyeTheme: EyeColorTheme,
        showLegends: Bool,
        flipped: Bool,
        marquee: Bool
    ) {
        let transform = ctx.userSpaceToDeviceSpaceTransform
        // Round up in quarter steps so dragging a resize handle does not rebuild the cache every tick.
        func rasterScale(_ value: CGFloat) -> CGFloat { min(4, max(1, (value * 4).rounded(.up) / 4)) }
        let scale = CGSize(width: rasterScale(hypot(transform.a, transform.b)),
                           height: rasterScale(hypot(transform.c, transform.d)))
        let style = KeyboardStyle(theme: theme, showLegends: showLegends, flipped: flipped, scale: scale)
        if keyboardArtwork?.style != style {
            keyboardArtwork = makeKeyboardArtwork(style: style)
        }
        guard let artwork = keyboardArtwork else { return }

        let glowBaseColor = eyeTheme.glowColor
        if !marquee, physics.keyGlow.isEmpty, let idle = artwork.idle {
            idle.draw(in: ctx)
        } else {
            artwork.chassis?.draw(in: ctx)
            let phase = physics.marqueePhase.truncatingRemainder(dividingBy: 1)
            let backlight = marquee
                ? KeyboardMarquee(phase: phase, color: hsvColor(hue: phase + 0.52, saturation: 0.55, value: 1),
                                  start: artwork.deckStart, end: artwork.deckEnd)
                : nil
            if let backlight { drawMarquee(backlight, in: ctx, clippedTo: artwork.deckPath) }
            for key in artwork.keys {
                drawKeyboardKey(key, in: ctx, glow: physics.keyGlow[key.key] ?? 0,
                                glowColor: glowBaseColor, backlight: backlight)
            }
        }

        // Signature soft chartreuse backlit glow halos on active keys!
        for (key, glow) in physics.keyGlow where glow > 0.05 {
            let center = KeyboardLayout.canvasPoint(for: key)
            drawRadialGlow(in: ctx, center: center, radius: 17.0 + glow * 6.0,
                           color: glowBaseColor.withAlphaComponent(0.36 * glow))
        }
    }

    private static func makeKeyboardArtwork(style: KeyboardStyle) -> KeyboardArtwork {
        let tl = KeyboardLayout.screenQuadPoint(su: -0.012, sv: -0.04)
        let tr = KeyboardLayout.screenQuadPoint(su: 1.012, sv: -0.04)
        let bl = KeyboardLayout.screenQuadPoint(su: -0.016, sv: 1.04)
        let br = KeyboardLayout.screenQuadPoint(su: 1.016, sv: 1.04)

        let caseDepth: CGFloat = 4.5

        let shadowPath = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth + 2),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth + 2),
            br: CGPoint(x: br.x, y: br.y + caseDepth + 3),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth + 3),
            radius: 6
        )

        // Dark 3D chassis lower lip
        let baseColor: NSColor
        let deckColor: NSColor
        let keyColor: NSColor
        let keyBorderColor: NSColor
        let accentColor: NSColor

        switch style.theme {
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
        let topChassis = roundedQuadPath(tl: tl, tr: tr, br: br, bl: bl, radius: 5.0)
        let bounds = shadowPath.boundingBoxOfPath.union(lowerChassis.boundingBoxOfPath)
            .union(topChassis.boundingBoxOfPath).insetBy(dx: -2, dy: -2)
        let chassis = KeyboardBitmap(bounds: bounds, scale: style.scale) { ctx in
            ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
            ctx.addPath(shadowPath)
            ctx.fillPath()
            ctx.setFillColor(baseColor.cgColor)
            ctx.addPath(lowerChassis)
            ctx.fillPath()
            ctx.setFillColor(deckColor.cgColor)
            ctx.addPath(topChassis)
            ctx.fillPath()
        }

        // Individual keycaps — tight clean mechanical spacing matching the reference video
        let padU: CGFloat = 0.0028
        let padV: CGFloat = 0.014
        let border = keyBorderColor.cgColor

        let keys = KeyboardLayout.keycaps.map { cap in
            // 180° rotated to face the cat: su = 1 - u, sv = 1 - v
            let su0 = (1.0 - (cap.xUnits + cap.widthUnits)) + padU
            let su1 = (1.0 - cap.xUnits) - padU
            let sv0 = (1.0 - CGFloat(cap.row + 1) / 5.0) + padV
            let sv1 = (1.0 - CGFloat(cap.row) / 5.0) - padV

            let kTL = KeyboardLayout.screenQuadPoint(su: su0, sv: sv0)
            let kTR = KeyboardLayout.screenQuadPoint(su: su1, sv: sv0)
            let kBR = KeyboardLayout.screenQuadPoint(su: su1, sv: sv1)
            let kBL = KeyboardLayout.screenQuadPoint(su: su0, sv: sv1)

            let kPath = roundedQuadPath(tl: kTL, tr: kTR, br: kBR, bl: kBL, radius: 1.6)
            let center = CGPoint(x: (kTL.x + kTR.x + kBR.x + kBL.x) * 0.25,
                                 y: (kTL.y + kTR.y + kBR.y + kBL.y) * 0.25)
            let fill = cap.isAmberAccent ? accentColor : keyColor
            let keyBounds = kPath.boundingBoxOfPath.insetBy(dx: -2, dy: -2)
            var legendBitmap: KeyboardBitmap?
            if style.showLegends {
                let isSpace = cap.key == .space
                let legend = isSpace ? "space" : keycapLegend(cap.key)
                if !legend.isEmpty {
                    var labelCenter = center
                    if isSpace {
                        // The spacebar sits right under the cat: its legs hide the middle, and an
                        // unlabeled visible end looked like an odd blank patch beside the cat.
                        // Label the end that stays visible instead.
                        labelCenter = KeyboardLayout.screenQuadPoint(su: su0 + (su1 - su0) * 0.82, sv: (sv0 + sv1) * 0.5)
                    }
                    let textColor: NSColor
                    if cap.isAmberAccent || style.theme != .midnightHacker {
                        textColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 0.78)
                    } else {
                        textColor = NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.92, alpha: 0.82)
                    }
                    let fontSize: CGFloat = legend.count <= 1 ? 5.2 : 4.2
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                        .foregroundColor: textColor
                    ]
                    let str = NSAttributedString(string: legend, attributes: attrs)
                    let size = str.size()
                    let textRect = CGRect(x: -size.width * 0.5, y: -size.height * 0.5,
                                          width: size.width, height: size.height)
                    // Keyboard faces the cat (180°), so legends read upright from the cat's seat.
                    var transform = CGAffineTransform(translationX: labelCenter.x, y: labelCenter.y).rotated(by: .pi + 0.052)
                    if style.flipped { transform = transform.scaledBy(x: -1, y: 1) }
                    legendBitmap = KeyboardBitmap(bounds: textRect.applying(transform).insetBy(dx: -2, dy: -2),
                                                  scale: style.scale) { ctx in
                        ctx.concatenate(transform)
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                        str.draw(at: textRect.origin)
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
            }
            let restingBounds = legendBitmap.map { keyBounds.union($0.bounds) } ?? keyBounds
            let resting = KeyboardBitmap(bounds: restingBounds, scale: style.scale) { ctx in
                drawKeycap(in: ctx, path: kPath, fill: fill.cgColor, border: border)
                legendBitmap?.draw(in: ctx)
            }
            return KeyboardKeyArtwork(key: cap.key, center: center, path: kPath, fill: fill, border: border,
                                      legend: legendBitmap, resting: resting)
        }

        let idle = KeyboardBitmap(bounds: bounds, scale: style.scale) { ctx in
            chassis?.draw(in: ctx)
            for key in keys {
                drawKeyboardKey(key, in: ctx, glow: 0, glowColor: accentColor)
            }
        }
        return KeyboardArtwork(style: style, chassis: chassis, idle: idle, keys: keys,
                               deckPath: topChassis, deckStart: tl, deckEnd: br)
    }

    private static func drawKeyboardKey(_ key: KeyboardKeyArtwork, in ctx: CGContext, glow: CGFloat,
                                        glowColor: NSColor, backlight: KeyboardMarquee? = nil) {
        if backlight == nil, glow == 0, let resting = key.resting {
            resting.draw(in: ctx)
            return
        }

        let pressDepth = glow * 1.9
        let center = CGPoint(x: key.center.x, y: key.center.y + pressDepth)
        let illumination = backlight?.illumination(at: center) ?? 0
        var color = key.fill
        if let backlight, illumination > 0.015 {
            let lit = blendColor(backlight.color, .white, t: illumination * illumination * 0.5)
            color = blendColor(color, lit, t: illumination * 0.88)
        }
        if glow > 0.02 {
            color = blendColor(color, glowColor, t: glow * 0.55)
        }

        ctx.saveGState()
        ctx.translateBy(x: 0, y: pressDepth)
        if let backlight, illumination > 0.10 {
            let border = backlight.color.withAlphaComponent(illumination * 215.0 / 255.0).cgColor
            drawKeycap(in: ctx, path: key.path, fill: color.cgColor, border: border, borderWidth: 1.0)
        } else {
            drawKeycap(in: ctx, path: key.path, fill: color.cgColor, border: key.border)
        }
        if let backlight, illumination > 0.45 {
            ctx.saveGState()
            ctx.translateBy(x: key.center.x, y: key.center.y)
            ctx.scaleBy(x: 15.0, y: 10.5)
            let bloom = (illumination - 0.45) / 0.55
            drawRadialGlow(in: ctx, center: .zero, radius: 1.0,
                           color: backlight.color.withAlphaComponent(bloom * 135.0 / 255.0))
            ctx.restoreGState()
        }
        key.legend?.draw(in: ctx)
        ctx.restoreGState()
    }

    private static func drawKeycap(in ctx: CGContext, path: CGPath, fill: CGColor, border: CGColor,
                                   borderWidth: CGFloat = 0.65) {
        ctx.setFillColor(fill)
        ctx.setStrokeColor(border)
        ctx.setLineWidth(borderWidth)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
    }

    private struct KeyboardMarquee {
        let phase: CGFloat
        let color: NSColor
        let start: CGPoint
        let end: CGPoint
        let dx: CGFloat
        let dy: CGFloat
        let lengthSquared: CGFloat

        init(phase: CGFloat, color: NSColor, start: CGPoint, end: CGPoint) {
            self.phase = phase
            self.color = color
            self.start = start
            self.end = end
            dx = end.x - start.x
            dy = end.y - start.y
            lengthSquared = dx * dx + dy * dy
        }

        func illumination(at center: CGPoint) -> CGFloat {
            let t = ((center.x - start.x) * dx + (center.y - start.y) * dy) / lengthSquared
            return wave(at: max(0, min(1, t)))
        }

        func wave(at t: CGFloat) -> CGFloat {
            let distance = phase - t
            return exp(-(distance < 0 ? distance + 1 : distance) / 0.125)
        }
    }

    private static func drawMarquee(_ light: KeyboardMarquee, in ctx: CGContext, clippedTo deck: CGPath) {
        ctx.saveGState()
        ctx.addPath(deck)
        ctx.clip()
        let stops = (0..<24).map { CGFloat($0) / 23 }
        let colors = stops.map { stop in
            light.color.withAlphaComponent(light.wave(at: stop) * 200.0 / 255.0).cgColor
        }
        if let band = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: stops) {
            ctx.drawLinearGradient(band, start: light.start, end: light.end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let head = CGPoint(x: light.start.x + light.dx * light.phase, y: light.start.y + light.dy * light.phase)
        drawRadialGlow(in: ctx, center: head, radius: 44.0,
                       color: NSColor(calibratedRed: 240.0 / 255, green: 252.0 / 255, blue: 1, alpha: 150.0 / 255))
        ctx.restoreGState()
    }

    // MARK: - Tail

    static func tailCurve(_ physics: CatPhysics)
        -> (root: CGPoint, control1: CGPoint, control2: CGPoint, tip: CGPoint) {
        let seatX = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let scruff = max(0, min(1, physics.scruffDrag.value))
        let lie = max(0, min(1, physics.lieIntensity.value))
        let lieS = lie * lie * (3.0 - 2.0 * lie)
        let seatY = CatPhysics.seatAnchor.y - scruff * 22.0 + lieS * 10.0
        let p = physics.tailPhase
        let hunt = max(0, min(1, physics.huntIntensity.value))
        let agility = max(0, min(1, physics.tailAgility.value))
        let wag1 = sin(p) * (8.0 + hunt * 5.5 + agility * 4.0)
        let wag2 = cos(p * 1.3) * (6.0 + hunt * 4.5 + agility * 3.5)
        // Tail drops lower & swishes tautly when stalking/hunting!
        let huntDrop = hunt * 14.0

        // Signature low sweep out to the right, then playful upward curl at the tip!
        let baseRoot = CGPoint(x: seatX + 34, y: seatY - 6)
        let reach = max(0, min(1, physics.tailTyping.value))
        let target = physics.tailTip.point
        let flickScale = (1.0 - reach) * (1.0 - lieS)
        let fx = physics.tailFlick.point.x * flickScale
        let fy = physics.tailFlick.point.y * flickScale
        let curl = physics.tailCurl.value * flickScale
        let baseC1 = CGPoint(x: seatX + 64 + 12 * reach + fx * 0.25, y: seatY + 2 + wag1 * 0.35 + huntDrop * 0.4 - 18 * reach + fy * 0.22 + curl * 0.35)
        let idleC2 = CGPoint(x: seatX + 66 + wag2 * 0.4 + fx * 0.65 - curl * 0.45, y: seatY - 26 + wag1 * 0.7 + huntDrop + fy * 0.60 - curl * 0.55)
        let idleTip = CGPoint(x: seatX + 91 + wag2 * 0.5 + fx, y: seatY - 30 + wag1 * 0.85 + huntDrop + fy)
        let baseC2 = CGPoint(x: idleC2.x + (target.x + 24 - idleC2.x) * reach, y: idleC2.y + (target.y - 30 - idleC2.y) * reach)
        let baseTip = CGPoint(x: idleTip.x + (target.x - idleTip.x) * reach, y: idleTip.y + (target.y - idleTip.y) * reach)

        // When curling up to sleep, tail sweeps smoothly around the front to wrap cozily around the cat ball!
        let sleepWag = sin(p * 0.6) * 2.0
        let wrapRoot = CGPoint(x: seatX + 40, y: seatY - 2)
        let wrapC1 = CGPoint(x: seatX + 54, y: seatY + 13)
        let wrapC2 = CGPoint(x: seatX + 14, y: seatY + 17)
        let wrapTip = CGPoint(x: seatX - 28, y: seatY + 8 + sleepWag)

        let root = CGPoint(x: baseRoot.x + (wrapRoot.x - baseRoot.x) * lieS, y: baseRoot.y + (wrapRoot.y - baseRoot.y) * lieS)
        let c1 = CGPoint(x: baseC1.x + (wrapC1.x - baseC1.x) * lieS, y: baseC1.y + (wrapC1.y - baseC1.y) * lieS)
        let c2 = CGPoint(x: baseC2.x + (wrapC2.x - baseC2.x) * lieS, y: baseC2.y + (wrapC2.y - baseC2.y) * lieS)
        let tip = CGPoint(x: baseTip.x + (wrapTip.x - baseTip.x) * lieS, y: baseTip.y + (wrapTip.y - baseTip.y) * lieS)
        return (root, c1, c2, tip)
    }

    private static func drawTail(in ctx: CGContext, physics: CatPhysics, coat: CatCoatTheme, outlineOnly: Bool = false) {
        let (root, c1, c2, tip) = tailCurve(physics)
        let lie = max(0, min(1, physics.lieIntensity.value))
        let lieS = lie * lie * (3.0 - 2.0 * lie)

        ctx.saveGState()
        if outlineOnly {
            ctx.setStrokeColor(blackOutlineColor.cgColor)
            ctx.setLineWidth(11.0 + blackOutlineWidth * 2.0)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: root)
            ctx.addCurve(to: tip, control1: c1, control2: c2)
            ctx.strokePath()
            ctx.restoreGState()
            return
        }
        let tailColor = earTailColor(coat)
        ctx.setStrokeColor(tailColor.cgColor)
        ctx.setLineWidth(coat == .siamese ? 9.5 : 11.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: root)
        ctx.addCurve(to: tip, control1: c1, control2: c2)
        let tailLine = ctx.path
        ctx.strokePath()
        // Crisp upper separation rim on wrapped sleeping tail so it stands out cleanly against the curled torso!
        if lieS > 0.35 {
            let rAlpha = min(1.0, (lieS - 0.35) / 0.45) * 0.72
            let rimCol = (coat == .siamese) ? siameseCrease : creaseColor(coat)
            ctx.saveGState()
            ctx.setStrokeColor(rimCol.withAlphaComponent(rAlpha).cgColor)
            ctx.setLineWidth(1.45)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: root.x - 4, y: root.y - 3))
            ctx.addCurve(
                to: CGPoint(x: tip.x + 2, y: tip.y - 4.5),
                control1: CGPoint(x: c1.x - 6, y: c1.y - 5.5),
                control2: CGPoint(x: c2.x, y: c2.y - 5.5)
            )
            ctx.strokePath()
            ctx.restoreGState()
        }
        if patterned(coat), let line = tailLine {
            ctx.saveGState()
            ctx.addPath(line.copy(strokingWithWidth: 11, lineCap: .round, lineJoin: .round, miterLimit: 10))
            ctx.clip()
            let rings: [CGFloat]
            if coat == .tabby {
                rings = [0.40, 0.58, 0.74, 0.93]
                ctx.setStrokeColor(tabbyStripe.cgColor)
                ctx.setLineWidth(4.0)
            } else {
                rings = [0.50, 0.78]
                ctx.setStrokeColor(rgb(coat == .shorthair ? 0x55595A : 0xA57543, 0.50).cgColor)
                ctx.setLineWidth(3.5)
            }
            ctx.setLineCap(.butt)
            for t in rings {
                let u = 1-t
                let p = CGPoint(x: u*u*u*root.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*tip.x,
                                y: u*u*u*root.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*tip.y)
                let dx = 3*u*u*(c1.x-root.x)+6*u*t*(c2.x-c1.x)+3*t*t*(tip.x-c2.x)
                let dy = 3*u*u*(c1.y-root.y)+6*u*t*(c2.y-c1.y)+3*t*t*(tip.y-c2.y)
                let length = max(0.001, hypot(dx,dy)), nx = -dy/length*8, ny = dx/length*8
                ctx.move(to: CGPoint(x:p.x+nx,y:p.y+ny)); ctx.addLine(to: CGPoint(x:p.x-nx,y:p.y-ny)); ctx.strokePath()
            }
            if coat == .tabby {
                ctx.setFillColor(tabbyStripe.cgColor)
                ctx.fillEllipse(in: CGRect(x: tip.x - 5.5, y: tip.y - 5.5, width: 11, height: 11))
            }
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    // MARK: - Unified C1-Continuous Cat Silhouette (Crown -> Cheeks -> Plush Neck -> Pear Hips)

    private static func drawUnifiedSilhouette(
        in ctx: CGContext,
        seatX: CGFloat,
        seatY: CGFloat,
        headCenter: CGPoint,
        breath: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme,
        outlineOnly: Bool = false
    ) {
        let yaw = physics.headYaw.value
        let pitch = physics.headPitch.value
        let hTilt = physics.headTilt.value
        let bTilt = physics.bodyTilt.value

        let cH = cos(hTilt), sH = sin(hTilt)
        func H(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            CGPoint(
                x: headCenter.x + lx * cH - ly * sH,
                y: headCenter.y + lx * sH + ly * cH
            )
        }

        let cB = cos(bTilt), sB = sin(bTilt)
        let lie = max(0, min(1, physics.lieIntensity.value))
        let lieS = lie * lie * (3.0 - 2.0 * lie)
        let sy = physics.bodySquash.value * (1.0 - lieS * 0.42)
        let sx = (1.0 + (1.0 - physics.bodySquash.value) * 0.55) * (1.0 + lieS * 0.03)
        func B(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            let rx = lx * sx
            let ry = ly * sy
            return CGPoint(
                x: seatX + rx * cB - ry * sB,
                y: seatY + rx * sB + ry * cB
            )
        }

        let isSiamese = (coat == .siamese)
        let cheekShift = yaw * 3.0
        let crownDrop = pitch * 2.0
        let cheekHalfW: CGFloat = isSiamese ? 42.5 : 42.5
        let crownCtrlW: CGFloat = isSiamese ? 25.0 : 26.0
        let crownBaseY: CGFloat = isSiamese ? -29.5 : -30.0
        let cheekY: CGFloat = isSiamese ? 6.5 : 5.0
        let neckPinchX: CGFloat = isSiamese ? 6.5 : 2.5
        let neckCtrlY: CGFloat = isSiamese ? 27.5 : 24.0
        let hipHalfW: CGFloat = isSiamese ? 44.5 : 49.0
        let waistCtrlW: CGFloat = isSiamese ? 41.0 : 51.5
        let waistCtrlY: CGFloat = isSiamese ? -50.0 : -48.0
        let botOuterW: CGFloat = isSiamese ? 42.0 : 47.0
        let botInnerW: CGFloat = isSiamese ? 32.0 : 36.0
        let botHalfW: CGFloat = isSiamese ? 22.0 : 24.0
        let leftCheekX: CGFloat = -cheekHalfW + cheekShift * 0.4
        let rightCheekX: CGFloat = cheekHalfW + cheekShift * 0.4

        // ONE single tangent-continuous closed cubic Bezier path — mathematically impossible to form any ledge or protrusion!
        let crown  = H(cheekShift * 0.2, crownBaseY + crownDrop)
        let rCheek = H(rightCheekX, cheekY)
        let rHip   = B(hipHalfW, -14)
        let rBot   = B(botHalfW, 12)
        let lBot   = B(-botHalfW, 12)
        let lHip   = B(-hipHalfW, -14)
        let lCheek = H(leftCheekX, cheekY)

        let cheekCtrlTopY: CGFloat = isSiamese ? -13.0 : -14.0
        let path = CGMutablePath()
        path.move(to: crown)
        path.addCurve(to: rCheek, control1: H(crownCtrlW + cheekShift * 0.3, crownBaseY + crownDrop), control2: H(rightCheekX + 1.5, cheekCtrlTopY))
        path.addCurve(to: rHip,   control1: H(rightCheekX - neckPinchX, neckCtrlY), control2: B(waistCtrlW, waistCtrlY + breath * 0.5))
        path.addCurve(to: rBot,   control1: B(botOuterW, 5), control2: B(botInnerW, 12))
        path.addLine(to: lBot)
        path.addCurve(to: lHip,   control1: B(-botInnerW, 12), control2: B(-botOuterW, 5))
        path.addCurve(to: lCheek, control1: B(-waistCtrlW, waistCtrlY + breath * 0.5), control2: H(leftCheekX + neckPinchX, neckCtrlY))
        path.addCurve(to: crown,  control1: H(leftCheekX - 1.5, cheekCtrlTopY), control2: H(-crownCtrlW + cheekShift * 0.3, crownBaseY + crownDrop))
        path.closeSubpath()

        if outlineOnly {
            ctx.saveGState()
            ctx.setStrokeColor(blackOutlineColor.cgColor)
            ctx.setLineWidth(blackOutlineWidth * 2.0)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.translateBy(x: seatX, y: seatY)
            ctx.rotate(by: bTilt)
            ctx.scaleBy(x: sx, y: sy)
            ctx.strokeEllipse(in: CGRect(x: -35.0, y: 3.0, width: 17.0, height: 11.0))
            if physics.hindFootActive.value < 0.35 {
                ctx.strokeEllipse(in: CGRect(x: 18.0, y: 4.5, width: 17.0, height: 12.5))
            }
            ctx.restoreGState()
            return
        }

        ctx.saveGState()
        if coat != .siamese {
            ctx.setFillColor(bodyColor(coat).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            if coat == .orangeWhite {
                // Overlap the matching fur colors at the ear/crown join so the
                // white torso underpaint cannot leave an antialiased seam.
                let join = CGMutablePath()
                join.move(to: lCheek)
                join.addCurve(to: crown, control1: H(leftCheekX - 1.5, -14), control2: H(-26 + cheekShift * 0.3, -30 + crownDrop))
                join.addCurve(to: rCheek, control1: H(26 + cheekShift * 0.3, -30 + crownDrop), control2: H(rightCheekX + 1.5, -14))
                ctx.setStrokeColor(earTailColor(coat).cgColor); ctx.setLineWidth(1.0); ctx.setLineCap(.round)
                ctx.addPath(join); ctx.strokePath()
            }
            if patterned(coat) {
                ctx.saveGState(); ctx.addPath(path); ctx.clip()
                drawCoatMarks(in: ctx, seatX: seatX, seatY: seatY, head: headCenter, physics: physics, coat: coat)
                ctx.restoreGState()
            }
        } else {
            // Siamese warm oat-milk cream gradient + soft toasted back shading + 2.5D rotating seal-point face mask!
            ctx.addPath(path)
            ctx.clip()

            let cs = CGColorSpaceCreateDeviceRGB()
            let bodyColors = [siameseCream.cgColor, siameseLatte.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: bodyColors, locations: [0.15, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: seatX, y: headCenter.y - 34),
                    end: CGPoint(x: seatX, y: seatY + 18),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // Soft toasted ear-base blend at top crown so espresso ears melt organically into cream head
            let yawRad = yaw * 0.50
            let pitchRad = pitch * 0.36
            ctx.saveGState()
            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: hTilt)

            // 2.5D Rotating Seal-Point "挖煤" Face Mask (layered soft mocha halo + velvety seal-brown muzzle!)
            let maskCenter = projectHead3D(x: 0, y: 3.0, z: 27.0, yawRad: yawRad, pitchRad: pitchRad).pt
            let maskScaleX = max(0.76, cos(yawRad * 0.7))
            let maskScaleY = max(0.82, cos(pitchRad * 0.7))

            // Layer 1: Soft wide eye-and-cheek mocha mask halo (startRadius: 0 so there is NEVER a center hole!)
            ctx.saveGState()
            ctx.translateBy(x: maskCenter.x, y: maskCenter.y)
            ctx.scaleBy(x: maskScaleX * 1.24, y: maskScaleY * 0.88)
            let maskColors = [
                siamesePoint.cgColor,
                siamesePoint.withAlphaComponent(0.92).cgColor,
                siameseMocha.withAlphaComponent(0.62).cgColor,
                siameseMocha.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let maskGrad = CGGradient(colorsSpace: cs, colors: maskColors, locations: [0.0, 0.42, 0.74, 1.0]) {
                ctx.drawRadialGradient(
                    maskGrad,
                    startCenter: .zero, startRadius: 0,
                    endCenter: .zero, endRadius: 31.5,
                    options: [.drawsBeforeStartLocation]
                )
            }
            ctx.restoreGState()

            // Layer 2: Soft warm cocoa muzzle depth below eyes
            let muzzleCenter = projectHead3D(x: 0, y: 7.5, z: 28.0, yawRad: yawRad, pitchRad: pitchRad).pt
            ctx.saveGState()
            ctx.translateBy(x: muzzleCenter.x, y: muzzleCenter.y)
            ctx.scaleBy(x: maskScaleX * 1.04, y: maskScaleY * 0.76)
            let muzzleColors = [
                siamesePoint.cgColor,
                siamesePoint.withAlphaComponent(0.85).cgColor,
                siamesePoint.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let muzGrad = CGGradient(colorsSpace: cs, colors: muzzleColors, locations: [0.0, 0.50, 1.0]) {
                ctx.drawRadialGradient(
                    muzGrad,
                    startCenter: .zero, startRadius: 0,
                    endCenter: .zero, endRadius: 19.5,
                    options: [.drawsBeforeStartLocation]
                )
            }
            ctx.restoreGState()
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // Ultra-soft plush rim on Siamese cream body (never a harsh dark outline)
        if coat == .siamese {
            ctx.saveGState()
            ctx.setStrokeColor(siameseOutline.cgColor)
            ctx.setLineWidth(1.0)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Tucked hind paws peeking softly along bottom edge
        ctx.saveGState()
        ctx.translateBy(x: seatX, y: seatY)
        ctx.rotate(by: bTilt)
        ctx.scaleBy(x: sx, y: sy)
        ctx.setFillColor(pawColor(coat).cgColor)

        let leftHindX: CGFloat = isSiamese ? -31.0 : -35.0
        let hindW: CGFloat = isSiamese ? 15.5 : 17.0
        let rightHindX: CGFloat = isSiamese ? 15.5 : 18.0
        let leftHindY: CGFloat = isSiamese ? 3.5 : 3.0
        let leftHindH: CGFloat = isSiamese ? 12.0 : 11.0
        let rightHindY: CGFloat = (coat == .classicBlack || isSiamese) ? 4.5 : 3.0
        let rightHindH: CGFloat = (coat == .classicBlack || isSiamese) ? 12.5 : 11.0

        ctx.fillEllipse(in: CGRect(x: leftHindX, y: leftHindY, width: hindW, height: leftHindH))
        if physics.hindFootActive.value < 0.35 {
            ctx.fillEllipse(in: CGRect(x: rightHindX, y: rightHindY, width: hindW, height: rightHindH))
        }

        // Subtle bottom rim highlights on tucked haunches
        let rimColor = (coat == .siamese) ? siameseCream.withAlphaComponent(0.55) : (coat == .classicBlack ? blackOutlineColor.withAlphaComponent(0.0) : creaseColor(coat).withAlphaComponent(0.58))
        ctx.setStrokeColor(rimColor.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: leftHindX + hindW * 0.5, y: leftHindY + leftHindH * 0.5), radius: 7.5, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
        ctx.strokePath()
        if physics.hindFootActive.value < 0.35 {
            ctx.addArc(center: CGPoint(x: rightHindX + hindW * 0.5, y: rightHindY + rightHindH * 0.5), radius: 7.5, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func coatMarkPoint(_ p: CGPoint, headSurface: Bool, skull: Bool, coat: CatCoatTheme, seatX: CGFloat, seatY: CGFloat,
                                      head: CGPoint, physics: CatPhysics, whiteSurface: Bool = false) -> CGPoint {
        if headSurface {
            let radius = max(0, 1 - pow(p.x / 46, 2) - pow(p.y / 40, 2))
            // A zero-slope depth at the cheek rim keeps the white contour from
            // folding into a tip as it turns. Other coat patterns stay unchanged.
            let surface = whiteSurface ? radius * radius * (3 - 2 * radius) : sqrt(radius)
            let depth: CGFloat = coat == .orangeWhite ? 29.6 * surface : 27.5
            let projected = skull ? p : projectHead3D(x: p.x, y: p.y, z: depth,
                                          yawRad: physics.headYaw.value * 0.50,
                                          pitchRad: physics.headPitch.value * 0.36).pt
            let c = cos(physics.headTilt.value), s = sin(physics.headTilt.value)
            return CGPoint(x: head.x + projected.x*c - projected.y*s,
                           y: head.y + projected.x*s + projected.y*c)
        }
        let squash = physics.bodySquash.value
        // Keep the tabby's torso markings attached when the body curls up.
        let lie = coat == .tabby ? max(0, min(1, physics.lieIntensity.value)) : 0
        let lieS = lie * lie * (3 - 2 * lie)
        let sy = squash * (1 - lieS * 0.42)
        let sx = (1 + (1 - squash) * 0.55) * (1 + lieS * 0.03)
        let c = cos(physics.bodyTilt.value), s = sin(physics.bodyTilt.value)
        return CGPoint(x: seatX + p.x*sx*c - p.y*sy*s,
                       y: seatY + p.x*sx*s + p.y*sy*c)
    }
    private static func drawCoatMarks(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat,
                                      head: CGPoint, physics: CatPhysics, coat: CatCoatTheme) {
        let marks = CoatPatterns.marks(for: coat)
        let overlap = min(1, abs(physics.headYaw.value) * max(0, physics.headPitch.value))
        let coverage = overlap * overlap * (3 - 2 * overlap)
        func markPath(_ mark: CoatMark) -> CGMutablePath {
            let path = CGMutablePath()
            for (i, point) in mark.points.enumerated() {
                var local = point
                if mark.clipToBib {
                    let lowerRim = min(1, max(0, (point.y - 20) / 6))
                    local.x *= 1 - 0.5 * lowerRim * (1 - coverage)
                    if point.y > 20 { local.y = 20 + (point.y - 20) * (0.75 + 0.25 * coverage) }
                }
                let p = coatMarkPoint(local, headSurface: mark.head, skull: mark.skull, coat: coat, seatX: seatX, seatY: seatY, head: head, physics: physics, whiteSurface: mark.rgb == 0xF2EEE4)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            if mark.width == 0 { path.closeSubpath() }
            return path
        }
        let bib = marks.first { $0.head && !$0.skull && $0.rgb == 0xF2EEE4 && $0.points.contains { abs($0.x) > 46 } }
        for mark in marks {
            // No extra white coverage in the front view or while looking up.
            if mark.clipToBib && coverage == 0 { continue }
            ctx.saveGState()
            if mark.clipToBib, let bib = bib { ctx.addPath(markPath(bib)); ctx.clip() }
            let path = markPath(mark)
            let color = rgb(mark.rgb, mark.alpha)
            if mark.width == 0 {
                path.closeSubpath(); ctx.setFillColor(color.cgColor); ctx.addPath(path); ctx.fillPath()
            } else {
                ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(mark.width)
                ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.addPath(path); ctx.strokePath()
            }
            ctx.restoreGState()
        }

    }

    // MARK: - 3rd Key Hind Foot Easter Egg

    private static func drawHindFoot(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat, physics: CatPhysics, coat: CatCoatTheme) {
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
            coat: coat
        )
    }

    // MARK: - 2.5D Spherical Head Projection Helper

    /// Projects a 3D point on the cat's head ellipsoid rotated by (yawRad, pitchRad)
    /// into 2D head-local coordinates — creating true Live2D-style 2.5D head turning!
    private static func projectHead3D(
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
        coat: CatCoatTheme,
        outlineOnly: Bool = false
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: physics.headTilt.value)

        let yawRad = physics.headYaw.value * 0.50
        let pitchRad = physics.headPitch.value * 0.36
        let fold = physics.earFold.value
        let twitch = physics.earTwitch.value * 0.045

        drawEar3D(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: twitch, coat: coat, outlineOnly: outlineOnly)
        drawEar3D(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: -twitch, coat: coat, outlineOnly: outlineOnly)

        ctx.restoreGState()
    }

    // MARK: - 2.5D Head Features (Luminous Eyes & Whiskers)

    private static func drawHeadFeatures(
        in ctx: CGContext,
        center: CGPoint,
        physics: CatPhysics,
        eyeTheme: EyeColorTheme,
        coat: CatCoatTheme
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: physics.headTilt.value)

        let yaw = physics.headYaw.value      // -1 (left) .. +1 (right)
        let pitch = physics.headPitch.value  // -1 (up)   .. +1 (down)
        let yawRad = yaw * 0.50              // ~±28.5° authentic head turn
        let pitchRad = pitch * 0.36          // ~±20.5° authentic head nod

        // 1. 3D-Projected Eyes with authentic spherical foreshortening & parallax!
        drawEye3D(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, physics: physics, eyeTheme: eyeTheme, coat: coat)
        drawEye3D(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, physics: physics, eyeTheme: eyeTheme, coat: coat)

        // 1b. Cute little kitty nose + delicate `:3` mouth hint on Siamese (小豆泥 charm!)
        if coat == .siamese {
            let nose = projectHead3D(x: 0, y: 8.2, z: 29.0, yawRad: yawRad, pitchRad: pitchRad).pt
            let mouthL = projectHead3D(x: -4.2, y: 12.2, z: 28.4, yawRad: yawRad, pitchRad: pitchRad).pt
            let mouthM = projectHead3D(x: 0, y: 11.2, z: 28.8, yawRad: yawRad, pitchRad: pitchRad).pt
            let mouthR = projectHead3D(x: 4.2, y: 12.2, z: 28.4, yawRad: yawRad, pitchRad: pitchRad).pt
            ctx.saveGState()
            // Tiny warm dark-rose-espresso triangle nose
            let nPath = CGMutablePath()
            nPath.move(to: CGPoint(x: nose.x - 2.3, y: nose.y - 1.1))
            nPath.addQuadCurve(to: CGPoint(x: nose.x + 2.3, y: nose.y - 1.1), control: CGPoint(x: nose.x, y: nose.y - 1.6))
            nPath.addQuadCurve(to: CGPoint(x: nose.x, y: nose.y + 1.5), control: CGPoint(x: nose.x + 1.8, y: nose.y + 0.6))
            nPath.addQuadCurve(to: CGPoint(x: nose.x - 2.3, y: nose.y - 1.1), control: CGPoint(x: nose.x - 1.8, y: nose.y + 0.6))
            nPath.closeSubpath()
            ctx.setFillColor(NSColor(calibratedRed: 0.14, green: 0.09, blue: 0.08, alpha: 0.95).cgColor)
            ctx.addPath(nPath)
            ctx.fillPath()
            // Delicate light-mocha `ω` kitty mouth (hidden while mouth is open yawning)
            if physics.yawnAmount < 0.15 {
                ctx.setStrokeColor(NSColor(calibratedRed: 0.78, green: 0.66, blue: 0.56, alpha: 0.55).cgColor)
                ctx.setLineWidth(1.05)
                ctx.setLineCap(.round)
                ctx.move(to: mouthL)
                ctx.addQuadCurve(to: mouthM, control: CGPoint(x: (mouthL.x + mouthM.x) * 0.5, y: mouthL.y + 1.6))
                ctx.addQuadCurve(to: mouthR, control: CGPoint(x: (mouthM.x + mouthR.x) * 0.5, y: mouthR.y + 1.6))
                ctx.strokePath()
            }
            ctx.restoreGState()
        }

        if patterned(coat) { drawPatternedMuzzle(in: ctx, yawRad: yawRad, pitchRad: pitchRad, coat: coat) }
        if physics.yawnAmount > 0.03 {
            drawYawnMouth(in: ctx, yawRad: yawRad, pitchRad: pitchRad, yawn: physics.yawnAmount, coat: coat)
        }

        // 2. 3D-Projected Whiskers (outer-side whiskers poke out past silhouette when turning!)
        drawWhiskers3D(in: ctx, yawRad: yawRad, pitchRad: pitchRad, physics: physics, coat: coat)

        // 3. Expressive emotion badges: Anger vein (💢) & Dizzy orbiting stars (✦) & Scruff pinch!
        let anger = max(0, min(1, physics.angerIntensity.value))
        if anger > 0.25 {
            let aAlpha = min(1.0, (anger - 0.25) / 0.35)
            let pulse = 1.0 + sin(physics.time * 14.0) * 0.10
            let pt = projectHead3D(x: 28.0, y: -22.0, z: 24.0, yawRad: yawRad, pitchRad: pitchRad).pt
            ctx.saveGState()
            ctx.translateBy(x: pt.x, y: pt.y)
            ctx.scaleBy(x: pulse, y: pulse)
            ctx.setStrokeColor(NSColor(calibratedRed: 0.96, green: 0.22, blue: 0.28, alpha: 0.95 * aAlpha).cgColor)
            ctx.setLineWidth(2.0)
            ctx.setLineCap(.round)
            // Classic 4-corner anime anger vein mark
            let d: CGFloat = 2.4, r: CGFloat = 6.2
            for (sx, sy): (CGFloat, CGFloat) in [(-1,-1), (1,-1), (-1,1), (1,1)] {
                ctx.move(to: CGPoint(x: sx * r, y: sy * d))
                ctx.addQuadCurve(to: CGPoint(x: sx * d, y: sy * r), control: CGPoint(x: sx * d, y: sy * d))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }

        ctx.restoreGState()
    }

    private static func drawYawnMouth(in ctx: CGContext, yawRad: CGFloat, pitchRad: CGFloat, yawn: CGFloat, coat: CatCoatTheme) {
        let y = max(0, min(1, yawn))
        let center = projectHead3D(x: 0, y: 16.2 + y * 2.2, z: 30.2, yawRad: yawRad, pitchRad: pitchRad).pt
        let rx = 3.2 + y * 5.8
        let ry = 1.6 + y * 7.4

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)

        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 0, y: -ry * 0.92))
        mouth.addCurve(to: CGPoint(x: rx, y: ry * 0.08), control1: CGPoint(x: rx * 0.68, y: -ry * 0.92), control2: CGPoint(x: rx * 1.05, y: -ry * 0.42))
        mouth.addCurve(to: CGPoint(x: 0, y: ry), control1: CGPoint(x: rx * 0.95, y: ry * 0.72), control2: CGPoint(x: rx * 0.50, y: ry))
        mouth.addCurve(to: CGPoint(x: -rx, y: ry * 0.08), control1: CGPoint(x: -rx * 0.50, y: ry), control2: CGPoint(x: -rx * 0.95, y: ry * 0.72))
        mouth.addCurve(to: CGPoint(x: 0, y: -ry * 0.92), control1: CGPoint(x: -rx * 1.05, y: -ry * 0.42), control2: CGPoint(x: -rx * 0.68, y: -ry * 0.92))
        mouth.closeSubpath()

        ctx.setFillColor(NSColor(calibratedRed: 0.78, green: 0.19, blue: 0.25, alpha: 0.98).cgColor)
        ctx.addPath(mouth)
        ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(mouth)
        ctx.clip()

        ctx.setFillColor(NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.16, alpha: 0.55).cgColor)
        ctx.fillEllipse(in: CGRect(x: -rx * 0.65, y: -ry * 0.72, width: rx * 1.30, height: ry * 0.92))

        if y > 0.22 {
            let tAlpha = min(1.0, (y - 0.22) / 0.35)
            ctx.setFillColor(NSColor(calibratedRed: 0.95, green: 0.48, blue: 0.55, alpha: 0.92 * tAlpha).cgColor)
            let tongue = CGMutablePath()
            tongue.move(to: CGPoint(x: -rx * 0.62, y: ry * 0.55))
            tongue.addQuadCurve(to: CGPoint(x: 0, y: ry * 0.36), control: CGPoint(x: -rx * 0.32, y: ry * 0.16))
            tongue.addQuadCurve(to: CGPoint(x: rx * 0.62, y: ry * 0.55), control: CGPoint(x: rx * 0.32, y: ry * 0.16))
            tongue.addQuadCurve(to: CGPoint(x: -rx * 0.62, y: ry * 0.55), control: CGPoint(x: 0, y: ry * 1.25))
            tongue.closeSubpath()
            ctx.addPath(tongue)
            ctx.fillPath()
        }

        if y > 0.28 {
            let fScale = min(1.0, (y - 0.28) / 0.32)
            ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.96, alpha: 0.98).cgColor)
            let upperBaseY = -ry * 0.80
            let upperLen = (2.6 + y * 2.2) * fScale
            let upperHalfW = (1.15 + y * 0.55) * fScale
            for sign: CGFloat in [-1, 1] {
                let fx = sign * rx * 0.46
                let fang = CGMutablePath()
                fang.move(to: CGPoint(x: fx - upperHalfW, y: upperBaseY - 0.8))
                fang.addLine(to: CGPoint(x: fx + upperHalfW, y: upperBaseY - 0.8))
                fang.addQuadCurve(to: CGPoint(x: fx - sign * 0.25, y: upperBaseY + upperLen), control: CGPoint(x: fx + upperHalfW * 0.45, y: upperBaseY + upperLen * 0.62))
                fang.addQuadCurve(to: CGPoint(x: fx - upperHalfW, y: upperBaseY - 0.8), control: CGPoint(x: fx - upperHalfW * 0.45, y: upperBaseY + upperLen * 0.62))
                fang.closeSubpath()
                ctx.addPath(fang)
                ctx.fillPath()
            }
            let lowerBaseY = ry * 0.84
            let lowerLen = (1.6 + y * 1.3) * fScale
            let lowerHalfW = (0.85 + y * 0.35) * fScale
            for sign: CGFloat in [-1, 1] {
                let fx = sign * rx * 0.36
                let fang = CGMutablePath()
                fang.move(to: CGPoint(x: fx - lowerHalfW, y: lowerBaseY + 0.8))
                fang.addLine(to: CGPoint(x: fx + lowerHalfW, y: lowerBaseY + 0.8))
                fang.addQuadCurve(to: CGPoint(x: fx - sign * 0.15, y: lowerBaseY - lowerLen), control: CGPoint(x: fx + lowerHalfW * 0.4, y: lowerBaseY - lowerLen * 0.55))
                fang.addQuadCurve(to: CGPoint(x: fx - lowerHalfW, y: lowerBaseY + 0.8), control: CGPoint(x: fx - lowerHalfW * 0.4, y: lowerBaseY - lowerLen * 0.55))
                fang.closeSubpath()
                ctx.addPath(fang)
                ctx.fillPath()
            }
        }
        ctx.restoreGState()

        let rimColor: NSColor = (coat == .classicBlack || coat == .siamese)
            ? NSColor(calibratedRed: 0.42, green: 0.08, blue: 0.12, alpha: 0.85)
            : NSColor(calibratedRed: 0.56, green: 0.22, blue: 0.26, alpha: 0.72)
        ctx.setStrokeColor(rimColor.cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(mouth)
        ctx.strokePath()

        ctx.restoreGState()
    }

    // Small opaque nose and soft mouth on the existing white muzzle, below whiskers.
    // All control points share the head's yaw/pitch projection; the caller applies roll.
    private static func drawPatternedMuzzle(in ctx: CGContext, yawRad: CGFloat, pitchRad: CGFloat, coat: CatCoatTheme) {
        let local: [CGPoint] = [CGPoint(x: -2.9, y: 8.5), CGPoint(x: -1.8, y: 8.1), CGPoint(x: 1.8, y: 8.1), CGPoint(x: 2.9, y: 8.5), CGPoint(x: 3.2, y: 8.9), CGPoint(x: 0.8, y: 12.1), CGPoint(x: 0, y: 12.3), CGPoint(x: -0.8, y: 12.1), CGPoint(x: -3.2, y: 8.9), CGPoint(x: -2.9, y: 8.5), CGPoint(x: -5.9, y: 14.4), CGPoint(x: -4.7, y: 18), CGPoint(x: -1.4, y: 18), CGPoint(x: 0, y: 14.3), CGPoint(x: 1.4, y: 18), CGPoint(x: 4.7, y: 18), CGPoint(x: 5.9, y: 14.4), CGPoint(x: 0, y: 12.0)]
        let p = local.map { projectHead3D(x: $0.x, y: $0.y, z: 30, yawRad: yawRad, pitchRad: pitchRad).pt }
        ctx.saveGState()
        let nose = CGMutablePath()
        nose.move(to: p[0])
        nose.addCurve(to: p[3], control1: p[1], control2: p[2])
        nose.addCurve(to: p[6], control1: p[4], control2: p[5])
        nose.addCurve(to: p[9], control1: p[7], control2: p[8])
        nose.closeSubpath()
        ctx.setFillColor((coat == .tabby ? rgb(0x5E493D) : rgb(0xD98F9B)).cgColor)
        ctx.addPath(nose); ctx.fillPath()
        ctx.setStrokeColor((coat == .tabby ? tabbyStripe : rgb(0x8B8C86, 0.78)).cgColor)
        ctx.setLineWidth(1.15); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to: p[17]); ctx.addLine(to: p[13])
        ctx.move(to: p[10]); ctx.addCurve(to: p[13], control1: p[11], control2: p[12])
        ctx.addCurve(to: p[16], control1: p[14], control2: p[15]); ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawEar3D(
        in ctx: CGContext,
        isLeft: Bool,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        fold: CGFloat,
        twitch: CGFloat,
        coat: CatCoatTheme,
        outlineOnly: Bool = false
    ) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        let isSiamese = (coat == .siamese)
        // Siamese (小豆泥 style): cute, compact, softly-rounded triangular cat ears
        let foldAngle = sign * ((isSiamese ? 0.14 : 0.06) + fold * 0.34) + twitch
        let earLen: CGFloat = isSiamese ? 29.5 : 32.0

        let tipDx = sin(foldAngle) * earLen
        let tipDy = -cos(foldAngle) * earLen

        // Bases anchored comfortably inside the upper skull contour so they merge seamlessly at every yaw/pitch!
        let innerBase3D = projectHead3D(x: sign * (isSiamese ? 10.0 : 9.0), y: isSiamese ? -16.5 : -16.0, z: 0.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let outerBase3D = projectHead3D(x: sign * (isSiamese ? 35.5 : 35.0), y: isSiamese ? -4.5 : -5.0, z: -2.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let tip3D       = projectHead3D(x: sign * (isSiamese ? 25.0 : 24.5) + tipDx, y: (isSiamese ? -18.5 : -20.0) + tipDy, z: -3.0, yawRad: yawRad, pitchRad: pitchRad).pt

        // Soft plush rounded-tip feline ear
        let tipSpread: CGFloat = isSiamese ? 4.2 : 3.8
        let tipLeft  = CGPoint(x: tip3D.x - sign * tipSpread, y: tip3D.y + 2.8)
        let tipRight = CGPoint(x: tip3D.x + sign * tipSpread, y: tip3D.y + 3.2)

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

        ctx.saveGState()
        if outlineOnly {
            ctx.setStrokeColor(blackOutlineColor.cgColor)
            ctx.setLineWidth(blackOutlineWidth * 2.0)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.addPath(ear)
            ctx.strokePath()
            ctx.restoreGState()
            return
        }
        ctx.setFillColor(earTailColor(coat).cgColor)
        ctx.addPath(ear)
        ctx.fillPath()

        // Inner ear follows the same projected ear geometry as it tilts or folds.
        if isSiamese || coat == .tabby {
            let inI = CGPoint(x: innerBase3D.x + (tip3D.x - innerBase3D.x) * 0.24 + sign * 3.0,
                              y: innerBase3D.y + (tip3D.y - innerBase3D.y) * 0.16)
            let outI = CGPoint(x: outerBase3D.x + (tip3D.x - outerBase3D.x) * 0.20 - sign * 3.8,
                               y: outerBase3D.y + (tip3D.y - outerBase3D.y) * 0.18)
            let tipI = CGPoint(x: (innerBase3D.x + outerBase3D.x) * 0.16 + tip3D.x * 0.68,
                               y: (innerBase3D.y + outerBase3D.y) * 0.14 + tip3D.y * 0.72 + 2.5)
            let inner = CGMutablePath()
            inner.move(to: inI)
            inner.addQuadCurve(to: tipI, control: CGPoint(x: (inI.x + tipI.x) * 0.5 - sign * 0.8, y: (inI.y + tipI.y) * 0.5))
            inner.addQuadCurve(to: outI, control: CGPoint(x: (outI.x + tipI.x) * 0.5 + sign * 1.2, y: (outI.y + tipI.y) * 0.5))
            inner.closeSubpath()
            ctx.setFillColor((isSiamese ? siameseInnerEar : rgb(0xB6A087)).cgColor)
            ctx.addPath(inner)
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
        eyeTheme: EyeColorTheme,
        coat: CatCoatTheme
    ) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        let eyeColor = eyeTheme.primaryColor

        // Eye sits on the front surface of the 3D head sphere at (±17.5, -2.0, +28.0)
        let proj = projectHead3D(x: sign * 17.2, y: -2.0, z: 27.5, yawRad: yawRad, pitchRad: pitchRad)

        // Authentic spherical foreshortening: the eye turning away toward the edge narrows horizontally!
        let eyeNormalAngle = yawRad + sign * 0.34
        let foreshortenX = max(0.64, min(1.06, cos(eyeNormalAngle) / cos(0.34)))
        let foreshortenY = max(0.78, min(1.03, cos(pitchRad * 0.85)))

        ctx.saveGState()
        ctx.translateBy(x: proj.pt.x, y: proj.pt.y)
        ctx.scaleBy(x: foreshortenX, y: foreshortenY)

        // Mode 0: Dizzy spinning spiral eyes (@ @) — appear AFTER initial golden stars warning (>0.28)!
        let dizzy = max(0, min(1, physics.dizzyIntensity.value))
        if dizzy > 0.28 {
            ctx.setFillColor(NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.96, alpha: 0.95).cgColor)
            ctx.fillEllipse(in: CGRect(x: -11.5, y: -11.0, width: 23.0, height: 22.0))
            ctx.setStrokeColor(NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.18, alpha: 0.95).cgColor)
            ctx.setLineWidth(1.85)
            ctx.setLineCap(.round)
            let spiral = CGMutablePath()
            let spin = physics.dizzyPhase * (isLeft ? 1.0 : -1.0)
            for step in 0...42 {
                let t = CGFloat(step) / 42.0
                let theta = spin + t * .pi * 5.2
                let rad = 1.0 + t * 8.6
                let px = cos(theta) * rad
                let py = sin(theta) * rad
                if step == 0 { spiral.move(to: CGPoint(x: px, y: py)) }
                else { spiral.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.addPath(spiral)
            ctx.strokePath()
            ctx.restoreGState()
            return
        }

        // Mode 1: Happy closed glowing lime-green curved line eyes (petting head!)
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

        // Mode 2: Blissful half-squint glowing lime slits (petting back/body!)
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

        let hunt = max(0, min(1, physics.huntIntensity.value))

        // Subtle feline eye angle (straightens slightly when wide-eyed hunting!)
        ctx.rotate(by: sign * (0.06 * (1.0 - hunt * 0.6)))

        // Eyes grow rounder & slightly larger in full hunting focus!
        let isSiameseEye = (coat == .siamese && eyeTheme == .siameseBlue)
        let rx: CGFloat = (isSiameseEye ? 11.4 + hunt * 1.3 : 12.0 + hunt * 1.1)
        let ry: CGFloat = (isSiameseEye ? 9.8 + hunt * 2.0 : 10.8 + hunt * 1.8)
        let eyeRect = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)

        // Clip to the visible opening before painting any iris/pupil pixels.
        // Painting a lid over an antialiased oval leaves a colored fringe.
        ctx.saveGState()
        ctx.addEllipse(in: eyeRect)
        ctx.clip()

        let closure = max(0, min(1, physics.effectiveEyeClosure))
        if closure >= 1 {
            ctx.restoreGState()
            ctx.restoreGState()
            return
        }
        if closure > 0 {
            ctx.clip(to: CGRect(x: -rx - 2, y: -ry + 2 * ry * closure,
                                width: 2 * rx + 4, height: 2 * ry * (1 - closure)))
        }

        // Luminous iris (flat-art translucent pale crystal ice-blue top-to-bottom wash for Siamese!)
        ctx.setFillColor(eyeColor.cgColor)
        ctx.fill(eyeRect)
        if eyeTheme == .siameseBlue {
            let cs = CGColorSpaceCreateDeviceRGB()
            let irisCols = [
                NSColor(calibratedRed: 0.56, green: 0.77, blue: 0.90, alpha: 1.0).cgColor,  // #8FC4E6 soft cool upper iris
                NSColor(calibratedRed: 0.71, green: 0.87, blue: 0.96, alpha: 1.0).cgColor,  // #B5DEF5 airy pale sky blue
                NSColor(calibratedRed: 0.86, green: 0.945, blue: 0.99, alpha: 1.0).cgColor  // #DBF1FC clear luminous lower iris
            ] as CFArray
            if let irisGrad = CGGradient(colorsSpace: cs, colors: irisCols, locations: [0.0, 0.55, 1.0]) {
                ctx.drawLinearGradient(
                    irisGrad,
                    start: CGPoint(x: 0, y: -ry),
                    end: CGPoint(x: 0, y: ry),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        }

        // Pupil morphs smoothly from vertical almond slit -> HUGE round black boba pupil when hunting!
        let gaze = physics.eyeGaze.point
        let px = gaze.x * (4.2 - hunt * 1.2)
        let py = gaze.y * (3.6 - hunt * 1.0)
        let pScale = physics.pupilScale.value
        let normalW: CGFloat = 5.0 * pScale
        let normalH: CGFloat = 13.5 * min(1.12, pScale)
        let huntDiameter: CGFloat = 18.8 // huge round boba pupil leaving an electric chartreuse ring!
        let pupilW = normalW + (huntDiameter - normalW) * hunt
        let pupilH = normalH + (huntDiameter - normalH) * hunt
        let pupilRect = CGRect(x: px - pupilW * 0.5, y: py - pupilH * 0.5, width: pupilW, height: pupilH)
        // Photo-sampled hazel: #DAB257 outside, a narrow #8D9180 ring by the pupil.
        // Paint inside the existing lid clip and follow the animated pupil position/size.
        if eyeTheme == .referenceHazel {
            for i in 0...24 {
                let t = CGFloat(i) / 24
                let mix = t * t * (3 - 2 * t)
                ctx.setFillColor(NSColor(calibratedRed: (218 - 77 * mix)/255,
                    green: (178 - 33 * mix)/255, blue: (87 + 41 * mix)/255, alpha: 1).cgColor)
                let rim = (1 - t) * 2.2
                ctx.fillEllipse(in: pupilRect.insetBy(dx: -rim, dy: -rim))
            }
        }
        ctx.setFillColor(catBlack.cgColor)
        ctx.fillEllipse(in: pupilRect)

        // Tiny crisp white specular sparkle dot (subtle catchlight on translucent Siamese blue eyes + hunting boba sparkle!)
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
        } else if eyeTheme == .siameseBlue {
            ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.86).cgColor)
            let glintR: CGFloat = 1.65
            ctx.fillEllipse(in: CGRect(
                x: px - 2.9 - glintR,
                y: py - 3.6 - glintR,
                width: glintR * 2,
                height: glintR * 2
            ))
        }

        ctx.restoreGState()

        // Angry furrowed V-brow slant over upper inner corner of each eye when typing super fast!
        let anger = max(0, min(1, physics.angerIntensity.value))
        if anger > 0.15 {
            let lidColor: NSColor = (coat == .siamese) ? siamesePoint : bodyColor(coat)
            ctx.saveGState()
            let brow = CGMutablePath()
            let drop = 7.5 * anger
            brow.move(to: CGPoint(x: -sign * 13.5, y: -12.5))
            brow.addLine(to: CGPoint(x: sign * 13.5, y: -12.5))
            brow.addLine(to: CGPoint(x: sign * 13.5, y: -7.5))
            brow.addLine(to: CGPoint(x: -sign * 13.5, y: -6.5 + drop))
            brow.closeSubpath()
            ctx.setFillColor(lidColor.cgColor)
            ctx.addPath(brow)
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.restoreGState()
    }

    private static func drawWhiskers3D(
        in ctx: CGContext,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        let wiggle = sin(physics.time * 4.5) * (max(physics.petHeadIntensity, physics.petBodyIntensity) * 1.2)
        ctx.saveGState()
        let wColor: NSColor
        switch coat {
        case .siamese: wColor = siameseWhisker
        case .tabby: wColor = rgb(0xF0E4CD, 0.78)
        case .shorthair, .orangeWhite: wColor = rgb(0x8D8170, 0.68)
        case .classicBlack: wColor = whiskerColor.withAlphaComponent(0.68)
        }
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
        coat: CatCoatTheme
    ) {
        let lPos = physics.leftPaw.point
        let rPos = physics.rightPaw.point

        let lDist = hypot(lPos.x - CatPhysics.leftPawRest.x, lPos.y - CatPhysics.leftPawRest.y)
        let rDist = hypot(rPos.x - CatPhysics.rightPawRest.x, rPos.y - CatPhysics.rightPawRest.y)

        // Attach to the transformed chest, below the moving face rather than its white blaze.
        let isSiamese = (coat == .siamese)
        let siameseLift: CGFloat = isSiamese ? -3.0 : 0.0
        let lie = max(0, min(1, physics.lieIntensity.value))
        let lieS = lie * lie * (3.0 - 2.0 * lie)
        // When curling into a cozy sleeping ball, tuck front legs neatly inward underneath the chin (揣手手)!
        let idleTopY: CGFloat = (isSiamese ? seatY - 31 : seatY - 30) + lieS * 24.0
        let idleTopX: CGFloat = (isSiamese ? 16.5 : 18.0) - lieS * 5.0
        let idleBotX: CGFloat = (isSiamese ? 15.0 : 16.0) - lieS * 4.5
        let idleBotY: CGFloat = seatY + 12.0 - lieS * 4.0
        let shX: CGFloat = isSiamese ? 18.5 : 20.0
        func shoulder(_ x: CGFloat) -> CGPoint {
            let sy = physics.bodySquash.value * (1.0 - lieS * 0.42)
            let sx = (1.0 + (1.0 - physics.bodySquash.value) * 0.55) * (1.0 + lieS * 0.03)
            let c = cos(physics.bodyTilt.value), s = sin(physics.bodyTilt.value)
            let faceBottom = 126 + siameseLift + physics.headOffsetY.value + physics.headPitch.value * 4.8 + breath * 1.1 + 42
            return CGPoint(x: seatX + x*sx*c + 58*sy*s,
                           y: max(seatY + x*sx*s - 58*sy*c, faceBottom))
        }
        let leftShoulder = shoulder(-shX)
        let rightShoulder = shoulder(shX)

        // Left arm
        if lDist < 6.0 && !physics.leftPawOnMouse && !physics.leftPawTyping {
            if lieS < 0.78 {
                drawIdleFrontLeg(in: ctx, top: CGPoint(x: seatX - idleTopX, y: idleTopY), bottom: CGPoint(x: seatX - idleBotX, y: idleBotY), isLeft: true, coat: coat)
            }
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
                startWidth: isSiamese ? 17.0 : 19.0,
                endWidth: isSiamese ? 12.5 : 13.5,
                outlineOnLeftSide: false,
                outlineAlpha: 0.78,
                coat: coat
            )
        }

        // Right arm
        if rDist < 6.0 && !physics.rightPawTyping {
            if lieS < 0.78 {
                drawIdleFrontLeg(in: ctx, top: CGPoint(x: seatX + idleTopX, y: idleTopY), bottom: CGPoint(x: seatX + idleBotX, y: idleBotY), isLeft: false, coat: coat)
            }
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
                startWidth: isSiamese ? 17.0 : 19.0,
                endWidth: isSiamese ? 12.5 : 13.5,
                outlineOnLeftSide: true,
                outlineAlpha: 0.78,
                coat: coat
            )
        }
    }

    /// Signature tucked sitting front legs (black with mint lines OR Siamese cream-to-chocolate socks!)
    private static func drawIdleFrontLeg(in ctx: CGContext, top: CGPoint, bottom: CGPoint, isLeft: Bool, coat: CatCoatTheme) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        ctx.saveGState()

        if coat == .siamese {
            // Creamy upper leg dipping smoothly into adorable seal-point chocolate socks resting on the keyboard!
            let legRect = CGRect(x: bottom.x - 7.5, y: top.y, width: 15.0, height: bottom.y - top.y + 5.0)
            let legPath = CGPath(roundedRect: legRect, cornerWidth: 6.5, cornerHeight: 6.5, transform: nil)
            ctx.saveGState()
            ctx.addPath(legPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                siameseCream.withAlphaComponent(0.0).cgColor,
                siameseMocha.withAlphaComponent(0.75).cgColor,
                siamesePoint.cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.05, 0.50, 0.82]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: top.x, y: top.y),
                    end: CGPoint(x: bottom.x, y: bottom.y + 5.0),
                    options: []
                )
            }
            ctx.restoreGState()
        }

        if patterned(coat) || coat == .classicBlack {
            let cuff = CGRect(x: bottom.x - 7.5, y: bottom.y - 13, width: 15, height: 18)
            let cuffPath = CGPath(roundedRect: cuff, cornerWidth: 6.5, cornerHeight: 6.5, transform: nil)
            if coat == .classicBlack {
                ctx.saveGState()
                ctx.setStrokeColor(blackOutlineColor.cgColor)
                ctx.setLineWidth(blackOutlineWidth * 1.8)
                ctx.setLineCap(.round)
                ctx.addArc(center: CGPoint(x: bottom.x, y: bottom.y - 1.5), radius: 7.2, startAngle: 0.15, endAngle: .pi - 0.15, clockwise: false)
                ctx.strokePath()
                ctx.restoreGState()
            }
            ctx.setFillColor(pawColor(coat).cgColor)
            ctx.addPath(cuffPath)
            ctx.fillPath()
        }
        if coat == .tabby {
            ctx.setStrokeColor(tabbyStripe.cgColor)
            ctx.setLineWidth(2.8)
            ctx.setLineCap(.round)
            for progress: CGFloat in [0.19, 0.43, 0.67] {
                let x = top.x + (bottom.x - top.x) * progress
                let y = top.y + (bottom.y - top.y) * progress
                ctx.move(to: CGPoint(x: x - 6 * sign, y: y + 1.5))
                ctx.addQuadCurve(to: CGPoint(x: x + 7 * sign, y: y),
                                 control: CGPoint(x: x, y: y + 4))
            }
            ctx.strokePath()
        }
        let lineColor = (coat == .siamese) ? siameseCrease : (coat == .classicBlack ? blackOutlineColor.withAlphaComponent(0.75) : creaseColor(coat))
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

    /// Smooth tapered limb + plump rounded paw (matte black OR Siamese cream-to-espresso chocolate socks!)
    private static func drawLimb(
        in ctx: CGContext,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat,
        outlineOnLeftSide: Bool,
        outlineAlpha: CGFloat,
        coat: CatCoatTheme
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
        let tangent = quadTangent(start, control, end, t: 0)
        let length = max(0.001, hypot(tangent.x, tangent.y))
        limbPath.addQuadCurve(to: leftEdge[0], control: CGPoint(
            x: start.x - tangent.x/length*startWidth*0.5,
            y: start.y - tangent.y/length*startWidth*0.5))
        limbPath.closeSubpath()

        let pawR = endWidth * 0.58
        let pawRect = CGRect(x: end.x - pawR, y: end.y - pawR * 0.85, width: pawR * 2, height: pawR * 1.7)

        ctx.saveGState()
        if coat == .classicBlack {
            ctx.setStrokeColor(blackOutlineColor.cgColor)
            ctx.setLineWidth(blackOutlineWidth * 2.0)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let startIdx = 2
            if leftEdge.count > startIdx + 1 {
                ctx.move(to: leftEdge[startIdx])
                for idx in (startIdx + 1)..<leftEdge.count { ctx.addLine(to: leftEdge[idx]) }
                ctx.strokePath()
            }
            if rightEdge.count > startIdx + 1 {
                ctx.move(to: rightEdge[startIdx])
                for idx in (startIdx + 1)..<rightEdge.count { ctx.addLine(to: rightEdge[idx]) }
                ctx.strokePath()
            }
            ctx.strokeEllipse(in: pawRect)
        }
        if coat == .tabby {
            ctx.setFillColor(limbColor(coat).cgColor)
            ctx.addPath(limbPath)
            ctx.fillPath()
            // Span pairs of sampled edges so the bands bend with the limb.
            ctx.setFillColor(tabbyStripe.cgColor)
            for i in [4, 7, 10] {
                ctx.move(to: leftEdge[i])
                ctx.addLine(to: leftEdge[i + 1])
                ctx.addLine(to: rightEdge[i + 2])
                ctx.addLine(to: rightEdge[i + 1])
                ctx.closePath()
            }
            ctx.fillPath()
            ctx.setFillColor(pawColor(coat).cgColor)
            ctx.fillEllipse(in: pawRect)
        } else if coat != .siamese {
            ctx.setFillColor((patterned(coat) ? pawColor(coat) : limbColor(coat)).cgColor)
            ctx.addPath(limbPath)
            ctx.fillPath()
            if !patterned(coat) { ctx.fillEllipse(in: pawRect) }
            if patterned(coat) {
                let cuff = CGMutablePath()
                let first = Int(CGFloat(steps) * 0.72)
                cuff.move(to: leftEdge[first])
                for pt in leftEdge.dropFirst(first + 1) { cuff.addLine(to: pt) }
                for pt in rightEdge.dropFirst(first).reversed() { cuff.addLine(to: pt) }
                cuff.closeSubpath()
                ctx.setFillColor(pawColor(coat).cgColor); ctx.addPath(cuff); ctx.fillPath()
                ctx.fillEllipse(in: pawRect)
            }
        } else {
            // Siamese chocolate-dipped socks gradient along the limb!
            // Starts transparent at shoulder (0.0) so it melts 100% seamlessly into the creamy chest!
            ctx.saveGState()
            ctx.addPath(limbPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                siameseCream.withAlphaComponent(0.0).cgColor,
                siameseCream.cgColor,
                siameseMocha.cgColor,
                siamesePoint.cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 0.16, 0.48, 0.78]) {
                ctx.drawLinearGradient(grad, start: start, end: end, options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()

            // Solid rich espresso-chocolate rounded paw tip (no winding-rule overlap artifacts!)
            ctx.setFillColor(siamesePoint.cgColor)
            ctx.fillEllipse(in: pawRect)

            // Clean outer edge outline on Siamese arm (fading in below shoulder) so it reads crisply over light backgrounds
            ctx.setStrokeColor(siameseOutline.withAlphaComponent(0.72).cgColor)
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
        if highlightEdge.count > 6 && coat != .classicBlack {
            let strokeColor = (coat == .siamese)
                ? siameseOutline.withAlphaComponent(outlineAlpha * 0.78)
                : creaseColor(coat).withAlphaComponent(outlineAlpha * 0.9)
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
            let fontSize: CGFloat = charCount <= 1 ? 11.5 : 10.0
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
            ]
            let attrStr = NSAttributedString(string: badge.label, attributes: attrs)
            let strSize = attrStr.size()
            let w: CGFloat = max(23, ceil(strSize.width) + 12)
            let h: CGFloat = 22

            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: badge.position.x, y: badge.position.y)
            ctx.rotate(by: badge.rotation)
            ctx.scaleBy(x: CatSettings.shared.flipHorizontal ? -scale : scale, y: scale)

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

    private static func drawSparkles(in ctx: CGContext, physics: CatPhysics, eyeTheme: EyeColorTheme) {
        for sp in physics.sparkles {
            let p = sp.age / sp.lifetime
            let alpha = sin(min(1.0, p) * .pi)
            ctx.saveGState()
            ctx.setAlpha(alpha * 0.85)
            if sp.isSleepZ {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11 + p * 3, weight: .bold),
                    .foregroundColor: eyeTheme.primaryColor
                ]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSAttributedString(string: "z", attributes: attrs).draw(at: sp.position)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                // Tiny glowing chartreuse 4-point star
                let r: CGFloat = 3.5 + p * 1.5
                ctx.translateBy(x: sp.position.x, y: sp.position.y)
                ctx.setFillColor(eyeTheme.primaryColor.cgColor)
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

    private static func drawPermissionPill(in ctx: CGContext, text: String) {
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

    private static func keycapLegend(_ key: PhysicalKey) -> String {
        switch key {
        case .escape: return "ESC"
        case .tab: return "⇥"
        case .capsLock: return "⇪"
        case .leftShift, .rightShift: return "⇧"
        case .leftControl, .rightControl: return "⌃"
        case .leftOption, .rightOption: return "⌥"
        case .leftCommand, .rightCommand: return "⌘"
        case .backspace: return "⌫"
        case .enter: return "↵"
        case .space: return ""
        default: return key.badgeLabel
        }
    }

    private static func quadPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
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

    /// HSV → RGB, used by the keyboard marquee for its one-hue-cycle-per-sweep backlight.
    private static func hsvColor(hue h: CGFloat, saturation s: CGFloat, value v: CGFloat) -> NSColor {
        var hue = h.truncatingRemainder(dividingBy: 1.0)
        if hue < 0 { hue += 1 }
        let c = v * s
        let x = c * (1 - abs((hue * 6.0).truncatingRemainder(dividingBy: 2.0) - 1))
        let m = v - c
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        switch Int(hue * 6.0) % 6 {
        case 0: r = c; g = x
        case 1: r = x; g = c
        case 2: g = c; b = x
        case 3: g = x; b = c
        case 4: r = x; b = c
        default: r = c; b = x
        }
        return NSColor(calibratedRed: r + m, green: g + m, blue: b + m, alpha: 1.0)
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
