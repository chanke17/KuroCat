import Foundation
import CoreGraphics
import AppKit

/// Dedicated vector rendering pipeline for medium-to-long-haired fluffy cats
/// (Ragdoll, Persian, Maine Coon, etc.) with unified continuous fluffy silhouettes,
/// feathered plume tails, inner ear furnishings, layered chest manes, and spring-physics fur sway.
enum LongFurRenderer {

    // MARK: - 1. Continuous Feathered Plume Tail (No Stamped Circles!)

    static func drawTail(
        in ctx: CGContext,
        seatX: CGFloat,
        seatY: CGFloat,
        physics: CatPhysics,
        appearance: CatAppearance
    ) {
        let p = physics.tailPhase
        let hunt = max(0, min(1, physics.huntIntensity.value))
        let sleepCalm = 1.0 - physics.sleepiness * 0.65
        let fluff = max(0.3, min(1.0, appearance.furLength))
        let swayX = physics.furSwayX.value
        let swayY = physics.furSwayY.value

        let wag1 = sin(p) * (7.5 + hunt * 5.0) * sleepCalm
        let wag2 = cos(p * 1.3) * (5.5 + hunt * 4.0) * sleepCalm
        let huntDrop = hunt * 13.0 + physics.sleepiness * 18.0
        let sleepCurlIn = physics.sleepiness * 15.0

        // Tail spine cubic Bezier
        let root = CGPoint(x: seatX + 33, y: seatY - 6)
        let c1   = CGPoint(x: seatX + 64 - sleepCurlIn * 0.3 + swayX * 0.35, y: seatY + 4 + wag1 * 0.35 + huntDrop * 0.4 + swayY * 0.3)
        let c2   = CGPoint(x: seatX + 68 - sleepCurlIn * 0.7 + wag2 * 0.45 + swayX * 0.9,  y: seatY - 28 + wag1 * 0.7 + huntDrop + swayY * 0.7)
        let tip  = CGPoint(x: seatX + 95 - sleepCurlIn + wag2 * 0.55 + swayX * 1.4,        y: seatY - 34 + wag1 * 0.85 + huntDrop + swayY * 1.1)

        // Build ONE continuous organic plume polygon with scalloped fur locks along the trailing edge
        let steps = 28
        var upperEdge: [CGPoint] = []
        var lowerEdge: [CGPoint] = []

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let pt = cubicPoint(root, c1, c2, tip, t: t)
            let tan = cubicTangent(root, c1, c2, tip, t: t)
            let len = max(0.001, hypot(tan.x, tan.y))
            // Unit normal pointing "upward/left" relative to tail direction
            let nx = -tan.y / len
            let ny = tan.x / len

            // Plume width envelope: slender root -> lush billowing mid-to-tip -> tapered wispy tip
            let envelope = sin(pow(t, 0.78) * .pi)
            let baseHalfW: CGFloat = (4.5 + 10.5 * fluff * envelope) * (1.0 - 0.15 * t)

            // Soft undulating fur locks along the trailing/outer plume edge
            let lockWaveUpper = max(0, sin(t * .pi * 4.5)) * (2.2 * fluff * envelope)
            let lockWaveLower = max(0, sin(t * .pi * 5.5 + 0.8)) * (4.2 * fluff * envelope)

            // Physics gravity + sway lag on the longer underside plume hairs
            let hairLagX = swayX * (0.25 + t * 0.75) * fluff
            let hairLagY = (2.8 * fluff * envelope) + swayY * (0.25 + t * 0.65) * fluff

            let upHalf = baseHalfW * 0.78 + lockWaveUpper
            let dnHalf = baseHalfW * 1.15 + lockWaveLower

            upperEdge.append(CGPoint(
                x: pt.x - nx * upHalf + hairLagX * 0.35,
                y: pt.y - ny * upHalf + hairLagY * 0.25
            ))
            lowerEdge.append(CGPoint(
                x: pt.x + nx * dnHalf + hairLagX,
                y: pt.y + ny * dnHalf + hairLagY
            ))
        }

