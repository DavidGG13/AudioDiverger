import CoreAudio
import Foundation

/// A hardware (or virtual) device that can play audio.
struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32

    var symbol: String {
        let lower = name.lowercased()
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            return lower.contains("airpods") ? "airpods" : "headphones"
        }
        if lower.contains("headphone") || lower.contains("căști") || lower.contains("casti") {
            return "headphones"
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual: return "waveform"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker"
        default: return "speaker.wave.2"
        }
    }
}

enum DeviceCatalog {
    static func outputDevices() -> [OutputDevice] {
        CA.objectIDs(.system, kAudioHardwarePropertyDevices).compactMap { id in
            guard CA.channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
                  let uid = CA.string(id, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix(AppRoute.aggregatePrefix),
                  let name = CA.string(id, kAudioObjectPropertyName) else { return nil }
            let transport = CA.scalar(id, kAudioDevicePropertyTransportType, initial: UInt32(0)) ?? 0
            return OutputDevice(id: id, uid: uid, name: name, transport: transport)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultOutputDeviceID() -> AudioObjectID {
        CA.scalar(.system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID.unknown) ?? .unknown
    }
}
