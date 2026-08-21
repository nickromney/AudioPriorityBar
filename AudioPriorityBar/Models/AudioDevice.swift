import Foundation
import CoreAudio

enum AudioDeviceType: String, Codable {
    case input
    case output
}

enum VolumeControlPreference: String, Codable {
    case automatic
    case digital
    case device

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .digital: return "Digital slider"
        case .device: return "Device controls"
        }
    }
}

enum OutputCategory: String, Codable, CaseIterable {
    case speaker
    case headphone

    var icon: String {
        switch self {
        case .speaker: return "speaker.wave.2.fill"
        case .headphone: return "headphones"
        }
    }

    var label: String {
        switch self {
        case .speaker: return "Speakers"
        case .headphone: return "Headphones"
        }
    }
}

struct AudioDevice: Identifiable, Equatable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let type: AudioDeviceType
    var isConnected: Bool = true

    var isValid: Bool {
        id != kAudioObjectUnknown
    }

    /// Vocaster's listening and microphone levels are controlled by its
    /// internal mixer and physical controls, not macOS's virtual main volume.
    /// A CoreAudio volume property may still exist, but changing it does not
    /// change the level heard through the Vocaster.
    var supportsSystemVolumeControl: Bool {
        !name.localizedCaseInsensitiveContains("vocaster")
    }

    /// External displays generally have no convenient physical volume
    /// control, so prefer the digital slider for this monitor family unless
    /// the user explicitly chooses another mode.
    var prefersDigitalVolumeControl: Bool {
        name.localizedCaseInsensitiveContains("PL2792Q")
    }

    // Create a disconnected placeholder from stored device
    static func disconnected(uid: String, name: String, type: AudioDeviceType) -> AudioDevice {
        AudioDevice(id: 0, uid: uid, name: name, type: type, isConnected: false)
    }
}