        let plumePath = CGMutablePath()
        plumePath.move(to: upperEdge[0])
        for i in 1..<upperEdge.count {
            let prev = upperEdge[i - 1]
            let curr = upperEdge[i]
            let mid = CGPoint(x: (prev.x + curr.x) * 0.5, y: (prev.y + curr.y) * 0.5)
            plumePath.addQuadCurve(to: mid, control: prev)
        }
        // Flowing wispy tip
        let wispyTip = CGPoint(x: tip.x + 5.5 * fluff + swayX * 0.6, y: tip.y - 2.0 * fluff + swayY * 0.5)
        plumePath.addQuadCurve(to: wispyTip, control: upperEdge.last ?? tip)
        plumePath.addQuadCurve(to: lowerEdge.last ?? tip, control: CGPoint(x: wispyTip.x - 1.5, y: wispyTip.y + 4.0))

        for i in stride(from: lowerEdge.count - 2, through: 0, by: -1) {
            let prev = lowerEdge[i + 1]
            let curr = lowerEdge[i]
            let mid = CGPoint(x: (prev.x + curr.x) * 0.5, y: (prev.y + curr.y) * 0.5)
            plumePath.addQuadCurve(to: mid, control: prev)
        }
        plumePath.closeSubpath()

        let baseColor: NSColor
        switch appearance.pattern {
        case .colorpoint: baseColor = appearance.secondaryColor.nsColor
        case .calico:     baseColor = appearance.tertiaryColor.nsColor
        default:          baseColor = appearance.primaryColor.nsColor
        }

        ctx.saveGState()
        ctx.saveGState()
        ctx.addPath(plumePath)
        ctx.clip()

        // Volumetric soft gradient along the fluffy plume
        let cs = CGColorSpaceCreateDeviceRGB()
        let hiCol = appearance.isDarkCoat ? baseColor.blended(withFraction: 0.10, of: .white) ?? baseColor : baseColor.blended(withFraction: 0.16, of: .white) ?? baseColor
        let loCol = baseColor.blended(withFraction: 0.14, of: .black) ?? baseColor
        if let grad = CGGradient(colorsSpace: cs, colors: [hiCol.cgColor, baseColor.cgColor, loCol.cgColor] as CFArray, locations: [0.0, 0.55, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: root.x, y: tip.y - 18),
                end: CGPoint(x: tip.x, y: root.y + 18),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Clipped pattern markings inside the plume (Tabby rings, Calico patch, Tuxedo white plume tip!)
        if appearance.pattern == .tabby || appearance.pattern == .spotted {
            ctx.setStrokeColor(appearance.secondaryColor.nsColor.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(5.5)
            ctx.setLineCap(.round)
            for t in [0.25, 0.48, 0.70, 0.88] as [CGFloat] {
                let pt = cubicPoint(root, c1, c2, tip, t: t)
                let tan = cubicTangent(root, c1, c2, tip, t: t)
                let len = max(0.001, hypot(tan.x, tan.y))
                let nx = -tan.y / len, ny = tan.x / len
                ctx.move(to: CGPoint(x: pt.x - nx * 18, y: pt.y - ny * 18))
                ctx.addLine(to: CGPoint(x: pt.x + nx * 18, y: pt.y + ny * 18))
                ctx.strokePath()
            }
        } else if appearance.pattern == .calico {
            let pt = cubicPoint(root, c1, c2, tip, t: 0.54)
            ctx.setFillColor(appearance.secondaryColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - 14, y: pt.y - 14, width: 28, height: 28))
        } else if appearance.pattern == .tuxedo {
            ctx.setFillColor(appearance.secondaryColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x - 12, y: tip.y - 12, width: 28, height: 26))
        }

        // Delicate internal plume wisp strokes
        let wispCol = appearance.isDarkCoat
            ? CatRenderer.contourMint.withAlphaComponent(0.24)
            : baseColor.blended(withFraction: 0.42, of: .black)?.withAlphaComponent(0.22) ?? NSColor.gray.withAlphaComponent(0.2)
        ctx.setStrokeColor(wispCol.cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)
        let wStart = cubicPoint(root, c1, c2, tip, t: 0.25)
        let wMid   = cubicPoint(root, c1, c2, tip, t: 0.58)
        let wEnd   = cubicPoint(root, c1, c2, tip, t: 0.86)
        ctx.move(to: wStart)
        ctx.addQuadCurve(to: wEnd, control: CGPoint(x: wMid.x + 2, y: wMid.y + 4))
        ctx.strokePath()

