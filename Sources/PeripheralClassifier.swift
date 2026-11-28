import Foundation

/// Desk HID usage, independent of IOKit so the census rules can be checked without a device.
enum HIDDeskUsage {
    case keyboard
    case mouse
    case other
}

struct HIDCensusDevice: Equatable {
    var usage: HIDDeskUsage
    var isBuiltIn: Bool
    var transport: String
    var product: String
    var vendorID: Int
    var productID: Int
    var locationID: Int
}

struct PeripheralFlags: Equatable {
    var hasBuiltInKeyboard = false
    var hasBuiltInTrackpad = false
    var hasExternalKeyboard = false
    var hasExternalMouse = false
}

/// Classifies a HID census. An empty list is "nothing connected": every flag is false,
/// which is what `HardwareMonitor` applies when `IOHIDManagerCopyDevices` is nil or empty.
enum PeripheralClassifier {
    static let mouseKeywords = [
        "mouse", "trackball", "trackpad", "mx master", "mx anywhere", "mx vertical",
        "deathadder", "viper", "basilisk", "superlight", "g pro", "g304", "g305", "g502",
        "magic mouse", "aerox", "model o", "model d", "pulsar", "lamzu", "zowie", "finalmouse"
    ]

    static func classify(_ devices: [HIDCensusDevice]) -> PeripheralFlags {
        struct Identity: Hashable {
            var vendorID: Int
            var productID: Int
            var locationID: Int
            var product: String
        }

        var builtInKB = false
        var builtInTP = false
        var extKB = Set<Identity>()
        var extMouse = Set<Identity>()

        for dev in devices {
            let transport = dev.transport
            let product = dev.product
            let isVirtual = transport.caseInsensitiveCompare("Virtual") == .orderedSame
                || product.localizedCaseInsensitiveContains("Karabiner")
                || product.localizedCaseInsensitiveContains("Virtual")
            if isVirtual { continue }

            let isInternal = dev.isBuiltIn
                || transport.caseInsensitiveCompare("FIFO") == .orderedSame
                || transport.caseInsensitiveCompare("SPI") == .orderedSame
                || product.localizedCaseInsensitiveContains("Apple Internal")
            if isInternal {
                if dev.usage == .keyboard { builtInKB = true }
                else if dev.usage == .mouse { builtInTP = true }
                continue
            }

            let id = Identity(vendorID: dev.vendorID, productID: dev.productID, locationID: dev.locationID, product: product)
            if dev.usage == .keyboard {
                extKB.insert(id)
            } else if dev.usage == .mouse {
                extMouse.insert(id)
            }
        }

        for comp in extKB.intersection(extMouse) {
            if looksLikeMouse(comp.product) {
                extKB.remove(comp)
            } else {
                extMouse.remove(comp)
            }
        }

        return PeripheralFlags(
            hasBuiltInKeyboard: builtInKB,
            hasBuiltInTrackpad: builtInTP,
            hasExternalKeyboard: !extKB.isEmpty,
            hasExternalMouse: !extMouse.isEmpty
        )
    }

    static func looksLikeMouse(_ product: String) -> Bool {
        let lower = product.lowercased()
        return mouseKeywords.contains { lower.contains($0) }
    }
}
