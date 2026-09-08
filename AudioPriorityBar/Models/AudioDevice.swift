import Foundation
import CoreAudio

enum AudioDeviceType: String, Codable {
    case input
    case output
}

enum OutputPresentation: Equatable {
    case unmuted
    case muted
    case unselected
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
    /// Battery percentage reported by a connected Bluetooth device, when the
    /// device exposes one. `nil` means that no readable battery status exists.
    var batteryLevel: Int? = nil
    /// The Mac's own speakers or headphone jack. Always present and always
    /// mutable through CoreAudio, which makes it the reliable place to send
    /// audio when the device you are on refuses to go quiet.
    var isBuiltIn: Bool = false

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

    /// USB composite devices (a mic with a headphone jack) often appear twice
    /// in CoreAudio with the same name and the same device serial, differing
    /// only by interface index in the UID.
    func isSameHardware(as other: AudioDevice) -> Bool {
        guard type == other.type else { return false }
        if uid == other.uid { return true }
        if id != 0, id == other.id { return true }

        let parts = uid.split(separator: ":")
        let otherParts = other.uid.split(separator: ":")
        if parts.count >= 4, otherParts.count >= 4,
           parts[0] == otherParts[0],
           parts[1] == otherParts[1],
           parts[2] == otherParts[2],
           parts[3] == otherParts[3] {
            return true
        }

        guard name.caseInsensitiveCompare(other.name) == .orderedSame else { return false }
        if name.localizedCaseInsensitiveContains("microphone") {
            return true
        }
        return Self.stripInterfaceIndex(uid) == Self.stripInterfaceIndex(other.uid)
            && Self.stripInterfaceIndex(uid) != uid
    }

    private static func stripInterfaceIndex(_ uid: String) -> String {
        uid.replacingOccurrences(of: #":\d+$"#, with: "", options: .regularExpression)
    }

    static func uniqued(_ devices: [AudioDevice], preferring id: AudioObjectID? = nil) -> [AudioDevice] {
        var result: [AudioDevice] = []
        for device in devices {
            if let index = result.firstIndex(where: { $0.isSameHardware(as: device) }) {
                if device.id == id, result[index].id != id {
                    result[index] = device
                }
            } else {
                result.append(device)
            }
        }
        return result
    }
}

enum DeviceTab: String, CaseIterable {
    case speaker
    case headphone
    case microphone

    var label: String {
        switch self {
        case .speaker: return "Speakers"
        case .headphone: return "Headphones"
        case .microphone: return "Microphones"
        }
    }

    var icon: String {
        switch self {
        case .speaker: return "speaker.wave.2.fill"
        case .headphone: return "headphones"
        case .microphone: return "mic.fill"
        }
    }
}
