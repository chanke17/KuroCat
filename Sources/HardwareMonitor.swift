import Foundation
import AppKit
import IOKit
import IOKit.hid

// MARK: - Apple Laptop Enclosure Colors & Desk Setup Modes

enum MacBookColor: String, CaseIterable {
    // MacBook Pro & MacBook Air
    case spaceBlack
    case midnight
    case spaceGray
    case silver
    case starlight
    case skyBlue
    // MacBook Neo (with color-coordinated keycaps!)
    case neoBlush
    case neoCitrus
    case neoIndigo
    // iMac 24-inch
    case imacBlue
    case imacGreen
    case imacPink
    case imacYellow
    case imacOrange
    case imacPurple

    var displayName: String {
        switch self {
        case .spaceBlack: return L10n.tr("Space Black", "深空黑色")
        case .midnight:   return L10n.tr("Midnight", "午夜色")
        case .spaceGray:  return L10n.tr("Space Gray", "深空灰色")
        case .silver:     return L10n.tr("Silver", "银色")
        case .starlight:  return L10n.tr("Starlight", "星光色")
        case .skyBlue:    return L10n.tr("Sky Blue", "天蓝色")
        case .neoBlush:   return L10n.tr("MacBook Neo · Blush", "MacBook Neo · 桃粉色")
        case .neoCitrus:  return L10n.tr("MacBook Neo · Citrus", "MacBook Neo · 柑橘黄")
        case .neoIndigo:  return L10n.tr("MacBook Neo · Indigo", "MacBook Neo · 靛蓝色")
        case .imacBlue:   return L10n.tr("iMac · Blue", "iMac · 蓝色")
        case .imacGreen:  return L10n.tr("iMac · Green", "iMac · 绿色")
        case .imacPink:   return L10n.tr("iMac · Pink", "iMac · 粉色")
        case .imacYellow: return L10n.tr("iMac · Yellow", "iMac · 黄色")
        case .imacOrange: return L10n.tr("iMac · Orange", "iMac · 橙色")
        case .imacPurple: return L10n.tr("iMac · Purple", "iMac · 紫色")
        }
    }

    struct Palette {
        let deckTop: NSColor        // C-side anodized aluminum surface (light highlight)
        let deckBottom: NSColor     // C-side anodized aluminum surface (lower tone)
        let chassisSide: NSColor    // 3D front/bottom machined lip
        let borderEdge: NSColor     // Crisp chamfered edge stroke
        let keyWell: NSColor        // Recessed black keyboard well
        let keycap: NSColor         // Flat black MacBook scissor keycap
        let keycapBorder: NSColor   // Subtle keycap separation
        let trackpadFill: NSColor   // Force Touch glass trackpad
        let trackpadBorder: NSColor // Trackpad recessed border
        let hingeColor: NSColor     // Black clutch barrel hinge
        let lidTint: NSColor        // Translucent A/B lid glass tint
        let lidBorder: NSColor      // Translucent A/B lid metallic rim
        let logoColor: NSColor      // Subtle translucent Apple silhouette on A-side
    }

