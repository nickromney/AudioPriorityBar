import Foundation

/// A device address that survives a reconnect.
///
/// `AudioObjectID`s are reassigned when a device is unplugged and plugged back
/// in, so mute state keyed by ID silently attaches itself to the wrong device.
struct MuteKey: Hashable {
    let type: AudioDeviceType
    let uid: String
}

extension AudioDevice {
    var muteKey: MuteKey {
        MuteKey(type: type, uid: uid)
    }
}

/// What the hardware did when we asked it to go quiet.
enum MuteOutcome: Equatable {
    /// The write was read back and the device is silent.
    case silenced
    /// The device kept playing: it accepted the write and ignored it, or it has
    /// no settable mute or volume at all. HDMI displays and devices with
    /// hardware-only volume behave this way.
    case refused
}

/// The single source of truth for what should be silent.
///
/// Polling CoreAudio cannot answer this. A display will accept a mute write and
/// keep playing, and a device whose volume cannot be read looks identical to
/// one at full volume. So intent is stored here and the hardware's response is
/// recorded *next to* it rather than replacing it: the UI can then say "muted,
/// but this device ignored it" instead of quietly flipping back to "live".
///
/// Mute-all is a separate latch rather than an intent written onto every
/// device, so releasing it restores the devices it silenced while leaving the
/// ones the user muted individually alone.
struct MuteLedger {
    private(set) var allOutputsEngaged = false
    private(set) var allInputsEngaged = false
    private var deviceIntents: Set<MuteKey> = []
    private var selectionIntents: Set<MuteKey> = []
    private var outcomes: [MuteKey: MuteOutcome] = [:]
    private var savedLevels: [MuteKey: Float] = [:]

    /// The lowest level we still consider audible. CoreAudio scalars are
    /// floats, and a "zero" that came back from hardware is rarely exactly 0.
    static let silenceThreshold: Float = 0.01

    // MARK: - Intent

    func wantsMuted(_ key: MuteKey) -> Bool {
        if deviceIntents.contains(key) || selectionIntents.contains(key) { return true }
        if key.type == .output { return allOutputsEngaged }
        return allInputsEngaged
    }

    /// True when the latch alone is silencing this device, so releasing the
    /// latch should bring it back.
    func isMutedOnlyByAllOutputs(_ key: MuteKey) -> Bool {
        allOutputsEngaged && key.type == .output && !deviceIntents.contains(key)
    }

    mutating func setIntent(muted: Bool, for key: MuteKey) {
        if muted {
            selectionIntents.remove(key)
            deviceIntents.insert(key)
        } else {
            deviceIntents.remove(key)
            selectionIntents.remove(key)
            outcomes.removeValue(forKey: key)
        }
    }

    /// Records the temporary silence applied by the output-selection gesture.
    /// It is separate from a mute button intent so selecting another device
    /// can release only the selection-created mute.
    mutating func setSelectionIntent(muted: Bool, for key: MuteKey) {
        if muted {
            selectionIntents.insert(key)
        } else {
            selectionIntents.remove(key)
            if !deviceIntents.contains(key) {
                outcomes.removeValue(forKey: key)
            }
        }
    }

    mutating func clearSelectionIntents() {
        for key in selectionIntents {
            outcomes.removeValue(forKey: key)
        }
        selectionIntents.removeAll()
    }

    mutating func engageAllOutputs() {
        allOutputsEngaged = true
    }

    /// Drops the latch and every intent it implied. Devices the user muted
    /// individually keep their intent.
    mutating func releaseAllOutputs() {
        allOutputsEngaged = false
        for key in outcomes.keys where key.type == .output && !deviceIntents.contains(key) {
            outcomes.removeValue(forKey: key)
        }
    }

    /// Clears every output intent as well as the latch. Used by "Unmute All",
    /// which the user reads as "make everything audible again".
    mutating func releaseAllOutputsAndIntents() {
        allOutputsEngaged = false
        for key in deviceIntents where key.type == .output {
            deviceIntents.remove(key)
        }
        for key in outcomes.keys where key.type == .output {
            outcomes.removeValue(forKey: key)
        }
        selectionIntents = selectionIntents.filter { $0.type != .output }
    }

    /// Turns the latch into an explicit intent on each device it was covering,
    /// then drops the latch.
    ///
    /// Used when one device is about to be made audible on its own: after Mute
    /// All, letting a single device through must not quietly unmute the rest.
    mutating func pinLatchAsIntents(_ keys: [MuteKey]) {
        guard allOutputsEngaged else { return }
        for key in keys where key.type == .output {
            deviceIntents.insert(key)
        }
        allOutputsEngaged = false
    }

    mutating func releaseAllInputs() {
        allInputsEngaged = false
        for key in deviceIntents where key.type == .input {
            deviceIntents.remove(key)
        }
        for key in outcomes.keys where key.type == .input {
            outcomes.removeValue(forKey: key)
        }
    }

    mutating func engageAllInputs() {
        allInputsEngaged = true
    }

    // MARK: - Hardware response

    mutating func record(_ outcome: MuteOutcome, for key: MuteKey) {
        outcomes[key] = outcome
    }

    func outcome(for key: MuteKey) -> MuteOutcome? {
        outcomes[key]
    }

    /// Devices we were asked to silence that are still making noise. These are
    /// worth naming in the UI: the user needs to reach for the device's own
    /// controls.
    func refusedKeys() -> Set<MuteKey> {
        Set(outcomes.filter { $0.value == .refused && wantsMuted($0.key) }.keys)
    }

    /// A device that ignored our mute is audible no matter what we intended.
    /// Reporting it as silent is the failure the user hears.
    func isKnownAudibleDespiteIntent(_ key: MuteKey) -> Bool {
        wantsMuted(key) && outcomes[key] == .refused
    }

    // MARK: - Levels

    /// Remembers the level to come back to. A level that is already silent is
    /// not worth saving: restoring it would leave the user at zero with no
    /// obvious way back.
    mutating func saveLevel(_ level: Float, for key: MuteKey) {
        guard level > Self.silenceThreshold else { return }
        savedLevels[key] = level
    }

    mutating func takeSavedLevel(for key: MuteKey) -> Float? {
        savedLevels.removeValue(forKey: key)
    }

    func savedLevel(for key: MuteKey) -> Float? {
        savedLevels[key]
    }

    /// Picks a level that is actually audible, in order of preference:
    /// what the device was at, where it is now, the last slider position, and
    /// finally a middle default. Unmuting must never land back on silence.
    static func usableRestoredVolume(saved: Float?, current: Float?, fallback: Float) -> Float {
        if let saved, saved > silenceThreshold { return saved }
        if let current, current > silenceThreshold { return current }
        if fallback > silenceThreshold { return fallback }
        return 0.5
    }

    /// A HAL notification says this device is now at `level`. Returns true when
    /// that means the user unmuted it somewhere else (the keyboard, System
    /// Settings, the device's own knob) and our intent should be dropped.
    ///
    /// A device that refused our mute is excluded: it never went quiet, so its
    /// level rising proves nothing about what the user wants.
    func externalUnmuteDetected(for key: MuteKey, level: Float) -> Bool {
        guard wantsMuted(key) else { return false }
        guard outcomes[key] != .refused else { return false }
        return level > Self.silenceThreshold
    }
}
