import Foundation

struct StoredDevice: Codable, Equatable {
    let uid: String
    let name: String
    let isInput: Bool
    var lastSeen: Date

    var lastSeenRelative: String {
        let now = Date()
        let interval = now.timeIntervalSince(lastSeen)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return "\(weeks)w ago"
        } else {
            let months = Int(interval / 2592000)
            return "\(months)mo ago"
        }
    }
}

class PriorityManager {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private let inputPrioritiesKey = "inputPriorities"
    private let speakerPrioritiesKey = "speakerPriorities"
    private let headphonePrioritiesKey = "headphonePriorities"
    private let deviceCategoriesKey = "deviceCategories"
    private let currentModeKey = "currentMode"
    private let customModeKey = "customMode"
    private let hiddenDevicesKey = "hiddenDevices"
    private let knownDevicesKey = "knownDevices"
    private let deviceLevelsKey = "deviceLevels"
    private let deviceLevelsEnabledKey = "deviceLevelsEnabled"
    private let volumeControlPreferencesKey = "volumeControlPreferences"
    private let defaultOutputCategoryKey = "defaultOutputCategory"
    private let enormousModeKey = "enormousMode"

    // MARK: - Known Devices (Persistent Memory)

    func getKnownDevices() -> [StoredDevice] {
        guard let data = defaults.data(forKey: knownDevicesKey),
              let devices = try? JSONDecoder().decode([StoredDevice].self, from: data) else {
            return []
        }
        return devices
    }

    func rememberDevice(_ uid: String, name: String, isInput: Bool) {
        var known = getKnownDevices()
        let now = Date()
        if let index = known.firstIndex(where: { $0.uid == uid }) {
            // Update name and lastSeen
            known[index] = StoredDevice(uid: uid, name: name, isInput: isInput, lastSeen: now)
        } else {
            known.append(StoredDevice(uid: uid, name: name, isInput: isInput, lastSeen: now))
        }
        saveKnownDevices(known)
    }

    /// Some USB devices (notably Studio Display audio) include the connection
    /// path in their UID and return with a new UID after reconnecting. Move the
    /// old device's settings before recording the new identity.
    func migrateDeviceUIDIfNeeded(uid: String, name: String, isInput: Bool) {
        guard getStoredDevice(uid: uid) == nil else { return }
        guard let old = getKnownDevices().last(where: {
            $0.uid != uid && $0.name == name && $0.isInput == isInput
        }) else { return }

        migrateUID(in: inputPrioritiesKey, from: old.uid, to: uid)
        migrateUID(in: speakerPrioritiesKey, from: old.uid, to: uid)
        migrateUID(in: headphonePrioritiesKey, from: old.uid, to: uid)
        migrateUID(in: hiddenMicsKey, from: old.uid, to: uid)
        migrateUID(in: hiddenSpeakersKey, from: old.uid, to: uid)
        migrateUID(in: hiddenHeadphonesKey, from: old.uid, to: uid)
        migrateUID(in: neverUseKey, from: old.uid, to: uid)
        migrateUID(in: deviceLevelsKey, from: old.uid, to: uid)

        var categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        if let category = categories.removeValue(forKey: old.uid) {
            categories[uid] = category
            defaults.set(categories, forKey: deviceCategoriesKey)
        }

        var known = getKnownDevices()
        known.removeAll { $0.uid == old.uid }
        saveKnownDevices(known)
    }

    func getStoredDevice(uid: String) -> StoredDevice? {
        getKnownDevices().first { $0.uid == uid }
    }

    func forgetDevice(_ uid: String) {
        var known = getKnownDevices()
        known.removeAll { $0.uid == uid }
        saveKnownDevices(known)
    }

