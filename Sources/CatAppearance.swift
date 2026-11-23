import Foundation
import AppKit
import CoreGraphics

// MARK: - Codable Color Wrapper

struct RGBAColor: Codable, Equatable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat = 1.0

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        self.r = c.redComponent
        self.g = c.greenComponent
        self.b = c.blueComponent
        self.a = c.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }

    var cgColor: CGColor {
        nsColor.cgColor
    }

    var luminance: CGFloat {
        0.299 * r + 0.587 * g + 0.114 * b
    }

    func darkened(by amount: CGFloat) -> NSColor {
        let factor = max(0, 1.0 - amount)
        return NSColor(calibratedRed: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }

    func lightened(by amount: CGFloat) -> NSColor {
        let t = max(0, min(1, amount))
        return NSColor(
            calibratedRed: r + (1.0 - r) * t,
            green: g + (1.0 - g) * t,
            blue: b + (1.0 - b) * t,
            alpha: a
        )
    }
}

// MARK: - Fur Patterns

enum FurPattern: String, CaseIterable, Codable {
    case solid      = "纯色 (Solid)"
    case colorpoint = "重点色 / 暹罗 (Colorpoint)"
    case tuxedo     = "奶牛 / 燕尾服 (Tuxedo)"
    case tabby      = "虎斑 (Tabby)"
    case calico     = "三花 (Calico)"
    case spotted    = "斑点 / 奶牛斑 (Spotted)"

    var displayName: String {
        switch self {
        case .solid:      return L10n.tr("Solid", "纯色")
        case .colorpoint: return L10n.tr("Colorpoint / Siamese", "重点色 / 暹罗")
        case .tuxedo:     return L10n.tr("Tuxedo / Bicolor", "奶牛 / 燕尾服")
        case .tabby:      return L10n.tr("Tabby", "虎斑")
        case .calico:     return L10n.tr("Calico", "三花")
        case .spotted:    return L10n.tr("Spotted", "斑点 / 奶牛斑")
        }
    }

    /// How many coat colors this pattern uses (1, 2, or 3).
    var colorSlotCount: Int {
        switch self {
        case .solid: return 1
        case .tuxedo, .spotted: return 2
        case .colorpoint, .tabby, .calico: return 3
        }
    }

    var primaryLabel: String {
        switch self {
        case .solid:      return L10n.tr("Primary Coat", "主毛色")
        case .colorpoint: return L10n.tr("Body Base", "躯干底色")
        case .tuxedo:     return L10n.tr("Primary Coat", "主毛色")
        case .tabby:      return L10n.tr("Base Coat", "毛发底色")
        case .calico:     return L10n.tr("Base Coat (Cream/White)", "底色 (通常奶白)")
        case .spotted:    return L10n.tr("Base Coat", "毛发底色")
        }
    }

    var secondaryLabel: String {
        switch self {
        case .solid:      return L10n.tr("Secondary", "辅色")
        case .colorpoint: return L10n.tr("Points (Mask / Ears / Socks)", "重点色 (面罩/耳/袜)")
        case .tuxedo:     return L10n.tr("Bib & Mittens", "胸腹/爪子色")
        case .tabby:      return L10n.tr("Tabby Stripes", "虎斑条纹色")
        case .calico:     return L10n.tr("Patch Color 1 (e.g. Ginger)", "花斑色 1 (如橘色)")
        case .spotted:    return L10n.tr("Spot Color", "斑点色")
        }
    }

    var tertiaryLabel: String {
        switch self {
        case .colorpoint: return L10n.tr("Point Blend Halo", "过渡晕染色")
        case .tabby:      return L10n.tr("Chin & Belly", "下巴/肚皮色")
        case .calico:     return L10n.tr("Patch Color 2 (e.g. Dark)", "花斑色 2 (如深棕/黑)")
        default:          return L10n.tr("Accent Color", "点缀色")
        }
    }
}

// MARK: - Breed Presets (First-Class Priority!)

enum CatBreedPreset: String, CaseIterable, Codable {
    case classicBlack    = "经典小黑猫 (Classic Black)"
    case siamese         = "挖煤暹罗猫 (Siamese)"
    case orangeTabby     = "大橘虎斑 (Orange Tabby)"
    case silverTabby     = "美短银虎斑 (Silver Tabby)"
    case tuxedo          = "奶牛燕尾服 (Tuxedo)"
    case calico          = "三花招财猫 (Calico)"
    case ragdoll         = "长毛布偶猫 (Ragdoll)"
    case britishBlue     = "英短蓝猫 (British Blue)"
    case whitePersian    = "长毛白波斯 (White Persian)"
    case goldenMaineCoon = "金渐层缅因 (Golden Maine Coon)"