    var palette: Palette {
        switch self {
        case .spaceBlack:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.21, green: 0.215, blue: 0.23, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.145, green: 0.15, blue: 0.165, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.095, green: 0.10, blue: 0.11, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.34, green: 0.35, blue: 0.38, alpha: 0.90),
                keyWell:        NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.11, green: 0.115, blue: 0.125, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.23, alpha: 0.75),
                trackpadFill:   NSColor(calibratedRed: 0.175, green: 0.18, blue: 0.195, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.08, green: 0.085, blue: 0.095, alpha: 0.85),
                hingeColor:     NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 0.11),
                lidBorder:      NSColor(calibratedRed: 0.42, green: 0.44, blue: 0.48, alpha: 0.50),
                logoColor:      NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.78, alpha: 0.22)
            )
        case .midnight:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.17, green: 0.205, blue: 0.275, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.115, green: 0.145, blue: 0.205, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.32, green: 0.38, blue: 0.48, alpha: 0.90),
                keyWell:        NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.14, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.19, green: 0.22, blue: 0.27, alpha: 0.75),
                trackpadFill:   NSColor(calibratedRed: 0.145, green: 0.175, blue: 0.235, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 0.85),
                hingeColor:     NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.085, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.29, alpha: 0.11),
                lidBorder:      NSColor(calibratedRed: 0.38, green: 0.46, blue: 0.60, alpha: 0.52),
                logoColor:      NSColor(calibratedRed: 0.70, green: 0.78, blue: 0.92, alpha: 0.22)
            )
        case .spaceGray:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.52, green: 0.535, blue: 0.56, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.41, green: 0.425, blue: 0.45, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.28, green: 0.29, blue: 0.31, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.66, green: 0.675, blue: 0.70, alpha: 0.92),
                keyWell:        NSColor(calibratedRed: 0.08, green: 0.085, blue: 0.095, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.13, green: 0.135, blue: 0.145, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.25, alpha: 0.75),
                trackpadFill:   NSColor(calibratedRed: 0.46, green: 0.475, blue: 0.50, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.29, alpha: 0.75),
                hingeColor:     NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.46, green: 0.48, blue: 0.51, alpha: 0.11),
                lidBorder:      NSColor(calibratedRed: 0.68, green: 0.70, blue: 0.73, alpha: 0.55),
                logoColor:      NSColor(calibratedRed: 0.85, green: 0.87, blue: 0.90, alpha: 0.24)
            )
        case .silver:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.87, green: 0.88, blue: 0.895, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.76, green: 0.775, blue: 0.795, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.56, green: 0.58, blue: 0.60, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.97, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.09, green: 0.095, blue: 0.105, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.14, green: 0.145, blue: 0.155, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.27, alpha: 0.75),
                trackpadFill:   NSColor(calibratedRed: 0.82, green: 0.83, blue: 0.845, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.58, green: 0.60, blue: 0.62, alpha: 0.75),
                hingeColor:     NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.72, green: 0.75, blue: 0.79, alpha: 0.10),
                lidBorder:      NSColor(calibratedRed: 0.52, green: 0.55, blue: 0.59, alpha: 0.58),
                logoColor:      NSColor(calibratedRed: 0.56, green: 0.59, blue: 0.64, alpha: 0.30)
            )
        case .starlight:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.90, green: 0.87, blue: 0.815, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.80, green: 0.765, blue: 0.70, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.60, green: 0.565, blue: 0.505, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.89, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.15, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.24, green: 0.24, blue: 0.25, alpha: 0.75),
                trackpadFill:   NSColor(calibratedRed: 0.85, green: 0.82, blue: 0.76, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.62, green: 0.585, blue: 0.525, alpha: 0.75),
                hingeColor:     NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.105, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.80, green: 0.75, blue: 0.67, alpha: 0.10),
                lidBorder:      NSColor(calibratedRed: 0.58, green: 0.54, blue: 0.47, alpha: 0.56),
                logoColor:      NSColor(calibratedRed: 0.62, green: 0.57, blue: 0.49, alpha: 0.30)
            )
        case .skyBlue:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.77, green: 0.845, blue: 0.895, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.64, green: 0.73, blue: 0.795, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.45, green: 0.54, blue: 0.605, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.88, green: 0.935, blue: 0.97, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.08, green: 0.095, blue: 0.11, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.13, green: 0.145, blue: 0.16, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.23, green: 0.25, blue: 0.28, alpha: 0.75),
                trackpadFill:   NSColor(calibratedRed: 0.71, green: 0.79, blue: 0.85, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.48, green: 0.56, blue: 0.63, alpha: 0.75),
                hingeColor:     NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.60, green: 0.72, blue: 0.82, alpha: 0.11),
                lidBorder:      NSColor(calibratedRed: 0.44, green: 0.56, blue: 0.66, alpha: 0.58),
                logoColor:      NSColor(calibratedRed: 0.48, green: 0.60, blue: 0.70, alpha: 0.30)
            )

        // MARK: MacBook Neo Finishes (with signature color-coordinated keycaps!)
        case .neoBlush:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.96, green: 0.82, blue: 0.85, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.89, green: 0.71, blue: 0.76, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.72, green: 0.53, blue: 0.59, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.99, green: 0.90, blue: 0.92, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.81, green: 0.63, blue: 0.68, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.94, green: 0.83, blue: 0.86, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.74, green: 0.58, blue: 0.63, alpha: 0.80),
                trackpadFill:   NSColor(calibratedRed: 0.93, green: 0.77, blue: 0.81, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.73, green: 0.55, blue: 0.61, alpha: 0.78),
                hingeColor:     NSColor(calibratedRed: 0.66, green: 0.49, blue: 0.55, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.94, green: 0.74, blue: 0.80, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.76, green: 0.52, blue: 0.59, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.78, green: 0.50, blue: 0.58, alpha: 0.32)
            )
        case .neoCitrus:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.97, green: 0.91, blue: 0.52, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.89, green: 0.81, blue: 0.36, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.68, green: 0.60, blue: 0.22, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.72, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.78, green: 0.71, blue: 0.30, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.66, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.72, green: 0.65, blue: 0.28, alpha: 0.80),
                trackpadFill:   NSColor(calibratedRed: 0.93, green: 0.86, blue: 0.46, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.70, green: 0.62, blue: 0.24, alpha: 0.78),
                hingeColor:     NSColor(calibratedRed: 0.60, green: 0.53, blue: 0.20, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.95, green: 0.87, blue: 0.40, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.72, green: 0.63, blue: 0.22, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.74, green: 0.64, blue: 0.18, alpha: 0.32)
            )
        case .neoIndigo:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.31, green: 0.36, blue: 0.58, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.22, green: 0.26, blue: 0.45, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.32, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.48, green: 0.54, blue: 0.76, alpha: 0.92),
                keyWell:        NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.35, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.27, green: 0.31, blue: 0.50, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.38, green: 0.43, blue: 0.64, alpha: 0.78),
                trackpadFill:   NSColor(calibratedRed: 0.26, green: 0.31, blue: 0.51, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.33, alpha: 0.82),
                hingeColor:     NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.29, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.26, green: 0.31, blue: 0.54, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.72, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.64, green: 0.70, blue: 0.92, alpha: 0.28)
            )

        // MARK: iMac 24-inch Finishes
        case .imacBlue:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.45, green: 0.66, blue: 0.84, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.33, green: 0.53, blue: 0.73, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.22, green: 0.39, blue: 0.58, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.68, green: 0.82, blue: 0.94, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.30, green: 0.49, blue: 0.68, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.72, green: 0.78, blue: 0.84, alpha: 0.85),
                trackpadFill:   NSColor(calibratedRed: 0.52, green: 0.72, blue: 0.88, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.27, green: 0.45, blue: 0.63, alpha: 0.78),
                hingeColor:     NSColor(calibratedRed: 0.22, green: 0.38, blue: 0.55, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.38, green: 0.60, blue: 0.82, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.28, green: 0.50, blue: 0.72, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.30, green: 0.52, blue: 0.76, alpha: 0.32)
            )
        case .imacGreen:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.45, green: 0.73, blue: 0.61, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.32, green: 0.60, blue: 0.48, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.21, green: 0.44, blue: 0.35, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.68, green: 0.88, blue: 0.79, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.28, green: 0.54, blue: 0.43, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.97, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.70, green: 0.80, blue: 0.75, alpha: 0.85),
                trackpadFill:   NSColor(calibratedRed: 0.53, green: 0.78, blue: 0.67, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.25, green: 0.48, blue: 0.39, alpha: 0.78),
                hingeColor:     NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.33, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.36, green: 0.68, blue: 0.55, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.25, green: 0.56, blue: 0.44, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.26, green: 0.58, blue: 0.45, alpha: 0.32)
            )
        case .imacPink:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.92, green: 0.56, blue: 0.64, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.82, green: 0.42, blue: 0.52, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.64, green: 0.29, blue: 0.38, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.81, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.76, green: 0.38, blue: 0.47, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.96, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.84, green: 0.72, blue: 0.75, alpha: 0.85),
                trackpadFill:   NSColor(calibratedRed: 0.94, green: 0.64, blue: 0.71, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.68, green: 0.34, blue: 0.43, alpha: 0.78),
                hingeColor:     NSColor(calibratedRed: 0.60, green: 0.27, blue: 0.36, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.88, green: 0.46, blue: 0.56, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.76, green: 0.35, blue: 0.45, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.80, green: 0.36, blue: 0.47, alpha: 0.32)
            )
        case .imacYellow:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.96, green: 0.83, blue: 0.42, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.87, green: 0.71, blue: 0.28, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.68, green: 0.53, blue: 0.17, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.99, green: 0.92, blue: 0.68, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.80, green: 0.65, blue: 0.25, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.94, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.84, green: 0.79, blue: 0.64, alpha: 0.85),
                trackpadFill:   NSColor(calibratedRed: 0.96, green: 0.86, blue: 0.52, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.72, green: 0.57, blue: 0.20, alpha: 0.78),
                hingeColor:     NSColor(calibratedRed: 0.64, green: 0.50, blue: 0.16, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.92, green: 0.77, blue: 0.32, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.76, green: 0.60, blue: 0.20, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.78, green: 0.62, blue: 0.18, alpha: 0.32)
            )
        case .imacOrange:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.95, green: 0.63, blue: 0.44, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.86, green: 0.50, blue: 0.31, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.66, green: 0.35, blue: 0.19, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.99, green: 0.80, blue: 0.68, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.79, green: 0.45, blue: 0.27, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.94, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.84, green: 0.75, blue: 0.68, alpha: 0.85),
                trackpadFill:   NSColor(calibratedRed: 0.95, green: 0.69, blue: 0.53, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.70, green: 0.39, blue: 0.22, alpha: 0.78),
                hingeColor:     NSColor(calibratedRed: 0.62, green: 0.33, blue: 0.18, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.91, green: 0.55, blue: 0.35, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.78, green: 0.42, blue: 0.24, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.82, green: 0.44, blue: 0.24, alpha: 0.32)
            )
        case .imacPurple:
            return Palette(
                deckTop:        NSColor(calibratedRed: 0.67, green: 0.62, blue: 0.85, alpha: 1.0),
                deckBottom:     NSColor(calibratedRed: 0.54, green: 0.49, blue: 0.74, alpha: 1.0),
                chassisSide:    NSColor(calibratedRed: 0.39, green: 0.34, blue: 0.58, alpha: 1.0),
                borderEdge:     NSColor(calibratedRed: 0.82, green: 0.79, blue: 0.94, alpha: 0.95),
                keyWell:        NSColor(calibratedRed: 0.49, green: 0.44, blue: 0.68, alpha: 1.0),
                keycap:         NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.99, alpha: 1.0),
                keycapBorder:   NSColor(calibratedRed: 0.77, green: 0.74, blue: 0.86, alpha: 0.85),
                trackpadFill:   NSColor(calibratedRed: 0.72, green: 0.68, blue: 0.88, alpha: 1.0),
                trackpadBorder: NSColor(calibratedRed: 0.44, green: 0.39, blue: 0.62, alpha: 0.78),
                hingeColor:     NSColor(calibratedRed: 0.37, green: 0.32, blue: 0.54, alpha: 1.0),
                lidTint:        NSColor(calibratedRed: 0.60, green: 0.54, blue: 0.80, alpha: 0.12),
                lidBorder:      NSColor(calibratedRed: 0.48, green: 0.42, blue: 0.68, alpha: 0.60),
                logoColor:      NSColor(calibratedRed: 0.52, green: 0.45, blue: 0.74, alpha: 0.32)
            )
        }
    }
}