    private func saveKnownDevices(_ devices: [StoredDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: knownDevicesKey)
        }
    }

    // MARK: - Mode Management

    var currentMode: OutputCategory {
        get {
            guard let raw = defaults.string(forKey: currentModeKey),
                  let mode = OutputCategory(rawValue: raw) else {
                return .speaker
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: currentModeKey)
        }
    }

    var defaultOutputCategory: OutputCategory {
        get {
            guard let raw = defaults.string(forKey: defaultOutputCategoryKey),
                  let category = OutputCategory(rawValue: raw) else { return .speaker }
            return category
        }
        set { defaults.set(newValue.rawValue, forKey: defaultOutputCategoryKey) }
    }

    var isEnormousMode: Bool {
        get {
            guard defaults.object(forKey: enormousModeKey) != nil else { return true }
            return defaults.bool(forKey: enormousModeKey)
        }
        set { defaults.set(newValue, forKey: enormousModeKey) }
    }

    var isCustomMode: Bool {
        get { defaults.bool(forKey: customModeKey) }
        set { defaults.set(newValue, forKey: customModeKey) }
    }

    var areDeviceLevelsEnabled: Bool {
        get {
            guard defaults.object(forKey: deviceLevelsEnabledKey) != nil else { return true }
            return defaults.bool(forKey: deviceLevelsEnabledKey)
        }
        set { defaults.set(newValue, forKey: deviceLevelsEnabledKey) }
    }

    func deviceLevel(for uid: String) -> Float? {
        guard let data = defaults.data(forKey: deviceLevelsKey),
              let levels = try? JSONDecoder().decode([String: Float].self, from: data) else { return nil }
        return levels[uid]
    }

    func saveDeviceLevel(_ level: Float, for uid: String) {
        var levels: [String: Float] = [:]
        if let data = defaults.data(forKey: deviceLevelsKey),
           let stored = try? JSONDecoder().decode([String: Float].self, from: data) {
            levels = stored
        }
        levels[uid] = max(0, min(1, level))
        if let data = try? JSONEncoder().encode(levels) {
            defaults.set(data, forKey: deviceLevelsKey)
        }
    }

    func volumeControlPreference(for uid: String) -> VolumeControlPreference {
        let preferences = defaults.dictionary(forKey: volumeControlPreferencesKey) as? [String: String] ?? [:]
        guard let raw = preferences[uid], let preference = VolumeControlPreference(rawValue: raw) else {
            return .automatic
        }
        return preference
    }

    func setVolumeControlPreference(_ preference: VolumeControlPreference, for uid: String) {
        var preferences = defaults.dictionary(forKey: volumeControlPreferencesKey) as? [String: String] ?? [:]
        if preference == .automatic {
            preferences.removeValue(forKey: uid)
        } else {
            preferences[uid] = preference.rawValue
        }
        defaults.set(preferences, forKey: volumeControlPreferencesKey)
    }

    // MARK: - Device Categories

    func getCategory(for device: AudioDevice) -> OutputCategory {
        let categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        if let raw = categories[device.uid], let category = OutputCategory(rawValue: raw) {
            return category
        }
        // Default headphone-like devices to headphone category
        if HeadphoneDetection.isHeadphone(deviceName: device.name) {
            return .headphone
        }
        return .speaker
    }

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        var categories = defaults.dictionary(forKey: deviceCategoriesKey) as? [String: String] ?? [:]
        categories[device.uid] = category.rawValue
        defaults.set(categories, forKey: deviceCategoriesKey)
    }

    // MARK: - Never Use Devices (never auto-selected)

    private let neverUseKey = "neverUseDevices"

    func isNeverUse(_ device: AudioDevice) -> Bool {
        let list = defaults.array(forKey: neverUseKey) as? [String] ?? []
        return list.contains(device.uid)
    }

    func setNeverUse(_ device: AudioDevice, neverUse: Bool) {
        var list = defaults.array(forKey: neverUseKey) as? [String] ?? []
        if neverUse {
            if !list.contains(device.uid) {
                list.append(device.uid)
            }
        } else {
            list.removeAll { $0 == device.uid }
        }
        defaults.set(list, forKey: neverUseKey)
    }

    // MARK: - Hidden Devices (per category)

    private let hiddenMicsKey = "hiddenMics"
    private let hiddenSpeakersKey = "hiddenSpeakers"
    private let hiddenHeadphonesKey = "hiddenHeadphones"

    func isHidden(_ device: AudioDevice) -> Bool {
        let key = hiddenKey(for: device)
        let hidden = defaults.array(forKey: key) as? [String] ?? []
        return hidden.contains(device.uid)
    }

    func isHidden(_ device: AudioDevice, inCategory category: OutputCategory) -> Bool {
        let key = category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        let hidden = defaults.array(forKey: key) as? [String] ?? []
        return hidden.contains(device.uid)
    }

    func hideDevice(_ device: AudioDevice) {
        let key = hiddenKey(for: device)
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        if !hidden.contains(device.uid) {
            hidden.append(device.uid)
            defaults.set(hidden, forKey: key)
        }
    }

    func hideDevice(_ device: AudioDevice, inCategory category: OutputCategory) {
        let key = category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        if !hidden.contains(device.uid) {
            hidden.append(device.uid)
            defaults.set(hidden, forKey: key)
        }
    }

    func unhideDevice(_ device: AudioDevice) {
        let key = hiddenKey(for: device)
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        hidden.removeAll { $0 == device.uid }
        defaults.set(hidden, forKey: key)
    }

    func unhideDevice(_ device: AudioDevice, fromCategory category: OutputCategory) {
        let key = category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        var hidden = defaults.array(forKey: key) as? [String] ?? []
        hidden.removeAll { $0 == device.uid }
        defaults.set(hidden, forKey: key)
    }

    private func hiddenKey(for device: AudioDevice) -> String {
        if device.type == .input {
            return hiddenMicsKey
        } else {
            let category = getCategory(for: device)
            return category == .speaker ? hiddenSpeakersKey : hiddenHeadphonesKey
        }
    }

    // MARK: - Priority Management

    func sortByPriority(_ devices: [AudioDevice], type: AudioDeviceType) -> [AudioDevice] {
        let key = priorityKey(for: type, category: nil)
        return sortDevices(devices, usingKey: key)
    }

    func sortByPriority(_ devices: [AudioDevice], category: OutputCategory) -> [AudioDevice] {
        let key = priorityKey(for: .output, category: category)
        return sortDevices(devices, usingKey: key)
    }

    func savePriorities(_ devices: [AudioDevice], type: AudioDeviceType) {
        let key = priorityKey(for: type, category: nil)
        savePriorities(devices, key: key)
    }

    func savePriorities(_ devices: [AudioDevice], category: OutputCategory) {
        let key = priorityKey(for: .output, category: category)
        savePriorities(devices, key: key)
    }

    // MARK: - Private Helpers

    private func priorityKey(for type: AudioDeviceType, category: OutputCategory?) -> String {
        switch type {
        case .input:
            return inputPrioritiesKey
        case .output:
            switch category {
            case .speaker, .none:
                return speakerPrioritiesKey
            case .headphone:
                return headphonePrioritiesKey
            }
        }
    }

    private func sortDevices(_ devices: [AudioDevice], usingKey key: String) -> [AudioDevice] {
        let priorities = defaults.array(forKey: key) as? [String] ?? []

        return devices.enumerated().sorted { lhs, rhs in
            let indexA = priorities.firstIndex(of: lhs.element.uid) ?? Int.max
            let indexB = priorities.firstIndex(of: rhs.element.uid) ?? Int.max
            return indexA == indexB ? lhs.offset < rhs.offset : indexA < indexB
        }.map(\.element)
    }

    private func migrateUID(in key: String, from oldUID: String, to newUID: String) {
        if key == deviceLevelsKey {
            guard let data = defaults.data(forKey: key),
                  var levels = try? JSONDecoder().decode([String: Float].self, from: data),
                  let level = levels.removeValue(forKey: oldUID) else { return }
            levels[newUID] = level
            if let newData = try? JSONEncoder().encode(levels) { defaults.set(newData, forKey: key) }
            return
        }
        guard var values = defaults.array(forKey: key) as? [String],
              let index = values.firstIndex(of: oldUID) else { return }
        values.removeAll { $0 == newUID || $0 == oldUID }
        values.insert(newUID, at: min(index, values.count))
        defaults.set(values, forKey: key)
    }

    private func mergedPriorityOrder(existing: [String], visible: [String]) -> [String] {
        guard !existing.isEmpty else { return visible }
        var remaining = visible
        var result = existing.map { uid -> String in
            guard let index = remaining.firstIndex(of: uid) else { return uid }
            return remaining.remove(at: index)
        }
        result.append(contentsOf: remaining)
        return result
    }

    private func savePriorities(_ devices: [AudioDevice], key: String) {
        let uids = devices.map { $0.uid }
        let existing = defaults.array(forKey: key) as? [String] ?? []
        defaults.set(mergedPriorityOrder(existing: existing, visible: uids), forKey: key)
    }
}