    var displayName: String {
        switch self {
        case .classicBlack:    return L10n.tr("Classic Black Cat", "经典小黑猫")
        case .siamese:         return L10n.tr("Seal-Point Siamese", "挖煤暹罗猫")
        case .orangeTabby:     return L10n.tr("Orange Tabby", "大橘虎斑")
        case .silverTabby:     return L10n.tr("Silver Tabby", "美短银虎斑")
        case .tuxedo:          return L10n.tr("Tuxedo", "奶牛燕尾服")
        case .calico:          return L10n.tr("Calico", "三花招财猫")
        case .ragdoll:         return L10n.tr("Long-Haired Ragdoll", "长毛布偶猫")
        case .britishBlue:     return L10n.tr("British Shorthair Blue", "英短蓝猫")
        case .whitePersian:    return L10n.tr("White Persian", "长毛白波斯")
        case .goldenMaineCoon: return L10n.tr("Golden Maine Coon", "金渐层缅因")
        }
    }

    var shortName: String {
        switch self {
        case .classicBlack:    return L10n.tr("Black", "小黑猫")
        case .siamese:         return L10n.tr("Siamese", "暹罗猫")
        case .orangeTabby:     return L10n.tr("Orange", "大橘")
        case .silverTabby:     return L10n.tr("Silver", "银虎斑")
        case .tuxedo:          return L10n.tr("Tuxedo", "奶牛猫")
        case .calico:          return L10n.tr("Calico", "三花猫")
        case .ragdoll:         return L10n.tr("Ragdoll", "布偶猫")
        case .britishBlue:     return L10n.tr("Brit Blue", "英短蓝")
        case .whitePersian:    return L10n.tr("Persian", "白波斯")
        case .goldenMaineCoon: return L10n.tr("Maine", "缅因猫")
        }
    }

    var appearance: CatAppearance {
        switch self {
        case .classicBlack:
            return CatAppearance(
                presetID: rawValue,
                pattern: .solid,
                furLength: 0.0,
                primaryColor:   RGBAColor(r: 0.085, g: 0.085, b: 0.095),
                secondaryColor: RGBAColor(r: 0.16,  g: 0.16,  b: 0.18),
                tertiaryColor:  RGBAColor(r: 0.24,  g: 0.24,  b: 0.26),
                eyeColor:       RGBAColor(r: 0.79,  g: 0.95,  b: 0.25)
            )
        case .siamese:
            return CatAppearance(
                presetID: rawValue,
                pattern: .colorpoint,
                furLength: 0.0,
                primaryColor:   RGBAColor(r: 0.945, g: 0.905, b: 0.835),
                secondaryColor: RGBAColor(r: 0.175, g: 0.128, b: 0.105),
                tertiaryColor:  RGBAColor(r: 0.45,  g: 0.34,  b: 0.27),
                eyeColor:       RGBAColor(r: 0.37,  g: 0.78,  b: 0.98)
            )
        case .orangeTabby:
            return CatAppearance(
                presetID: rawValue,
                pattern: .tabby,
                furLength: 0.18,
                primaryColor:   RGBAColor(r: 0.93,  g: 0.62,  b: 0.28),
                secondaryColor: RGBAColor(r: 0.72,  g: 0.36,  b: 0.11),
                tertiaryColor:  RGBAColor(r: 0.98,  g: 0.93,  b: 0.84),
                eyeColor:       RGBAColor(r: 0.95,  g: 0.76,  b: 0.20)
            )
        case .silverTabby:
            return CatAppearance(
                presetID: rawValue,
                pattern: .tabby,
                furLength: 0.12,
                primaryColor:   RGBAColor(r: 0.76,  g: 0.78,  b: 0.80),
                secondaryColor: RGBAColor(r: 0.24,  g: 0.26,  b: 0.29),
                tertiaryColor:  RGBAColor(r: 0.95,  g: 0.96,  b: 0.97),
                eyeColor:       RGBAColor(r: 0.48,  g: 0.84,  b: 0.44)
            )
        case .tuxedo:
            return CatAppearance(
                presetID: rawValue,
                pattern: .tuxedo,
                furLength: 0.08,
                primaryColor:   RGBAColor(r: 0.10,  g: 0.105, b: 0.12),
                secondaryColor: RGBAColor(r: 0.96,  g: 0.965, b: 0.97),
                tertiaryColor:  RGBAColor(r: 0.88,  g: 0.89,  b: 0.91),
                eyeColor:       RGBAColor(r: 0.95,  g: 0.78,  b: 0.24)
            )
        case .calico:
            return CatAppearance(
                presetID: rawValue,
                pattern: .calico,
                furLength: 0.16,
                primaryColor:   RGBAColor(r: 0.97,  g: 0.95,  b: 0.91),
                secondaryColor: RGBAColor(r: 0.90,  g: 0.50,  b: 0.18),
                tertiaryColor:  RGBAColor(r: 0.16,  g: 0.14,  b: 0.14),
                eyeColor:       RGBAColor(r: 0.93,  g: 0.72,  b: 0.22)
            )
        case .ragdoll:
            return CatAppearance(
                presetID: rawValue,
                pattern: .colorpoint,
                furLength: 0.95,
                primaryColor:   RGBAColor(r: 0.97,  g: 0.955, b: 0.93),
                secondaryColor: RGBAColor(r: 0.36,  g: 0.31,  b: 0.28),
                tertiaryColor:  RGBAColor(r: 0.64,  g: 0.57,  b: 0.52),
                eyeColor:       RGBAColor(r: 0.32,  g: 0.74,  b: 0.98)
            )
        case .britishBlue:
            return CatAppearance(
                presetID: rawValue,
                pattern: .solid,
                furLength: 0.32,
                primaryColor:   RGBAColor(r: 0.44,  g: 0.48,  b: 0.54),
                secondaryColor: RGBAColor(r: 0.32,  g: 0.36,  b: 0.42),
                tertiaryColor:  RGBAColor(r: 0.60,  g: 0.64,  b: 0.70),
                eyeColor:       RGBAColor(r: 0.96,  g: 0.64,  b: 0.18)
            )
        case .whitePersian:
            return CatAppearance(
                presetID: rawValue,
                pattern: .solid,
                furLength: 1.0,
                primaryColor:   RGBAColor(r: 0.975, g: 0.97,  b: 0.96),
                secondaryColor: RGBAColor(r: 0.90,  g: 0.89,  b: 0.87),
                tertiaryColor:  RGBAColor(r: 0.99,  g: 0.99,  b: 0.99),
                eyeColor:       RGBAColor(r: 0.45,  g: 0.88,  b: 0.98)
            )
        case .goldenMaineCoon:
            return CatAppearance(
                presetID: rawValue,
                pattern: .tabby,
                furLength: 0.92,
                primaryColor:   RGBAColor(r: 0.87,  g: 0.68,  b: 0.42),
                secondaryColor: RGBAColor(r: 0.48,  g: 0.30,  b: 0.15),
                tertiaryColor:  RGBAColor(r: 0.97,  g: 0.93,  b: 0.85),
                eyeColor:       RGBAColor(r: 0.82,  g: 0.86,  b: 0.28)
            )
        }
    }
}