enum MacBookColorOption: String, CaseIterable {
    case auto = "自动匹配本机颜色"
    // MacBook Pro & Air
    case spaceBlack = "深空黑色 (Space Black)"
    case silver = "银色 (Silver)"
    case spaceGray = "深空灰色 (Space Gray)"
    case midnight = "午夜色 (Midnight)"
    case starlight = "星光色 (Starlight)"
    case skyBlue = "天蓝色 (Sky Blue)"
    // MacBook Neo
    case neoBlush = "MacBook Neo · 桃粉色 (Blush)"
    case neoCitrus = "MacBook Neo · 柑橘黄 (Citrus)"
    case neoIndigo = "MacBook Neo · 靛蓝色 (Indigo)"
    // iMac
    case imacBlue = "iMac · 蓝色 (Blue)"
    case imacGreen = "iMac · 绿色 (Green)"
    case imacPink = "iMac · 粉色 (Pink)"
    case imacYellow = "iMac · 黄色 (Yellow)"
    case imacOrange = "iMac · 橙色 (Orange)"
    case imacPurple = "iMac · 紫色 (Purple)"

    var explicitColor: MacBookColor? {
        switch self {
        case .auto:       return nil
        case .spaceBlack: return .spaceBlack
        case .silver:     return .silver
        case .spaceGray:  return .spaceGray
        case .midnight:   return .midnight
        case .starlight:  return .starlight
        case .skyBlue:    return .skyBlue
        case .neoBlush:   return .neoBlush
        case .neoCitrus:  return .neoCitrus
        case .neoIndigo:  return .neoIndigo
        case .imacBlue:   return .imacBlue
        case .imacGreen:  return .imacGreen
        case .imacPink:   return .imacPink
        case .imacYellow: return .imacYellow
        case .imacOrange: return .imacOrange
        case .imacPurple: return .imacPurple
        }
    }
    var displayName: String {
        explicitColor?.displayName ?? L10n.tr("Auto-Match This Mac", "自动匹配本机颜色")
    }
}

