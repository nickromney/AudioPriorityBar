import SwiftUI
import CoreAudio
import AVFoundation
import AppKit
import Darwin

/// Menu-bar apps can be launched from multiple copies on disk. Bundle IDs do
/// not prevent that, so keep an OS-level lock for the lifetime of this process.
final class SingleInstanceGuard {
    static let shared = SingleInstanceGuard()

    private var fileDescriptor: Int32 = -1

    private init() {}

    func acquire() -> Bool {
        guard fileDescriptor == -1 else { return true }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioPriorityBar.instance.lock")
            .path
        let descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        fileDescriptor = descriptor
        return true
    }

    deinit {
        release()
    }

    func release() {
        guard fileDescriptor >= 0 else { return }
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }
}

enum AppProcess {
    static func relaunchConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        return configuration
    }

    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        SingleInstanceGuard.shared.release()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: relaunchConfiguration()) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

@main
struct AudioPriorityBarApp: App {
    @StateObject private var audioManager: AudioManager

    init() {
        guard SingleInstanceGuard.shared.acquire() else {
            // Another copy already owns the menu-bar slot. Exit quietly so a
            // second app bundle cannot leave a confusing duplicate icon.
            exit(EXIT_SUCCESS)
        }
        _audioManager = StateObject(wrappedValue: AudioManager())
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(audioManager)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .menuBarExtraStyle(.window)

    }
}

struct MenuBarLabel: View {
    let volume: Float
    let isOutputMuted: Bool
    let isInputMuted: Bool
    let isCustomMode: Bool
    let mode: OutputCategory
    let micFlash: Bool

    var body: some View {
        HStack(spacing: 2) {
            if isInputMuted {
                Image(systemName: micFlash ? "mic.fill" : "mic.slash.fill")
            }
            if isCustomMode {
                Image(systemName: "hand.raised.fill")
            } else if mode == .headphone {
                Image(systemName: "headphones")
            }
            if isOutputMuted {
                Image(systemName: "speaker.slash.fill")
            } else {
                Image(systemName: "speaker.wave.3.fill", variableValue: Double(volume))
            }
        }
    }
}

struct VolumeMeterView: View {
    let volume: Float
    let isMuted: Bool
    private let barCount = 4
    private let barSpacing: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let barWidth = (size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)
            let filledBars = isMuted ? 0 : Int(ceil(Double(volume) * Double(barCount)))
            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + barSpacing)
                let barHeight = size.height * CGFloat(i + 1) / CGFloat(barCount)
                let y = size.height - barHeight
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: 1)
                if i < filledBars {
                    context.fill(path, with: .color(isMuted ? .red : .primary))
                } else {
                    context.fill(path, with: .color(.primary.opacity(0.25)))
                }
            }
        }
    }
}

@MainActor
class AudioManager: ObservableObject {
    @Published var inputDevices: [AudioDevice] = []
    @Published var speakerDevices: [AudioDevice] = []
    @Published var headphoneDevices: [AudioDevice] = []
    @Published var hiddenInputDevices: [AudioDevice] = []
    @Published var hiddenSpeakerDevices: [AudioDevice] = []
    @Published var hiddenHeadphoneDevices: [AudioDevice] = []
    @Published var currentInputId: AudioObjectID?
    @Published var currentOutputId: AudioObjectID?
    @Published var currentMode: OutputCategory = .speaker
    @Published var volume: Float = 0
    @Published var inputGain: Float = 0
    @Published var perDeviceLevelsEnabled: Bool
    @Published var isEditMode: Bool = false
    @Published var isCustomMode: Bool = false
    // A single CoreAudio device can expose both input and output streams.
    // Keep direction in the key so muting one side never marks the other side muted.
    @Published var mutedDeviceKeys: Set<String> = []
    @Published var isActiveOutputMuted: Bool = false
    @Published var isActiveInputMuted: Bool = false
    @Published var micFlashState: Bool = false
    @Published var isEnormousMode: Bool
    @Published var keepMutedWhenChangingSelection: Bool

