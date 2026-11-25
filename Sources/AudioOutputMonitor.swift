import CoreAudio
import Foundation

/// Watches the system's default sound output and tells the cat whether it is a pair of headphones
/// (so it can put its AirPods on) and whether anything is playing through it (for music notes).
/// Only the device's type is read — never any audio.
final class AudioOutputMonitor {
    static let shared = AudioOutputMonitor()

    /// Called on the main queue. `animated` is false for the first report at launch.
    var onHeadphonesChange: ((_ isHeadphones: Bool, _ animated: Bool) -> Void)?
    /// Called on the main queue when the output device starts or stops playing.
    var onPlayingChange: ((Bool) -> Void)?

    private(set) var isHeadphones = false
    private(set) var isPlaying = false
    private var started = false
    private var watchedDevice = AudioObjectID(kAudioObjectUnknown)
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }

    // Selectors watched on the current device: headphone jack (data source) and playback.
    private static let deviceSelectors: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
        (kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput),
        (kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal),
    ]

    func start() {
        guard !started else { return }
        started = true
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.refresh()
        }
        refresh(initial: true)
    }

    private func refresh(initial: Bool = false) {
        let device = Self.defaultOutputDevice()
        if device != watchedDevice {
            for (sel, scope) in Self.deviceSelectors {
                var addr = Self.address(sel, scope)
                if watchedDevice != kAudioObjectUnknown {
                    AudioObjectRemovePropertyListenerBlock(watchedDevice, &addr, .main, deviceListener)
                }
                if device != kAudioObjectUnknown {
                    AudioObjectAddPropertyListenerBlock(device, &addr, .main, deviceListener)
                }
            }
            watchedDevice = device
        }

        let headphones = Self.isHeadphoneDevice(device)
        if initial || headphones != isHeadphones {
            isHeadphones = headphones
            onHeadphonesChange?(headphones, !initial)
        }
        let playing: UInt32 = Self.property(device, kAudioDevicePropertyDeviceIsRunningSomewhere, default: 0)
        if initial || (playing != 0) != isPlaying {
            isPlaying = playing != 0
            onPlayingChange?(isPlaying)
        }
    }

    /// Headphones = Bluetooth (AirPods etc.), USB headsets, or the built-in headphone jack.
    /// Speakers = the Mac's own speakers, HDMI / DisplayPort monitors, AirPlay, and virtual devices.
    static func isHeadphoneDevice(_ device: AudioObjectID) -> Bool {
        guard device != kAudioObjectUnknown else { return false }
        let transport: UInt32 = property(device, kAudioDevicePropertyTransportType, default: 0)
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeUSB:
            return true
        case kAudioDeviceTransportTypeBuiltIn:
            // Apple Silicon lists the jack as its own "External Headphones" device; Intel Macs switch
            // one built-in device between data sources. Both report 'hdpn' for headphones.
            let source: UInt32 = property(device, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput, default: 0)
            return source == 0x6864_706E // 'hdpn'
        default:
            return false
        }
    }

    static func defaultOutputDevice() -> AudioObjectID {
        property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                 default: AudioObjectID(kAudioObjectUnknown))
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, default value: T) -> T {
        var addr = address(selector, scope)
        var result = value
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectHasProperty(object, &addr),
              AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &result) == noErr else { return value }
        return result
    }
}