enum DeskSetupMode: String, CaseIterable {
    case auto = "自动检测外设 (推荐)"
    case laptop = "Apple 笔记本模式"
    case keyboardAndMouse = "经典外接键鼠"

    var displayName: String {
        switch self {
        case .auto:             return L10n.tr("Auto-Detect Peripherals (Recommended)", "自动检测外设 (推荐)")
        case .laptop:           return L10n.tr("Apple Laptop Mode", "Apple 笔记本模式")
        case .keyboardAndMouse: return L10n.tr("Classic Keyboard & Mouse", "经典外接键鼠")
        }
    }
}

// MARK: - Live Hardware Peripheral & MacBook Finish Monitor

/// Detects connected external keyboards/mice and Apple laptop enclosure finish
/// via IOKit HID enumeration & DeviceTree (requires zero Input Monitoring permissions).
final class HardwareMonitor {
    static let shared = HardwareMonitor()

    private(set) var isMacLaptop: Bool = false
    private(set) var hasBuiltInKeyboard: Bool = false
    private(set) var hasBuiltInTrackpad: Bool = false
    private(set) var hasExternalKeyboard: Bool = false
    private(set) var hasExternalMouse: Bool = false
    private(set) var detectedLaptopColor: MacBookColor = .silver

    private var hidManager: IOHIDManager?
    private var cachedClamshellClosed: Bool = false
    private var lastClamshellCheck: CFTimeInterval = -100