        ctx.restoreGState() // end plume clip

        // Crisp continuous outer outline
        if let outline = appearance.silhouetteOutlineColor {
            ctx.setStrokeColor(outline.withAlphaComponent(0.82).cgColor)
            ctx.setLineWidth(1.4)
            ctx.setLineJoin(.round)
            ctx.addPath(plumePath)
            ctx.strokePath()
        } else {
            ctx.setStrokeColor(CatRenderer.contourMint.withAlphaComponent(0.26).cgColor)
            ctx.setLineWidth(1.0)
            ctx.addPath(plumePath)
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    // MARK: - 2. Plush Ears with Lynx Tips & Inner Ear Furnishings

    static func drawEarsLayer(
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

        drawPlushEar(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: twitch, physics: physics, appearance: appearance)
        drawPlushEar(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: -twitch, physics: physics, appearance: appearance)

        ctx.restoreGState()
    }

    private static func drawPlushEar(
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
        let fluff = max(0.3, min(1.0, appearance.furLength))
        let swayX = physics.furSwayX.value * 0.35
        let swayY = physics.furSwayY.value * 0.25

        let tipDx = sin(foldAngle) * (33.0 + fluff * 3.0)
        let tipDy = -cos(foldAngle) * (33.0 + fluff * 3.0)

        let innerBase = CatRenderer.projectHead3D(x: sign * 8.5, y: -16.0, z: 0.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let outerBase = CatRenderer.projectHead3D(x: sign * 36.5, y: -4.0, z: -2.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let tip3D     = CatRenderer.projectHead3D(x: sign * 24.5 + tipDx, y: -20.0 + tipDy, z: -3.0, yawRad: yawRad, pitchRad: pitchRad).pt

        // Soft curved feline ear with integrated gentle lynx tip
        let lynxTip = CGPoint(x: tip3D.x + sign * (1.8 * fluff) + swayX, y: tip3D.y - (5.0 * fluff) + swayY)
        let ear = CGMutablePath()
        ear.move(to: innerBase)
        ear.addQuadCurve(
            to: lynxTip,
            control: CGPoint(x: (innerBase.x + tip3D.x) * 0.5 - sign * 3.0, y: (innerBase.y + tip3D.y) * 0.5 - 3.5)
        )
        ear.addQuadCurve(
            to: outerBase,
            control: CGPoint(x: (outerBase.x + tip3D.x) * 0.5 + sign * 4.5, y: (outerBase.y + tip3D.y) * 0.5 - 1.5)
        )
        ear.closeSubpath()

        let earColor: NSColor
        switch appearance.pattern {
        case .colorpoint: earColor = appearance.secondaryColor.nsColor
        case .calico:     earColor = isLeft ? appearance.secondaryColor.nsColor : appearance.tertiaryColor.nsColor
        default:          earColor = appearance.primaryColor.nsColor
        }

        ctx.saveGState()
        ctx.setFillColor(earColor.cgColor)
        ctx.addPath(ear)
        ctx.fillPath()
        if let outline = appearance.silhouetteOutlineColor {
            ctx.setStrokeColor(outline.cgColor)
            ctx.setLineWidth(1.35)
            ctx.setLineJoin(.round)
            ctx.addPath(ear)
            ctx.strokePath()
        }

        // Delicate inner-ear furnishings (wispy pale fur tufts inside each ear, classic Ragdoll/Maine Coon!)
        let furnBase = CatRenderer.projectHead3D(x: sign * 17.5, y: -18.5, z: 3.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let furnCol = appearance.isDarkCoat
            ? NSColor(calibratedWhite: 0.85, alpha: 0.28 * fluff)
            : appearance.primaryColor.lightened(by: 0.45).withAlphaComponent(0.75 * fluff)
        ctx.setStrokeColor(furnCol.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        for i in 0..<2 {
            let offset = CGFloat(i) * 4.0
            ctx.move(to: CGPoint(x: furnBase.x, y: furnBase.y + offset))
            ctx.addQuadCurve(
                to: CGPoint(x: furnBase.x + sign * (10.5 * fluff) + swayX * 0.4, y: furnBase.y - 6.0 + offset + swayY * 0.3),
                control: CGPoint(x: furnBase.x + sign * (5.5 * fluff), y: furnBase.y - 4.5 + offset)
            )
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - 3. Unified Continuous Fluffy Silhouette + Layered Mane + Fur Patterns

    static func drawUnifiedSilhouette(
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
        let fluff = max(0.3, min(1.0, appearance.furLength))
        let swayX = physics.furSwayX.value
        let swayY = physics.furSwayY.value

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
        let f = fluff // 0.3 .. 1.0

        // Build ONE single continuous, seamless fluffy silhouette path!
        // Every fur tuft is integrated directly into the closed contour — ZERO glued-on side fins!
        let path = CGMutablePath()

        // Crown with soft central head cowlick/floof
        let crownL = H(-12 + cheekShift * 0.2, -31.0 - f * 2.5 + crownDrop)
        let crownTip = H(cheekShift * 0.2 + swayX * 0.35, -34.5 - f * 4.5 + crownDrop + swayY * 0.25)
        let crownR = H(12 + cheekShift * 0.2, -31.0 - f * 2.5 + crownDrop)

        // Right cheek: plush wide multi-lock mane curving gently outward & downward
        let rTemple   = H(38.0 + f * 3.0 + cheekShift * 0.4, -14.0)
        let rCheek1   = H(47.5 + f * 9.5 + cheekShift * 0.4 + swayX * 0.55, 2.0 + swayY * 0.45)
        let rCheekIn1 = H(43.0 + f * 5.5 + cheekShift * 0.35 + swayX * 0.35, 9.5 + swayY * 0.35)
        let rCheek2   = H(49.0 + f * 11.0 + cheekShift * 0.35 + swayX * 0.80, 18.0 + f * 3.5 + swayY * 0.65)
        let rNeckIn   = H(41.0 + f * 5.0 + cheekShift * 0.25 + swayX * 0.45, 28.0 + f * 2.0)

        // Right billowing shoulder & plush hip fur locks
        let rFlank1   = B(53.0 + f * 8.5 + swayX * 0.55, -52.0 + breath * 0.4 + swayY * 0.45)
        let rFlankIn1 = B(50.5 + f * 5.5 + swayX * 0.35, -36.0 + breath * 0.3)
        let rHipOut   = B(55.0 + f * 8.0 + swayX * 0.45, -14.0 + swayY * 0.35)
        let rBot      = B(26.0 + f * 3.0, 12.5)
        let lBot      = B(-26.0 - f * 3.0, 12.5)

        // Left plush hip & billowing shoulder fur locks (mirrored)
        let lHipOut   = B(-55.0 - f * 8.0 + swayX * 0.45, -14.0 + swayY * 0.35)
        let lFlankIn1 = B(-50.5 - f * 5.5 + swayX * 0.35, -36.0 + breath * 0.3)
        let lFlank1   = B(-53.0 - f * 8.5 + swayX * 0.55, -52.0 + breath * 0.4 + swayY * 0.45)

        // Left cheek: plush wide multi-lock mane
        let lNeckIn   = H(-41.0 - f * 5.0 + cheekShift * 0.25 + swayX * 0.45, 28.0 + f * 2.0)
        let lCheek2   = H(-49.0 - f * 11.0 + cheekShift * 0.35 + swayX * 0.80, 18.0 + f * 3.5 + swayY * 0.65)
        let lCheekIn1 = H(-43.0 - f * 5.5 + cheekShift * 0.35 + swayX * 0.35, 9.5 + swayY * 0.35)
        let lCheek1   = H(-47.5 - f * 9.5 + cheekShift * 0.4 + swayX * 0.55, 2.0 + swayY * 0.45)
        let lTemple   = H(-38.0 - f * 3.0 + cheekShift * 0.4, -14.0)

        path.move(to: crownL)
        // Soft crown tuft
        path.addQuadCurve(to: crownTip, control: H(-4 + cheekShift * 0.2, -33.5 - f * 3.5 + crownDrop))
        path.addQuadCurve(to: crownR,   control: H(5 + cheekShift * 0.2, -33.5 - f * 3.5 + crownDrop))
        // Right forehead -> cheek locks
        path.addQuadCurve(to: rTemple,   control: H(29 + f * 2.0 + cheekShift * 0.3, -29.0 + crownDrop))
        path.addQuadCurve(to: rCheek1,   control: H(45.5 + f * 7.5 + cheekShift * 0.4, -7.0))
        path.addQuadCurve(to: rCheekIn1, control: H(46.5 + f * 7.5 + cheekShift * 0.4, 7.0))
        path.addQuadCurve(to: rCheek2,   control: H(49.5 + f * 10.0 + cheekShift * 0.35, 13.0))
        path.addQuadCurve(to: rNeckIn,   control: H(46.5 + f * 8.0 + cheekShift * 0.3, 25.0 + f * 2.0))
        // Right shoulder -> flank -> hip -> bottom
        path.addQuadCurve(to: rFlank1,   control: B(52.0 + f * 7.5, -62.0))
        path.addQuadCurve(to: rFlankIn1, control: B(53.0 + f * 7.5, -42.0))
        path.addQuadCurve(to: rHipOut,   control: B(55.5 + f * 8.0, -25.0))
        path.addCurve(to: rBot, control1: B(52.0 + f * 6.5, 6.0), control2: B(40.0 + f * 4.5, 12.5))
        path.addLine(to: lBot)
        // Left bottom -> hip -> flank -> shoulder
        path.addCurve(to: lHipOut, control1: B(-40.0 - f * 4.5, 12.5), control2: B(-52.0 - f * 6.5, 6.0))
        path.addQuadCurve(to: lFlankIn1, control: B(-55.5 - f * 8.0, -25.0))
        path.addQuadCurve(to: lFlank1,   control: B(-53.0 - f * 7.5, -42.0))
        path.addQuadCurve(to: lNeckIn,   control: B(-52.0 - f * 7.5, -62.0))
        // Left cheek locks -> forehead -> crown
        path.addQuadCurve(to: lCheek2,   control: H(-46.5 - f * 8.0 + cheekShift * 0.3, 25.0 + f * 2.0))
        path.addQuadCurve(to: lCheekIn1, control: H(-49.5 - f * 10.0 + cheekShift * 0.35, 13.0))
        path.addQuadCurve(to: lCheek1,   control: H(-46.5 - f * 7.5 + cheekShift * 0.4, 7.0))
        path.addQuadCurve(to: lTemple,   control: H(-45.5 - f * 7.5 + cheekShift * 0.4, -7.0))
        path.addQuadCurve(to: crownL,    control: H(-29 - f * 2.0 + cheekShift * 0.3, -29.0 + crownDrop))
        path.closeSubpath()

        // 1. Base coat fill + clipped fur patterns
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        let cs = CGColorSpaceCreateDeviceRGB()
        if appearance.isDarkCoat {
            // Subtle plush velvet radial highlight on dark long-haired cats so they feel soft & 3D
            let topC = appearance.primaryColor.lightened(by: 0.05)
            let botC = appearance.primaryColor.nsColor
            if let grad = CGGradient(colorsSpace: cs, colors: [topC.cgColor, botC.cgColor] as CFArray, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: seatX, y: headCenter.y - 36),
                    end: CGPoint(x: seatX, y: seatY + 18),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        } else {
            let topCol = appearance.primaryColor.lightened(by: 0.04)
            let botCol = appearance.primaryColor.darkened(by: 0.10)
            if let grad = CGGradient(colorsSpace: cs, colors: [topCol.cgColor, botCol.cgColor] as CFArray, locations: [0.1, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: seatX, y: headCenter.y - 36),
                    end: CGPoint(x: seatX, y: seatY + 18),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        }

        // Render clipped fur pattern markings (reusing the same rich 2.5D pattern geometry!)
        CatRenderer.drawClippedFurPattern(
            in: ctx,
            headCenter: headCenter,
            hTilt: hTilt,
            yaw: yaw,
            pitch: pitch,
            B: B,
            H: H,
            appearance: appearance
        )

        // 2. Lush Layered Chest Mane / Lion Ruff (soft gradient fading seamlessly from upper neck — NO hard top line!)
        drawLayeredChestMane(
            in: ctx,
            seatX: seatX,
            headCenter: headCenter,
            breath: breath,
            tilt: bTilt * 0.65 + hTilt * 0.35,
            fluff: f,
            swayX: swayX,
            swayY: swayY,
            appearance: appearance
        )

        // 3. Delicate internal tactile fur-tuft wisp accents along cheeks & hips
        let wispCol = appearance.isDarkCoat
            ? CatRenderer.contourMint.withAlphaComponent(0.22 * f)
            : appearance.primaryColor.darkened(by: 0.36).withAlphaComponent(0.28 * f)
        ctx.setStrokeColor(wispCol.cgColor)
        ctx.setLineWidth(1.1)
        ctx.setLineCap(.round)
        for sign in [-1.0, 1.0] as [CGFloat] {
            let ch0 = H(sign * 34.0, 12.0)
            let ch1 = H(sign * (42.0 + f * 5.0) + swayX * 0.4, 21.0 + swayY * 0.35)
            ctx.move(to: ch0)
            ctx.addQuadCurve(to: ch1, control: H(sign * 39.0, 15.0))

            let hp0 = B(sign * 38.0, -34.0)
            let hp1 = B(sign * (45.0 + f * 4.0) + swayX * 0.3, -20.0 + swayY * 0.25)
            ctx.move(to: hp0)
            ctx.addQuadCurve(to: hp1, control: B(sign * 43.0, -28.0))
        }
        ctx.strokePath()

        ctx.restoreGState() // end silhouette clip

        // 4. Single continuous crisp outer outline around the ENTIRE fluffy silhouette
        if let outline = appearance.silhouetteOutlineColor {
            ctx.saveGState()
            ctx.setStrokeColor(outline.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineJoin(.round)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // 5. Plush tucked hind paws peeking softly along bottom edge
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
        ctx.fillEllipse(in: CGRect(x: -36, y: 2.5, width: 19, height: 12))
        if physics.hindFootActive.value < 0.35 {
            ctx.fillEllipse(in: CGRect(x: 17, y: 2.5, width: 19, height: 12))
        }
        let rimColor = appearance.limbSeparationColor.withAlphaComponent(0.55)
        ctx.setStrokeColor(rimColor.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: -26.5, y: 8.5), radius: 8.0, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
        ctx.strokePath()
        if physics.hindFootActive.value < 0.35 {
            ctx.addArc(center: CGPoint(x: 26.5, y: 8.5), radius: 8.0, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Lush, soft-fading layered chest mane (Ragdoll / Persian / Maine Coon ruff) with per-lock sway!
    private static func drawLayeredChestMane(
        in ctx: CGContext,
        seatX: CGFloat,
        headCenter: CGPoint,
        breath: CGFloat,
        tilt: CGFloat,
        fluff: CGFloat,
        swayX: CGFloat,
        swayY: CGFloat,
        appearance: CatAppearance
    ) {
        let maneX = seatX * 0.45 + headCenter.x * 0.55
        let maneY = headCenter.y + 34.0 + breath * 0.45

        let maneCol: NSColor
        switch appearance.pattern {
        case .tuxedo: maneCol = appearance.secondaryColor.nsColor
        case .tabby:  maneCol = appearance.tertiaryColor.nsColor
        default:
            maneCol = appearance.isDarkCoat
                ? appearance.primaryColor.lightened(by: 0.08)
                : appearance.primaryColor.lightened(by: 0.22)
        }

        ctx.saveGState()
        ctx.translateBy(x: maneX, y: maneY)
        ctx.rotate(by: tilt)

        let w: CGFloat = 26.0 + fluff * 14.0
        let h: CGFloat = 15.0 + fluff * 18.0

        // Multi-lock flowing crescent mane path
        let mane = CGMutablePath()
        mane.move(to: CGPoint(x: -w, y: -12.0))
        mane.addQuadCurve(to: CGPoint(x: -w * 0.72 + swayX * 0.4, y: h * 0.55 + swayY * 0.4), control: CGPoint(x: -w * 0.96, y: h * 0.25))
        mane.addQuadCurve(to: CGPoint(x: -w * 0.48 + swayX * 0.5, y: h * 0.42 + swayY * 0.35), control: CGPoint(x: -w * 0.62, y: h * 0.58))
        mane.addQuadCurve(to: CGPoint(x: -w * 0.32 + swayX * 0.65, y: h * 0.88 + swayY * 0.65), control: CGPoint(x: -w * 0.44, y: h * 0.72))
        mane.addQuadCurve(to: CGPoint(x: -w * 0.14 + swayX * 0.6, y: h * 0.68 + swayY * 0.55), control: CGPoint(x: -w * 0.22, y: h * 0.85))
        mane.addQuadCurve(to: CGPoint(x: swayX * 0.85, y: h + swayY * 0.85), control: CGPoint(x: -w * 0.08 + swayX * 0.7, y: h * 0.96))
        mane.addQuadCurve(to: CGPoint(x: w * 0.14 + swayX * 0.6, y: h * 0.68 + swayY * 0.55), control: CGPoint(x: w * 0.08 + swayX * 0.7, y: h * 0.96))
        mane.addQuadCurve(to: CGPoint(x: w * 0.32 + swayX * 0.65, y: h * 0.88 + swayY * 0.65), control: CGPoint(x: w * 0.22, y: h * 0.85))
        mane.addQuadCurve(to: CGPoint(x: w * 0.48 + swayX * 0.5, y: h * 0.42 + swayY * 0.35), control: CGPoint(x: w * 0.44, y: h * 0.72))
        mane.addQuadCurve(to: CGPoint(x: w * 0.72 + swayX * 0.4, y: h * 0.55 + swayY * 0.4), control: CGPoint(x: w * 0.62, y: h * 0.58))
        mane.addQuadCurve(to: CGPoint(x: w, y: -12.0), control: CGPoint(x: w * 0.96, y: h * 0.25))
        mane.closeSubpath()

        // Vertical fade gradient: 0% alpha at top (melts invisibly into neck!) -> lush soft fur at tips!
        ctx.saveGState()
        ctx.addPath(mane)
        ctx.clip()
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [
            maneCol.withAlphaComponent(0.0).cgColor,
            maneCol.withAlphaComponent(0.88).cgColor,
            maneCol.cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 0.38, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: -10.0),
                end: CGPoint(x: 0, y: h + 2.0),
                options: [.drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        // Subtle soft shadow contour ONLY under the lower swaying mane tips
        let tipShadow = appearance.isDarkCoat
            ? CatRenderer.contourMint.withAlphaComponent(0.26 * fluff)
            : appearance.primaryColor.darkened(by: 0.42).withAlphaComponent(0.38 * fluff)
        ctx.setStrokeColor(tipShadow.cgColor)
        ctx.setLineWidth(1.1)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: -w * 0.72 + swayX * 0.4, y: h * 0.55 + swayY * 0.4))
        ctx.addQuadCurve(to: CGPoint(x: -w * 0.32 + swayX * 0.65, y: h * 0.88 + swayY * 0.65), control: CGPoint(x: -w * 0.50, y: h * 0.55))
        ctx.addQuadCurve(to: CGPoint(x: swayX * 0.85, y: h + swayY * 0.85), control: CGPoint(x: -w * 0.14 + swayX * 0.65, y: h * 0.72))
        ctx.addQuadCurve(to: CGPoint(x: w * 0.32 + swayX * 0.65, y: h * 0.88 + swayY * 0.65), control: CGPoint(x: w * 0.14 + swayX * 0.65, y: h * 0.72))
        ctx.addQuadCurve(to: CGPoint(x: w * 0.72 + swayX * 0.4, y: h * 0.55 + swayY * 0.4), control: CGPoint(x: w * 0.50, y: h * 0.55))
        ctx.strokePath()

        ctx.restoreGState()
    }

    // MARK: - Bezier Helpers

    private static func cubicPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t
        return CGPoint(
            x: mt2 * mt * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t2 * t * p3.x,
            y: mt2 * mt * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t2 * t * p3.y
        )
    }

    private static func cubicTangent(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: 3 * mt * mt * (p1.x - p0.x) + 6 * mt * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x),
            y: 3 * mt * mt * (p1.y - p0.y) + 6 * mt * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
        )
    }
}