    private let deviceService: any AudioDeviceServicing
    private var micFlashTimer: Timer?
    private var softwareMutedInputKeys: Set<String> = []
    private var softwareMutedOutputKeys: Set<String> = []
    private var savedInputVolumes: [String: Float] = [:]
    private var savedOutputVolumes: [String: Float] = [:]
    private var muteAllOutputsEngaged = false
    let priorityManager: PriorityManager
    private var connectedDeviceUIDs: Set<String> = []
    /// Unfiltered connected devices, including USB interface twins that are
    /// collapsed to one row in the visible lists. Mute-all still addresses
    /// every HAL object so a hidden twin cannot keep playing.
    private var connectedOutputsForControl: [AudioDevice] = []
    private var connectedInputsForControl: [AudioDevice] = []

    var menuBarIcon: String {
        currentMode.icon
    }

    var defaultOutputCategory: OutputCategory {
        get { priorityManager.defaultOutputCategory }
        set { priorityManager.defaultOutputCategory = newValue }
    }

    var currentOutputSupportsSystemVolumeControl: Bool {
        guard let device = device(withId: currentOutputId, type: .output) else { return true }
        return usesDigitalVolume(for: device) && (deviceService.supportsDeviceVolumeControl(device.id, type: .output) || volumeControlPreference(for: device) == .digital)
    }

    var currentInputSupportsSystemVolumeControl: Bool {
        guard let device = device(withId: currentInputId, type: .input) else { return true }
        return usesDigitalVolume(for: device) && (deviceService.supportsDeviceVolumeControl(device.id, type: .input) || volumeControlPreference(for: device) == .digital)
    }

    func volumeControlPreference(for device: AudioDevice) -> VolumeControlPreference {
        let preference = priorityManager.volumeControlPreference(for: device.uid)
        if preference == .automatic && device.prefersDigitalVolumeControl {
            return .digital
        }
        return preference
    }

    func setVolumeControlPreference(_ preference: VolumeControlPreference, for device: AudioDevice) {
        priorityManager.setVolumeControlPreference(preference, for: device.uid)
        if device.id == currentOutputId || device.id == currentInputId {
            refreshVolume()
            refreshInputGain()
            objectWillChange.send()
        }
    }

    private func usesDigitalVolume(for device: AudioDevice) -> Bool {
        switch volumeControlPreference(for: device) {
        case .digital: return true
        case .device: return false
        case .automatic: return device.supportsSystemVolumeControl
        }
    }

    func refreshVolume() {
        volume = deviceService.getOutputVolume()
    }

    func refreshInputGain() {
        inputGain = deviceService.getInputVolume()
    }