    private init() {
        isMacLaptop = Self.detectIsMacLaptop()
        detectedLaptopColor = Self.detectMacBookColor()
        cachedClamshellClosed = Self.readClamshellClosed()
        lastClamshellCheck = CACurrentMediaTime()
        startDeviceMonitor()
    }

    deinit {
        if let mgr = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    // MARK: - Resolved Desk Display State

    var isClamshellClosed: Bool {
        let now = CACurrentMediaTime()
        if now - lastClamshellCheck > 2.0 {
            lastClamshellCheck = now
            cachedClamshellClosed = Self.readClamshellClosed()
        }
        return cachedClamshellClosed
    }

    private static func readClamshellClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        if let val = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            return val
        }
        return false
    }

    var shouldShowLaptop: Bool {
        switch CatSettings.shared.deskSetupMode {
        case .laptop:
            return true
        case .keyboardAndMouse:
            return false
        case .auto:
            guard isMacLaptop && !isClamshellClosed else { return false }
            // On an open MacBook, show the Apple Laptop whenever using the built-in keyboard
            // (immune to USB-C monitors/docks/hubs that register dummy HID keyboard endpoints!).
            if !hasExternalKeyboard { return true }
            return InputEngine.shared.activeKeyboardSource == .builtIn
        }
    }

    var shouldShowExternalKeyboard: Bool {
        switch CatSettings.shared.deskSetupMode {
        case .laptop:
            return false
        case .keyboardAndMouse:
            return true
        case .auto:
            if shouldShowLaptop { return false }
            return hasExternalKeyboard || hasBuiltInKeyboard
        }
    }

    var shouldShowExternalMouse: Bool {
        switch CatSettings.shared.deskSetupMode {
        case .laptop:
            return hasExternalMouse && InputEngine.shared.activePointerSource == .external
        case .keyboardAndMouse:
            return true
        case .auto:
            guard hasExternalMouse else { return false }
            if isMacLaptop && !isClamshellClosed {
                // Only show an external mouse next to an open MacBook when actually using it
                return InputEngine.shared.activePointerSource == .external
            }
            return true
        }
    }

    var hasAnyKeyboardSurface: Bool {
        shouldShowLaptop || shouldShowExternalKeyboard
    }

    var effectiveLaptopColor: MacBookColor {
        CatSettings.shared.macBookColorOption.explicitColor ?? detectedLaptopColor
    }

    var hardwareSummary: String {
        if shouldShowLaptop {
            let colorName = effectiveLaptopColor.displayName
            if shouldShowExternalMouse {
                return L10n.tr("💻 MacBook (\(colorName)) + 🖱️ Mouse", "💻 MacBook (\(colorName)) + 🖱️ 外接鼠标")
            }
            return "💻 MacBook (\(colorName))"
        }
        var parts: [String] = []
        if shouldShowExternalKeyboard { parts.append(L10n.tr("⌨️ Keyboard", "⌨️ 键盘")) }
        if shouldShowExternalMouse { parts.append(L10n.tr("🖱️ Mouse", "🖱️ 鼠标")) }
        return parts.isEmpty ? L10n.tr("🐾 No Peripherals", "🐾 无外设 (纯猫猫模式)") : parts.joined(separator: " + ")
    }

    // MARK: - Live IOHIDManager Peripheral Enumeration

    private func startDeviceMonitor() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { ctx, _, _, _ in
            guard let ctx else { return }
            let monitor = Unmanaged<HardwareMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.refreshDevices()
            }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, callback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, callback, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = mgr
        refreshDevices()
    }

    func refreshDevices() {
        guard let mgr = hidManager,
              let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
            return
        }

        struct DeviceIdentity: Hashable {
            let vid: Int
            let pid: Int
            let loc: Int
            let product: String
        }

        var builtInKB = false
        var builtInTP = false
        var extKBDevices = Set<DeviceIdentity>()
        var extMouseDevices = Set<DeviceIdentity>()

        for dev in devices {
            let usage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0
            let builtInNum = (IOHIDDeviceGetProperty(dev, kIOHIDBuiltInKey as CFString) as? NSNumber)?.intValue ?? 0
            let transport = (IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String) ?? ""
            let product = (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String) ?? ""
            let vid = (IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let pid = (IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let loc = (IOHIDDeviceGetProperty(dev, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0

            let isVirtual = transport.caseInsensitiveCompare("Virtual") == .orderedSame
                || product.localizedCaseInsensitiveContains("Karabiner")
                || product.localizedCaseInsensitiveContains("Virtual")
            if isVirtual { continue }

            let isInternal = (builtInNum != 0)
                || transport.caseInsensitiveCompare("FIFO") == .orderedSame
                || transport.caseInsensitiveCompare("SPI") == .orderedSame
                || product.localizedCaseInsensitiveContains("Apple Internal")

            if isInternal {
                if usage == kHIDUsage_GD_Keyboard { builtInKB = true }
                else if usage == kHIDUsage_GD_Mouse { builtInTP = true }
                continue
            }

            let id = DeviceIdentity(vid: vid, pid: pid, loc: loc, product: product)
            if usage == kHIDUsage_GD_Keyboard {
                extKBDevices.insert(id)
            } else if usage == kHIDUsage_GD_Mouse {
                extMouseDevices.insert(id)
            }
        }

        // Disambiguate composite USB/BT devices that expose BOTH keyboard & mouse HID interfaces
        // (e.g. QMK/VIA mechanical keyboards with a dummy mouse interface, or gaming mice with macro keys).
        let mouseKeywords = [
            "mouse", "trackball", "trackpad", "mx master", "mx anywhere", "mx vertical",
            "deathadder", "viper", "basilisk", "superlight", "g pro", "g304", "g305", "g502",
            "magic mouse", "aerox", "model o", "model d", "pulsar", "lamzu", "zowie", "finalmouse"
        ]
        func looksLikeMouse(_ product: String) -> Bool {
            let lower = product.lowercased()
            return mouseKeywords.contains { lower.contains($0) }
        }

        let compositeDevices = extKBDevices.intersection(extMouseDevices)
        for comp in compositeDevices {
            if looksLikeMouse(comp.product) {
                extKBDevices.remove(comp)
            } else {
                // Composite keyboard (QMK/VIA/media/knob) — ignore its secondary mouse HID interface
                extMouseDevices.remove(comp)
            }
        }

        hasBuiltInKeyboard = builtInKB
        hasBuiltInTrackpad = builtInTP
        hasExternalKeyboard = !extKBDevices.isEmpty
        hasExternalMouse = !extMouseDevices.isEmpty
        if !hasExternalKeyboard {
            InputEngine.shared.resetExternalKeyboardSourceIfNeeded()
        }
        if !hasExternalMouse {
            InputEngine.shared.resetExternalPointerSourceIfNeeded()
        }
        if builtInKB && builtInTP {
            isMacLaptop = true
        }
    }

    // MARK: - MacBook Model & Enclosure Color Detection

    private static func detectIsMacLaptop() -> Bool {
        // 1. Check IODeviceTree:/product -> product-name / builtin-battery
        let prodEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if prodEntry != 0 {
            defer { IOObjectRelease(prodEntry) }
            if let data = IORegistryEntryCreateCFProperty(prodEntry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
               let name = String(data: data, encoding: .utf8),
               name.localizedCaseInsensitiveContains("MacBook") {
                return true
            }
            if let batt = IORegistryEntryCreateCFProperty(prodEntry, "builtin-battery" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
               let first = batt.first, first != 0 {
                return true
            }
        }

        // 2. Fallback: AppleSmartBattery service presence
        let battService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if battService != 0 {
            IOObjectRelease(battService)
            return true
        }

        // 3. Fallback: sysctl hw.model
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var buf = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &buf, &size, nil, 0)
            let model = String(cString: buf)
            if model.localizedCaseInsensitiveContains("MacBook") {
                return true
            }
        }

        return false
    }

    private static func readProductName() -> String {
        let prodEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard prodEntry != 0 else { return "" }
        defer { IOObjectRelease(prodEntry) }
        if let data = IORegistryEntryCreateCFProperty(prodEntry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
           let name = String(data: data, encoding: .utf8) {
            return name.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \n\t"))
        }
        return ""
    }

    private static func detectMacBookColor() -> MacBookColor {
        let productName = readProductName()
        let isIMac = productName.localizedCaseInsensitiveContains("iMac")
        let isNeo = productName.localizedCaseInsensitiveContains("Neo")

        // Sample the official system computer icon (macOS renders the exact Mac enclosure color!)
        if let img = NSImage(named: NSImage.computerName),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let w = cg.width
            let h = cg.height
            let rep = NSBitmapImageRep(cgImage: cg)

            var rSum: CGFloat = 0
            var gSum: CGFloat = 0
            var bSum: CGFloat = 0
            var count: CGFloat = 0

            // Sample the metallic base lip (MacBook C-side) or colorful lower chin (iMac)
            let yStart = Int(Double(h) * (isIMac ? 0.62 : 0.72))
            let yEnd = max(yStart + 1, Int(Double(h) * (isIMac ? 0.76 : 0.85)))
            let xStart = Int(Double(w) * 0.25)
            let xEnd = max(xStart + 1, Int(Double(w) * 0.75))

            for y in yStart..<yEnd {
                for x in xStart..<xEnd {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.8 {
                        rSum += c.redComponent
                        gSum += c.greenComponent
                        bSum += c.blueComponent
                        count += 1
                    }
                }
            }

            if count > 10 {
                let r = rSum / count
                let g = gSum / count
                let b = bSum / count
                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                let delta = maxC - minC
                let sat = maxC > 0.001 ? (delta / maxC) : 0
                let lum = 0.299 * r + 0.587 * g + 0.114 * b

                // Compute hue in degrees [0..360)
                var hue: CGFloat = 0
                if delta > 0.001 {
                    if maxC == r {
                        hue = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6.0))
                    } else if maxC == g {
                        hue = 60.0 * (((b - r) / delta) + 2.0)
                    } else {
                        hue = 60.0 * (((r - g) / delta) + 4.0)
                    }
                    if hue < 0 { hue += 360.0 }
                }

                // Saturated vibrant finishes (MacBook Neo & iMac)
                if sat >= 0.16 && lum >= 0.26 {
                    if hue >= 320 || hue < 15 {
                        return (isIMac && !isNeo) ? .imacPink : .neoBlush
                    } else if hue < 42 {
                        return .imacOrange
                    } else if hue < 78 {
                        return (isIMac && !isNeo) ? .imacYellow : .neoCitrus
                    } else if hue < 175 {
                        return .imacGreen
                    } else if hue < 225 {
                        return isIMac ? .imacBlue : .skyBlue
                    } else if hue < 265 {
                        return .neoIndigo
                    } else {
                        return .imacPurple
                    }
                }

                // Neutral / subtle metallic MacBook finishes
                if lum < 0.28 {
                    // Dark finishes: Midnight has a noticeable cool-blue cast vs neutral Space Black
                    return (b - r > 0.035) ? .midnight : .spaceBlack
                } else if lum < 0.56 {
                    return .spaceGray
                } else {
                    if r - b > 0.035 { return .starlight }
                    if b - r > 0.035 { return .skyBlue }
                    return .silver
                }
            }
        }

        // Secondary fallback via IODeviceTree:/chosen housing-color code
        let chosen = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
        if chosen != 0 {
            defer { IOObjectRelease(chosen) }
            if let data = IORegistryEntryCreateCFProperty(chosen, "housing-color" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
               data.count >= 16 {
                let code = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
                switch code {
                case 9:  return .spaceBlack
                case 4:  return .midnight
                case 2:  return .spaceGray
                case 3:  return .starlight
                default: return .silver
                }
            }
        }

        return .silver
    }
}