// MARK: - Complete Custom Cat Appearance Model

struct CatAppearance: Codable, Equatable {
    var presetID: String?          // nil if user customized colors/pattern/fur
    var pattern: FurPattern
    var furLength: CGFloat         // 0.0 (sleek short fur) ... 1.0 (plush long fur with sway physics!)
    var primaryColor: RGBAColor
    var secondaryColor: RGBAColor
    var tertiaryColor: RGBAColor
    var eyeColor: RGBAColor

    /// True if the main coat is dark enough to benefit from light separation contour strokes.
    var isDarkCoat: Bool {
        primaryColor.luminance < 0.28
    }

    /// Face-area color (used for eyelids & blinking so lids blend naturally into the face!).
    var faceEyelidColor: NSColor {
        switch pattern {
        case .colorpoint:
            return secondaryColor.nsColor
        default:
            return primaryColor.nsColor
        }
    }

    /// Crisp silhouette outline color (only needed for medium/light coats; dark coats stay sleek matte).
    var silhouetteOutlineColor: NSColor? {
        if isDarkCoat { return nil }
        return primaryColor.darkened(by: 0.58).withAlphaComponent(0.84)
    }

    /// Paw/limb separation crease color (auto-contrasts against primary coat).
    var limbSeparationColor: NSColor {
        if isDarkCoat {
            return NSColor(calibratedRed: 0.82, green: 0.92, blue: 0.89, alpha: 0.78)
        }
        return primaryColor.darkened(by: 0.55).withAlphaComponent(0.72)
    }

    /// Whisker color (auto-contrasts against face!).
    var whiskerColor: NSColor {
        let faceLum = (pattern == .colorpoint) ? secondaryColor.luminance : primaryColor.luminance
        if faceLum < 0.35 {
            return NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.92, alpha: 0.72)
        }
        return primaryColor.darkened(by: 0.52).withAlphaComponent(0.68)
    }

    /// Sleeping closed-eye line color (auto-contrasts against face!).
    var sleepingEyeColor: NSColor {
        let faceLum = (pattern == .colorpoint) ? secondaryColor.luminance : primaryColor.luminance
        if faceLum < 0.35 {
            return NSColor(calibratedRed: 0.84, green: 0.93, blue: 0.90, alpha: 0.86)
        }
        return primaryColor.darkened(by: 0.65).withAlphaComponent(0.82)
    }

    /// Eye glow color for keyboard backlighting & sparkles.
    var eyeGlowColor: NSColor {
        eyeColor.nsColor.withAlphaComponent(0.85)
    }
}