    func refreshMuteStatus() {
        var muted: Set<String> = []
        for device in inputDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .input) {
                muted.insert(muteKey(for: device))
            }
        }
        for device in speakerDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .output) {
                muted.insert(muteKey(for: device))
            }
        }
        for device in headphoneDevices where device.isConnected {
            if deviceService.isDeviceMuted(device.id, type: .output) {
                muted.insert(muteKey(for: device))
            }
        }
        mutedDeviceKeys = muted.union(softwareMutedInputKeys).union(softwareMutedOutputKeys)
        if let outputId = currentOutputId {
            isActiveOutputMuted = volume <= 0.01 && (
                muteAllOutputsEngaged || mutedDeviceKeys.contains("output:\(outputId)")
            )
        } else {
            isActiveOutputMuted = false
        }
        if let inputId = currentInputId {
            isActiveInputMuted = mutedDeviceKeys.contains("input:\(inputId)")
        } else {
            isActiveInputMuted = false
        }
        if isActiveInputMuted && micFlashTimer == nil {
            micFlashTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.micFlashState.toggle()
                }
            }
        } else if !isActiveInputMuted && micFlashTimer != nil {
            micFlashTimer?.invalidate()
            micFlashTimer = nil
            micFlashState = false
        }
    }

    func isDeviceMuted(_ device: AudioDevice) -> Bool {
        if deviceService.getDeviceVolume(device.id, type: device.type) > 0.01 {
            return false
        }
        if device.type == .output && muteAllOutputsEngaged { return true }
        return mutedDeviceKeys.contains(muteKey(for: device))
    }

    private func muteKey(for device: AudioDevice) -> String {
        "\(device.type.rawValue):\(device.id)"
    }

    private func uniquedForControl(_ devices: [AudioDevice]) -> [AudioDevice] {
        var seen = Set<String>()
        return devices.filter { $0.isConnected && seen.insert("\($0.type.rawValue):\($0.uid)").inserted }
    }

    func setVolume(_ newVolume: Float) {
        guard currentOutputSupportsSystemVolumeControl else { return }
        if newVolume > 0.01 {
            muteAllOutputsEngaged = false
            if let device = currentOutputDevice {
                _ = deviceService.setDeviceMuted(false, deviceId: device.id, type: .output)
                softwareMutedOutputKeys.remove(muteKey(for: device))
            }
        }
        volume = newVolume
        deviceService.setOutputVolume(newVolume, force: true)
        if let outputId = currentOutputId {
            _ = deviceService.setDeviceVolume(newVolume, deviceId: outputId, type: .output, force: true)
        }
        saveLevel(newVolume, for: currentOutputId, type: .output)
        refreshMuteStatus()
    }

    func setInputGain(_ newGain: Float) {
        guard currentInputSupportsSystemVolumeControl else { return }
        inputGain = newGain
        let force = currentInputDevice.map { volumeControlPreference(for: $0) == .digital } ?? false
        deviceService.setInputVolume(newGain, force: force)
        saveLevel(newGain, for: currentInputId, type: .input)
    }

    func setPerDeviceLevelsEnabled(_ enabled: Bool) {
        perDeviceLevelsEnabled = enabled
        priorityManager.areDeviceLevelsEnabled = enabled
        if enabled {
            restoreLevel(for: currentOutputId, type: .output)
            restoreLevel(for: currentInputId, type: .input)
        }
    }

    func setEnormousMode(_ enabled: Bool) {
        isEnormousMode = enabled
        priorityManager.isEnormousMode = enabled
    }

    func setKeepMutedWhenChangingSelection(_ enabled: Bool) {
        keepMutedWhenChangingSelection = enabled
        priorityManager.keepMutedWhenChangingSelection = enabled
    }

    var allConnectedOutputDevices: [AudioDevice] {
        uniquedForControl(connectedOutputsForControl)
    }

    var areAllOutputsMuted: Bool {
        if muteAllOutputsEngaged { return true }
        let devices = allConnectedOutputDevices
        return !devices.isEmpty && devices.allSatisfy { isDeviceMuted($0) }
    }

    var allConnectedInputDevices: [AudioDevice] {
        uniquedForControl(connectedInputsForControl)
    }

    var areAllInputsMuted: Bool {
        let devices = allConnectedInputDevices
        return !devices.isEmpty && devices.allSatisfy { isDeviceMuted($0) }
    }

    func setAllOutputsMuted(_ muted: Bool) {
        muteAllOutputsEngaged = muted
        for device in connectedOutputsForControl {
            applyOutputMute(muted, to: device)
        }
        refreshMuteStatus()
        refreshVolume()
    }

    func setAllInputsMuted(_ muted: Bool) {
        for device in allConnectedInputDevices {
            let key = muteKey(for: device)
            if muted {
                if !softwareMutedInputKeys.contains(key) {
                    savedInputVolumes[key] = deviceService.getDeviceVolume(device.id, type: .input)
                }
                let hardwareMuted = deviceService.setDeviceMuted(true, deviceId: device.id, type: .input)
                let volumeMuted = deviceService.setDeviceVolume(0, deviceId: device.id, type: .input, force: true)
                if hardwareMuted || volumeMuted {
                    softwareMutedInputKeys.insert(key)
                }
            } else {
                _ = deviceService.setDeviceMuted(false, deviceId: device.id, type: .input)
                if let savedVolume = savedInputVolumes.removeValue(forKey: key) {
                    _ = deviceService.setDeviceVolume(savedVolume, deviceId: device.id, type: .input, force: true)
                }
                softwareMutedInputKeys.remove(key)
            }
        }
        refreshMuteStatus()
    }

    var activeOutputDevices: [AudioDevice] {
        switch currentMode {
        case .speaker: return speakerDevices
        case .headphone: return headphoneDevices
        }
    }

    init(
        deviceService: any AudioDeviceServicing = AudioDeviceService(),
        priorityManager: PriorityManager = PriorityManager()
    ) {
        self.deviceService = deviceService
        self.priorityManager = priorityManager
        currentMode = priorityManager.currentMode
        isCustomMode = priorityManager.isCustomMode
        perDeviceLevelsEnabled = priorityManager.areDeviceLevelsEnabled
        isEnormousMode = priorityManager.isEnormousMode
        keepMutedWhenChangingSelection = priorityManager.keepMutedWhenChangingSelection
        refreshDevices()
        previousConnectedUIDs = connectedDeviceUIDs  // Initialize tracking
        refreshVolume()
        refreshInputGain()
        refreshMuteStatus()
        setupDeviceChangeListener()
        setupMuteVolumeListener()
        requestMicrophoneAccessIfNeeded()
        if !isCustomMode {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    private func requestMicrophoneAccessIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                // CoreAudio hides input streams until permission has been answered.
                self?.refreshDevices()
                self?.refreshMuteStatus()
            }
        }
    }

    private func setupMuteVolumeListener() {
        deviceService.onMuteOrVolumeChanged = { [weak self] in
            Task { @MainActor in
                self?.handleMuteOrVolumeChange()
            }
        }
    }

    private func handleMuteOrVolumeChange() {
        refreshMuteStatus()
        refreshVolume()
        refreshInputGain()
    }

    func refreshDevices() {
        let allConnectedDevices = deviceService.getDevices()
        connectedDeviceUIDs = Set(allConnectedDevices.map { $0.uid })
        for device in allConnectedDevices {
            priorityManager.migrateDeviceUIDIfNeeded(
                uid: device.uid,
                name: device.name,
                isInput: device.type == .input
            )
            priorityManager.rememberDevice(device.uid, name: device.name, isInput: device.type == .input)
        }
        connectedInputsForControl = allConnectedDevices.filter { $0.type == .input }
        connectedOutputsForControl = allConnectedDevices.filter { $0.type == .output }
        let connectedInputs = AudioDevice.uniqued(
            connectedInputsForControl,
            preferring: deviceService.getCurrentDefaultDevice(type: .input)
        )
        let connectedOutputs = AudioDevice.uniqued(
            connectedOutputsForControl,
            preferring: deviceService.getCurrentDefaultDevice(type: .output)
        )

        if isEditMode {
            let knownDevices = priorityManager.getKnownDevices()
            var allInputs: [AudioDevice] = connectedInputs
            for stored in knownDevices where stored.isInput {
                if !connectedDeviceUIDs.contains(stored.uid) {
                    allInputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .input))
                }
            }
            var allOutputs: [AudioDevice] = connectedOutputs
            for stored in knownDevices where !stored.isInput {
                if !connectedDeviceUIDs.contains(stored.uid) {
                    allOutputs.append(.disconnected(uid: stored.uid, name: stored.name, type: .output))
                }
            }
            inputDevices = priorityManager.sortByPriority(allInputs, type: .input)
            hiddenInputDevices = []
            let speakers = allOutputs.filter { priorityManager.getCategory(for: $0) == .speaker }
            let headphones = allOutputs.filter { priorityManager.getCategory(for: $0) == .headphone }
            speakerDevices = priorityManager.sortByPriority(speakers, category: .speaker)
            headphoneDevices = priorityManager.sortByPriority(headphones, category: .headphone)
            hiddenSpeakerDevices = []
            hiddenHeadphoneDevices = []
        } else {
            // Filter out hidden and never-use devices in normal mode
            let visibleInputs = connectedInputs.filter { !priorityManager.isHidden($0) && !priorityManager.isNeverUse($0) }
            // Hidden inputs: regular hidden first, then never-use
            let regularHiddenInputs = connectedInputs.filter { priorityManager.isHidden($0) && !priorityManager.isNeverUse($0) }
            let neverUseInputs = connectedInputs.filter { priorityManager.isNeverUse($0) }
            inputDevices = priorityManager.sortByPriority(visibleInputs, type: .input)
            hiddenInputDevices = regularHiddenInputs + neverUseInputs

            let speakers = connectedOutputs.filter { priorityManager.getCategory(for: $0) == .speaker }
            let headphones = connectedOutputs.filter { priorityManager.getCategory(for: $0) == .headphone }
            let visibleSpeakers = speakers.filter { !priorityManager.isHidden($0, inCategory: .speaker) && !priorityManager.isNeverUse($0) }
            let visibleHeadphones = headphones.filter { !priorityManager.isHidden($0, inCategory: .headphone) && !priorityManager.isNeverUse($0) }
            // Hidden outputs: regular hidden first, then never-use
            let regularHiddenSpeakers = speakers.filter { priorityManager.isHidden($0, inCategory: .speaker) && !priorityManager.isNeverUse($0) }
            let neverUseSpeakers = speakers.filter { priorityManager.isNeverUse($0) }
            let regularHiddenHeadphones = headphones.filter { priorityManager.isHidden($0, inCategory: .headphone) && !priorityManager.isNeverUse($0) }
            let neverUseHeadphones = headphones.filter { priorityManager.isNeverUse($0) }
            speakerDevices = priorityManager.sortByPriority(visibleSpeakers, category: .speaker)
            headphoneDevices = priorityManager.sortByPriority(visibleHeadphones, category: .headphone)
            hiddenSpeakerDevices = regularHiddenSpeakers + neverUseSpeakers
            hiddenHeadphoneDevices = regularHiddenHeadphones + neverUseHeadphones
        }
        currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
    }

    func toggleEditMode() {
        isEditMode.toggle()
        refreshDevices()
    }

    func isDeviceConnected(_ device: AudioDevice) -> Bool {
        connectedDeviceUIDs.contains(device.uid)
    }

    /// Tracks device UIDs from the previous refresh to detect new connections
    private var previousConnectedUIDs: Set<String> = []
    
    func setMode(_ mode: OutputCategory) {
        currentMode = mode
        priorityManager.currentMode = mode
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    func toggleMode() {
        let newMode: OutputCategory = currentMode == .speaker ? .headphone : .speaker
        setMode(newMode)
    }

    func setCustomMode(_ enabled: Bool) {
        isCustomMode = enabled
        priorityManager.isCustomMode = enabled
        if !enabled {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    func setCategory(_ category: OutputCategory, for device: AudioDevice) {
        priorityManager.setCategory(category, for: device)
        refreshDevices()
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    func hideDevice(_ device: AudioDevice, category: OutputCategory? = nil) {
        if device.type == .input {
            priorityManager.hideDevice(device)
        } else if let cat = category {
            priorityManager.hideDevice(device, inCategory: cat)
        } else {
            priorityManager.hideDevice(device)
        }
        refreshDevices()
        if !isCustomMode {
            if device.type == .input {
                applyHighestPriorityInput()
            } else {
                applyHighestPriorityOutput()
            }
        }
    }

    func hideDeviceEntirely(_ device: AudioDevice) {
        priorityManager.hideDevice(device, inCategory: .speaker)
        priorityManager.hideDevice(device, inCategory: .headphone)
        refreshDevices()
        if !isCustomMode {
            applyHighestPriorityOutput()
        }
    }

    func unhideDevice(_ device: AudioDevice, category: OutputCategory? = nil) {
        if device.type == .input {
            priorityManager.unhideDevice(device)
        } else if let cat = category {
            priorityManager.unhideDevice(device, fromCategory: cat)
        } else {
            priorityManager.unhideDevice(device)
        }
        refreshDevices()
    }

    func isDeviceIgnored(_ device: AudioDevice, inCategory category: OutputCategory? = nil) -> Bool {
        if device.type == .input {
            return priorityManager.isHidden(device)
        } else if let cat = category {
            return priorityManager.isHidden(device, inCategory: cat)
        } else {
            return priorityManager.isHidden(device)
        }
    }

    func isNeverUse(_ device: AudioDevice) -> Bool {
        priorityManager.isNeverUse(device)
    }

    func setNeverUse(_ device: AudioDevice, neverUse: Bool) {
        priorityManager.setNeverUse(device, neverUse: neverUse)
        refreshDevices()
        if !isCustomMode {
            if device.type == .input {
                applyHighestPriorityInput()
            } else {
                applyHighestPriorityOutput()
            }
        }
    }

    func moveInputDevice(from source: IndexSet, to destination: Int) {
        inputDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(inputDevices, type: .input)
        // Switch to top input if it's connected
        if let topInput = inputDevices.first, topInput.isConnected {
            applyInputDevice(topInput)
        }
    }

    func moveSpeakerDevice(from source: IndexSet, to destination: Int) {
        speakerDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(speakerDevices, category: .speaker)
        // Switch to top speaker only if we're in speaker mode and top speaker is connected
        if currentMode == .speaker, let topSpeaker = speakerDevices.first, topSpeaker.isConnected {
            applyOutputDevice(topSpeaker)
        }
    }

    func moveHeadphoneDevice(from source: IndexSet, to destination: Int) {
        headphoneDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(headphoneDevices, category: .headphone)
        // Switch to top headphone if it's connected
        if let topHeadphone = headphoneDevices.first, topHeadphone.isConnected {
            applyOutputDevice(topHeadphone)
        }
    }

    func setInputDevice(_ device: AudioDevice) {
        applyInputDevice(device)
    }

    func setOutputDevice(_ device: AudioDevice) {
        applyOutputDevice(device)
    }

    /// Select an output and its category as one operation. Changing the mode
    /// first would briefly apply priority-one output, which is visible as a
    /// bounce and can override combined input/output devices such as USB
    /// microphones with headphone outputs.
    func selectOutputDevice(_ device: AudioDevice, category: OutputCategory, applyMode: Bool = true) {
        if applyMode {
            currentMode = category
            priorityManager.currentMode = category
        }
        applyOutputDevice(device, makeAudible: !keepMutedWhenChangingSelection)
    }

    func cycleOutputPresentation(_ device: AudioDevice, category: OutputCategory) {
        switch outputPresentation(for: device) {
        case .unselected:
            selectOutputDevice(device, category: category)
        case .unmuted:
            applyOutputMute(true, to: device)
            refreshMuteStatus()
            refreshVolume()
        case .muted:
            let pool = category == .headphone ? headphoneDevices : speakerDevices
            if let next = pool.first(where: { $0.isConnected && $0.id != device.id }) {
                selectOutputDevice(next, category: category)
            }
        }
    }

    func outputPresentation(for device: AudioDevice) -> OutputPresentation {
        guard device.id == currentOutputId else { return .unselected }
        return isDeviceMuted(device) ? .muted : .unmuted
    }

    private func applyOutputMute(_ muted: Bool, to device: AudioDevice) {
        let key = muteKey(for: device)
        if muted {
            let current = deviceService.getDeviceVolume(device.id, type: .output)
            if current > 0.01 {
                savedOutputVolumes[key] = current
            }
            _ = deviceService.setDeviceMuted(true, deviceId: device.id, type: .output)
            _ = deviceService.setDeviceVolume(0, deviceId: device.id, type: .output, force: true)
            if device.id == currentOutputId {
                deviceService.setOutputVolume(0, force: true)
                volume = 0
            }
            softwareMutedOutputKeys.insert(key)
        } else {
            _ = deviceService.setDeviceMuted(false, deviceId: device.id, type: .output)
            let restored = Self.usableRestoredVolume(
                saved: savedOutputVolumes.removeValue(forKey: key),
                current: deviceService.getDeviceVolume(device.id, type: .output),
                fallback: volume
            )
            _ = deviceService.setDeviceVolume(restored, deviceId: device.id, type: .output, force: true)
            if device.id == currentOutputId {
                deviceService.setOutputVolume(restored, force: true)
                volume = restored
            }
            softwareMutedOutputKeys.remove(key)
        }
    }

    static func usableRestoredVolume(saved: Float?, current: Float, fallback: Float) -> Float {
        if let saved, saved > 0.01 { return saved }
        if current > 0.01 { return current }
        if fallback > 0.01 { return fallback }
        return 0.5
    }

    private func applyInputDevice(_ device: AudioDevice) {
        if let currentInputId {
            saveLevel(deviceService.getDeviceVolume(currentInputId, type: .input), for: currentInputId, type: .input)
        }
        deviceService.setDefaultDevice(device.id, type: .input)
        currentInputId = device.id
        restoreLevel(for: currentInputId, type: .input)
    }

    private func applyOutputDevice(_ device: AudioDevice, makeAudible: Bool = false) {
        if let currentOutputId {
            saveLevel(deviceService.getDeviceVolume(currentOutputId), for: currentOutputId, type: .output)
        }
        deviceService.setDefaultDevice(device.id, type: .output)
        currentOutputId = device.id
        if makeAudible {
            muteAllOutputsEngaged = false
            makeOutputAudible(device)
            refreshMuteStatus()
        } else if muteAllOutputsEngaged {
            applyOutputMute(true, to: device)
            refreshMuteStatus()
            refreshVolume()
        } else {
            restoreLevel(for: currentOutputId, type: .output)
            refreshMuteStatus()
            refreshVolume()
        }
    }

    private func makeOutputAudible(_ device: AudioDevice) {
        _ = deviceService.setDeviceMuted(false, deviceId: device.id, type: .output)
        softwareMutedOutputKeys.remove(muteKey(for: device))
        let restored = Self.usableRestoredVolume(
            saved: perDeviceLevelsEnabled ? priorityManager.deviceLevel(for: device.uid) : nil,
            current: deviceService.getDeviceVolume(device.id, type: .output),
            fallback: volume
        )
        _ = deviceService.setDeviceVolume(restored, deviceId: device.id, type: .output, force: true)
        deviceService.setOutputVolume(restored, force: true)
        volume = restored
    }

    private func device(withId id: AudioObjectID?, type: AudioDeviceType) -> AudioDevice? {
        guard let id else { return nil }
        return (inputDevices + speakerDevices + headphoneDevices).first {
            $0.id == id && $0.type == type
        }
    }

    private var currentOutputDevice: AudioDevice? { device(withId: currentOutputId, type: .output) }
    private var currentInputDevice: AudioDevice? { device(withId: currentInputId, type: .input) }

    private func saveLevel(_ level: Float, for id: AudioObjectID?, type: AudioDeviceType) {
        guard level > 0.01 else { return }
        guard perDeviceLevelsEnabled, let device = device(withId: id, type: type) else { return }
        guard usesDigitalVolume(for: device) else { return }
        priorityManager.saveDeviceLevel(level, for: device.uid)
    }

    private func restoreLevel(for id: AudioObjectID?, type: AudioDeviceType) {
        guard perDeviceLevelsEnabled, let device = device(withId: id, type: type) else { return }
        guard usesDigitalVolume(for: device) else { return }
        if let level = priorityManager.deviceLevel(for: device.uid) {
            let force = volumeControlPreference(for: device) == .digital
            if type == .output { deviceService.setOutputVolume(level, force: force); volume = level }
            else { deviceService.setInputVolume(level, force: force); inputGain = level }
        } else {
            saveLevel(deviceService.getDeviceVolume(device.id, type: type), for: id, type: type)
        }
    }

    private func applyHighestPriorityInput() {
        if let first = inputDevices.first(where: { $0.isConnected && !priorityManager.isNeverUse($0) }) {
            applyInputDevice(first)
        }
    }

    private func applyHighestPriorityOutput() {
        let devices = activeOutputDevices
        if let first = devices.first(where: { $0.isConnected && !priorityManager.isNeverUse($0) }) {
            applyOutputDevice(first)
        }
        refreshMuteStatus()
    }

    private func setupDeviceChangeListener() {
        deviceService.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.handleDeviceChange()
            }
        }
        deviceService.startListening()
    }

    private func handleDeviceChange() {
        let oldConnectedUIDs = previousConnectedUIDs
        refreshDevices()
        refreshMuteStatus()
        
        // Detect newly connected devices
        let newlyConnectedUIDs = connectedDeviceUIDs.subtracting(oldConnectedUIDs)
        let disconnectedUIDs = oldConnectedUIDs.subtracting(connectedDeviceUIDs)
        previousConnectedUIDs = connectedDeviceUIDs

        // A default-device notification also arrives when the user selects a
        // device. Only reapply priority after an actual connection change;
        // otherwise the listener immediately overwrites the user's choice.
        if !isCustomMode && (!newlyConnectedUIDs.isEmpty || !disconnectedUIDs.isEmpty) {
            // Auto-switch mode only when a new headphone connects or all headphones disconnect
            autoSwitchModeIfNeeded(newlyConnectedUIDs: newlyConnectedUIDs)
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }
    
    /// Automatically switches between headphone and speaker mode based on device connections.
    /// Only triggers on:
    /// 1. A new headphone device connects → switch to headphone mode
    /// 2. All headphones disconnect → switch to speaker mode
    private func autoSwitchModeIfNeeded(newlyConnectedUIDs: Set<String>) {
        let connectedHeadphones = headphoneDevices.filter { $0.isConnected }
        let hasConnectedHeadphones = !connectedHeadphones.isEmpty
        let hasConnectedSpeakers = speakerDevices.contains { $0.isConnected }
        
        // Check if a new headphone just connected
        let newHeadphoneConnected = connectedHeadphones.contains { newlyConnectedUIDs.contains($0.uid) }
        
        if newHeadphoneConnected && currentMode != .headphone {
            // A new headphone just connected - switch to headphone mode
            currentMode = .headphone
            priorityManager.currentMode = .headphone
        } else if !hasConnectedHeadphones && hasConnectedSpeakers && currentMode == .headphone {
            // All headphones disconnected - switch back to speaker mode
            currentMode = .speaker
            priorityManager.currentMode = .speaker
        }
    }
}
