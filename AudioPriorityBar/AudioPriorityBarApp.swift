import SwiftUI
import CoreAudio
import AVFoundation
import AppKit
import Combine
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

enum RunContext {
    /// The test bundle is hosted by this very app, so the single-instance lock
    /// would see the user's running copy and exit before a single test could
    /// run. That is the "Could not launch AudioPriorityBarTests" failure.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
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
        let executableURL = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("AudioPriorityBar")
        SingleInstanceGuard.shared.release()

        // LaunchServices can resolve an already-running LSUIElement app back
        // to the existing process, even with createsNewApplicationInstance.
        // Starting the installed executable directly makes Relaunch reliable
        // for both the LaunchAgent copy and a manually opened app bundle.
        do {
            let process = Process()
            process.executableURL = executableURL
            process.currentDirectoryURL = bundleURL
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            // Keep LaunchServices as a fallback for unusual bundle layouts.
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: relaunchConfiguration()) { application, error in
                guard application != nil, error == nil else {
                    print("AudioPriorityBar relaunch failed: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

/// Owns the actual AppKit status item. `MenuBarExtra` is convenient for a
/// static label, but its label is not a reliable live view for status-item
/// tooltips or state changes.
@MainActor
final class StatusItemController: NSObject, ObservableObject, NSPopoverDelegate {
    @Published var showingSettings = false

    private let audioManager: AudioManager
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var observation: AnyCancellable?

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: StatusItemPanel(controller: self, audioManager: audioManager)
        )

        observation = audioManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
    }

    func install() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItem(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Audio Priority Bar"
        updateStatusItem()
    }

    @objc private func handleStatusItem(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Relaunch", action: #selector(relaunch), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        showingSettings = true
        togglePopover()
    }

    @objc private func relaunch() {
        AppProcess.relaunch()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatusItem() {
        statusItem.button?.image = statusItemImage(isMuted: audioManager.isMuteAllActive)
        statusItem.button?.toolTip = "Audio Priority Bar"
    }

    private func statusItemImage(isMuted: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let speaker = NSImage(
            systemSymbolName: "speaker.wave.2.fill",
            accessibilityDescription: "Audio Priority Bar"
        )
        if let speaker {
            let sourceSize = speaker.size
            let scale = min(16 / max(sourceSize.width, 1), 16 / max(sourceSize.height, 1))
            let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let drawRect = NSRect(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            speaker.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: isMuted ? 0.45 : 1
            )
        }

        if isMuted {
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let strike = NSBezierPath()
            strike.move(to: NSPoint(x: 2.5, y: 2.5))
            strike.line(to: NSPoint(x: 15.5, y: 15.5))
            strike.lineWidth = 2
            strike.lineCapStyle = .round
            strike.stroke()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

private struct StatusItemPanel: View {
    @ObservedObject var controller: StatusItemController
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        MenuBarView(showingSettings: $controller.showingSettings)
            .environmentObject(audioManager)
    }
}

@main
struct AudioPriorityBarApp: App {
    @StateObject private var audioManager: AudioManager
    @StateObject private var statusItemController: StatusItemController

    init() {
        guard RunContext.isRunningTests || SingleInstanceGuard.shared.acquire() else {
            // Another copy already owns the menu-bar slot. Exit quietly so a
            // second app bundle cannot leave a confusing duplicate icon.
            exit(EXIT_SUCCESS)
        }
        let manager = AudioManager()
        _audioManager = StateObject(wrappedValue: manager)
        let controller = StatusItemController(audioManager: manager)
        _statusItemController = StateObject(wrappedValue: controller)
        controller.install()
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var audioManager: AudioManager
    let onSettings: () -> Void

    var body: some View {
        ZStack {
            Image(systemName: "speaker.wave.2.fill")

            if audioManager.isMuteAllActive {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 15, weight: .bold))
            }
        }
        .foregroundStyle(.primary)
        .opacity(audioManager.isMuteAllActive ? 0.45 : 1)
        .overlay {
            MenuBarTooltipView(text: "Audio Priority Bar")
                .frame(width: 18, height: 18)
        }
    }
}

/// `MenuBarExtra` hosts its label in AppKit, where SwiftUI's `.help` modifier
/// is not consistently bridged to the status item's tooltip. Give the label
/// an AppKit view with an explicit tooltip instead.
private struct MenuBarTooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
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
    @Published var isActiveOutputMuted: Bool = false
    @Published var isActiveInputMuted: Bool = false
    /// Published separately from the computed device summary so the menu-bar
    /// label updates when the mute ledger's Mute All latch changes.
    @Published private(set) var isMuteAllActive = false
    /// Connected outputs that were told to mute and kept playing anyway.
    /// Named in the UI so the user knows to reach for the device's own controls
    /// instead of assuming the app worked.
    @Published var outputsIgnoringMute: [String] = []
    @Published var micFlashState: Bool = false
    @Published var isEnormousMode: Bool
    @Published var redirectMuteAllToBuiltIn: Bool
    @Published var keepApplicationInForegroundAfterSourceChange: Bool
    /// Set when Mute All had to move audio elsewhere to guarantee silence, so
    /// the panel can say where it went.
    @Published var redirectedOutputName: String?

    private let deviceService: any AudioDeviceServicing
    private var micFlashTimer: Timer?
    /// What the user asked to be silent, and what the hardware did about it.
    private var ledger = MuteLedger()
    /// Where the output was before Mute All moved it to guarantee silence.
    private var outputBeforeMuteAll: String?
    private var redirectedToUID: String?
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
        // A silenced device reads back whatever level it happens to be parked
        // at, so show the level the user will actually hear: nothing.
        if let device = currentOutputDevice, isDeviceMuted(device) {
            volume = 0
        } else {
            volume = deviceService.getOutputVolume()
        }
    }

    func refreshInputGain() {
        if let device = currentInputDevice, isDeviceMuted(device) {
            inputGain = 0
        } else {
            inputGain = deviceService.getInputVolume()
        }
    }

    func refreshMuteStatus() {
        isActiveOutputMuted = currentOutputDevice.map { isDeviceMuted($0) } ?? false
        isActiveInputMuted = currentInputDevice.map { isDeviceMuted($0) } ?? false

        if let device = currentOutputDevice, isDeviceIgnoringMute(device) {
            outputsIgnoringMute = [device.name]
        } else {
            outputsIgnoringMute = []
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

    /// True when this device is silent. Intent comes first: a device that
    /// accepted a mute but exposes no readable level would otherwise look live,
    /// which is the failure the user hears as "mute did nothing".
    func isDeviceMuted(_ device: AudioDevice) -> Bool {
        guard device.isConnected else { return false }
        let key = device.muteKey
        // Still audible despite being told to mute: saying "muted" here would
        // be the lie that sent the user hunting for the sound.
        if ledger.isKnownAudibleDespiteIntent(key) { return false }
        if ledger.wantsMuted(key) { return true }
        return deviceService.isDeviceMuted(device.id, type: device.type)
    }

    /// The device you are listening through was asked to mute and kept
    /// playing.
    ///
    /// Scoped to the current output on purpose: macOS sends audio to the
    /// default device only, so a device that is not selected is silent whether
    /// or not it accepted the mute. Warning about those was telling the user
    /// sound was coming out of devices that were not playing at all.
    func isDeviceIgnoringMute(_ device: AudioDevice) -> Bool {
        guard device.isConnected, device.id == currentOutputId else { return false }
        return ledger.isKnownAudibleDespiteIntent(device.muteKey)
    }

    /// True when we could not silence a device, but it is not the one playing,
    /// so there is nothing for the user to do about it right now.
    func isDeviceUnmutable(_ device: AudioDevice) -> Bool {
        guard device.isConnected else { return false }
        return ledger.outcome(for: device.muteKey) == .refused
    }

    private func uniquedForControl(_ devices: [AudioDevice]) -> [AudioDevice] {
        var seen = Set<String>()
        return devices.filter { $0.isConnected && seen.insert("\($0.type.rawValue):\($0.uid)").inserted }
    }

    func setVolume(_ newVolume: Float) {
        guard currentOutputSupportsSystemVolumeControl else { return }
        // Reaching for the slider is the clearest "let sound out" there is, so
        // it drops the mute-all latch rather than fighting it.
        if newVolume > MuteLedger.silenceThreshold {
            ledger.pinLatchAsIntents(connectedOutputsForControl.map(\.muteKey))
            isMuteAllActive = false
            if let device = currentOutputDevice {
                ledger.setIntent(muted: false, for: device.muteKey)
                _ = deviceService.setDeviceMuted(false, deviceId: device.id, type: .output)
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

    func setRedirectMuteAllToBuiltIn(_ enabled: Bool) {
        redirectMuteAllToBuiltIn = enabled
        priorityManager.redirectMuteAllToBuiltIn = enabled
    }

    func setKeepApplicationInForegroundAfterSourceChange(_ enabled: Bool) {
        keepApplicationInForegroundAfterSourceChange = enabled
        priorityManager.keepApplicationInForegroundAfterSourceChange = enabled
    }

    func setEnormousMode(_ enabled: Bool) {
        isEnormousMode = enabled
        priorityManager.isEnormousMode = enabled
    }

    var allConnectedOutputDevices: [AudioDevice] {
        uniquedForControl(connectedOutputsForControl)
    }

    var areAllOutputsMuted: Bool {
        // The latch answers first. Waiting for every device to agree means a
        // display that ignores CoreAudio can keep the button saying "Mute All"
        // forever, with no way to undo what did get muted.
        if ledger.allOutputsEngaged { return true }
        let devices = allConnectedOutputDevices
        return !devices.isEmpty && devices.allSatisfy { isDeviceMuted($0) }
    }

    var allConnectedInputDevices: [AudioDevice] {
        uniquedForControl(connectedInputsForControl)
    }

    var areAllInputsMuted: Bool {
        if ledger.allInputsEngaged { return true }
        let devices = allConnectedInputDevices
        return !devices.isEmpty && devices.allSatisfy { isDeviceMuted($0) }
    }

    func setAllOutputsMuted(_ muted: Bool) {
        isMuteAllActive = muted
        if muted {
            ledger.engageAllOutputs()
            for device in connectedOutputsForControl {
                silence(device)
            }
            if redirectMuteAllToBuiltIn {
                redirectOutputIfItWillNotMute()
            }
        } else {
            ledger.releaseAllOutputsAndIntents()
            for device in connectedOutputsForControl {
                restore(device)
            }
            returnOutputAfterMuteAll()
        }
        // Volume first: the mute summary reads the level, and refreshing them
        // the other way round published a status computed from a stale value.
        refreshVolume()
        refreshMuteStatus()
    }

    func setAllInputsMuted(_ muted: Bool) {
        if muted {
            ledger.engageAllInputs()
        } else {
            ledger.releaseAllInputs()
        }
        for device in allConnectedInputDevices {
            if muted {
                silence(device)
            } else {
                restore(device)
            }
        }
        refreshInputGain()
        refreshMuteStatus()
    }

    /// Toggles one device from its own row. Muting a device the user is not
    /// listening to is a normal thing to want, so this never changes which
    /// device is selected.
    func toggleMute(for device: AudioDevice) {
        guard device.isConnected else { return }
        if isDeviceMuted(device) || ledger.wantsMuted(device.muteKey) {
            if device.type == .output {
                // Letting one device through is not the same as undoing Mute
                // All, so the rest keep their mute as an explicit intent.
                ledger.pinLatchAsIntents(connectedOutputsForControl.map(\.muteKey))
                isMuteAllActive = false
            }
            restore(device)
        } else {
            ledger.setIntent(muted: true, for: device.muteKey)
            silence(device)
        }
        refreshVolume()
        refreshInputGain()
        refreshMuteStatus()
    }

    /// Mute All has to end in silence, and some hardware will not cooperate:
    /// displays accept the write and keep playing, interfaces run their own
    /// volume. But macOS only ever sends audio to the default output, so
    /// moving the default onto a device that *does* mute silences the machine
    /// even when the device you were using cannot be silenced.
    ///
    /// The original output is remembered and handed back on Unmute All.
    private func redirectOutputIfItWillNotMute() {
        guard let current = currentOutputDevice,
              ledger.isKnownAudibleDespiteIntent(current.muteKey),
              let fallback = silenceableFallback(excluding: current) else { return }

        outputBeforeMuteAll = current.uid
        deviceService.setDefaultDevice(fallback.id, type: .output)
        currentOutputId = fallback.id
        // Becoming the default can undo the mute, so assert it again.
        silence(fallback)
        redirectedToUID = fallback.uid
        redirectedOutputName = fallback.name
    }

    /// Every connected output was just asked to mute, so the ledger already
    /// knows which ones actually went quiet. Prefer the Mac's own output: it is
    /// always there, and it always mutes.
    private func silenceableFallback(excluding current: AudioDevice) -> AudioDevice? {
        let candidates = connectedOutputsForControl
            .filter { $0.uid != current.uid && ledger.outcome(for: $0.muteKey) == .silenced }
        return candidates.first(where: \.isBuiltIn) ?? candidates.first
    }

    /// Puts the output back where the user had it, unless they have since moved
    /// it themselves.
    private func returnOutputAfterMuteAll() {
        defer {
            outputBeforeMuteAll = nil
            redirectedToUID = nil
            redirectedOutputName = nil
        }
        guard let previousUID = outputBeforeMuteAll,
              let redirectedToUID,
              currentOutputDevice?.uid == redirectedToUID,
              let previous = connectedOutputsForControl.first(where: { $0.uid == previousUID }) else { return }

        deviceService.setDefaultDevice(previous.id, type: .output)
        currentOutputId = previous.id
        restore(previous)
    }

    /// Asks the hardware to go quiet and records whether it actually did.
    @discardableResult
    private func silence(_ device: AudioDevice) -> MuteOutcome {
        let key = device.muteKey
        if let current = deviceService.readDeviceVolume(device.id, type: device.type) {
            ledger.saveLevel(current, for: key)
        } else if let stored = priorityManager.deviceLevel(for: device.uid) {
            // Unreadable level: fall back to the remembered one so unmuting has
            // something better than a guess to return to.
            ledger.saveLevel(stored, for: key)
        }

        let muteAccepted = deviceService.setDeviceMuted(true, deviceId: device.id, type: device.type)
        let volumeAccepted = deviceService.setDeviceVolume(0, deviceId: device.id, type: device.type, force: true)
        let outcome: MuteOutcome = (muteAccepted || volumeAccepted) ? .silenced : .refused
        ledger.record(outcome, for: key)
        return outcome
    }

    /// Brings a device back to a level the user can hear.
    private func restore(_ device: AudioDevice) {
        let key = device.muteKey
        ledger.setIntent(muted: false, for: key)
        _ = deviceService.setDeviceMuted(false, deviceId: device.id, type: device.type)
        let restored = MuteLedger.usableRestoredVolume(
            saved: ledger.takeSavedLevel(for: key),
            current: deviceService.readDeviceVolume(device.id, type: device.type),
            fallback: device.type == .output ? volume : inputGain
        )
        _ = deviceService.setDeviceVolume(restored, deviceId: device.id, type: device.type, force: true)
        if device.type == .output, device.id == currentOutputId {
            deviceService.setOutputVolume(restored, force: true)
            volume = restored
        }
        if device.type == .input, device.id == currentInputId {
            deviceService.setInputVolume(restored, force: true)
            inputGain = restored
        }
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
        redirectMuteAllToBuiltIn = priorityManager.redirectMuteAllToBuiltIn
        keepApplicationInForegroundAfterSourceChange = priorityManager.keepApplicationInForegroundAfterSourceChange
        refreshDevices()
        previousConnectedUIDs = connectedDeviceUIDs  // Initialize tracking
        refreshVolume()
        refreshInputGain()
        refreshMuteStatus()
        // A mute-all latch is intentionally in-memory, but the hardware can
        // still be muted when the app is relaunched. Reconstruct the published
        // presentation state so the menu-bar icon matches what the user sees.
        isMuteAllActive = areAllOutputsMuted
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
        adoptExternalUnmutes()
        refreshVolume()
        refreshInputGain()
        refreshMuteStatus()
    }

    /// CoreAudio also reports volume changes the app did not make: the volume
    /// keys, System Settings, a device's own knob. If something we silenced is
    /// audible again, the user wanted that, so let go of the intent rather than
    /// re-muting behind their back.
    ///
    /// A device that refused the mute never went quiet, so its level says
    /// nothing about intent and is deliberately excluded.
    private func adoptExternalUnmutes() {
        for device in connectedOutputsForControl + connectedInputsForControl {
            let key = device.muteKey
            guard ledger.wantsMuted(key) else { continue }
            guard let level = deviceService.readDeviceVolume(device.id, type: device.type) else { continue }
            guard !deviceService.isDeviceMuted(device.id, type: device.type) else { continue }
            guard ledger.externalUnmuteDetected(for: key, level: level) else { continue }
            if device.type == .output {
                ledger.releaseAllOutputs()
                isMuteAllActive = false
            }
            ledger.setIntent(muted: false, for: key)
        }
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
        let sourceChanged = device.id != currentInputId
        applyInputDevice(device)
        if sourceChanged { keepApplicationInForegroundIfNeeded() }
    }

    func setOutputDevice(_ device: AudioDevice) {
        let sourceChanged = device.id != currentOutputId
        applyOutputDevice(device)
        if sourceChanged { keepApplicationInForegroundIfNeeded() }
    }

    /// Select an output and its category as one operation. Changing the mode
    /// first would briefly apply priority-one output, which is visible as a
    /// bounce and can override combined input/output devices such as USB
    /// microphones with headphone outputs.
    func selectOutputDevice(_ device: AudioDevice, category: OutputCategory, applyMode: Bool = true) {
        let sourceChanged = device.id != currentOutputId
        activateOutput(device, category: category, applyMode: applyMode, silent: false)
        if sourceChanged { keepApplicationInForegroundIfNeeded() }
    }

    /// With the panel kept open, clicking a device walks it through three
    /// states: neutral, active but silent, then active and audible. When the
    /// panel closes after a source change, the first click is a complete,
    /// audible selection.
    ///
    /// Landing on a device silent is the point — choosing an output can then
    /// never blast sound at you, and the second click is the one that commits.
    func cycleOutputPresentation(_ device: AudioDevice, category: OutputCategory, applyMode: Bool = true) {
        let previousOutputId = currentOutputId
        let keepPanelOpen = keepApplicationInForegroundAfterSourceChange

        // When the panel is going to close immediately, a source selection is
        // a complete action. Do not leave the user on a newly selected but
        // silent output they can no longer see.
        if !keepPanelOpen, device.id != currentOutputId {
            activateOutput(device, category: category, applyMode: applyMode, silent: false)
            return
        }

        switch outputPresentation(for: device) {
        case .unselected:
            activateOutput(device, category: category, applyMode: applyMode, silent: true)
        case .muted:
            toggleMute(for: device)
        case .unmuted:
            // Third click parks this device and hands over to the next one in
            // the list, also silent. With nowhere to hand over to, fall back to
            // muting so the click is never dead.
            if let next = nextConnectedOutput(after: device, in: category) {
                activateOutput(next, category: category, applyMode: applyMode, silent: keepPanelOpen)
            } else {
                toggleMute(for: device)
            }
        }
        if currentOutputId != previousOutputId { keepApplicationInForegroundIfNeeded() }
    }

    private func keepApplicationInForegroundIfNeeded() {
        guard keepApplicationInForegroundAfterSourceChange else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.keyWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func nextConnectedOutput(after device: AudioDevice, in category: OutputCategory) -> AudioDevice? {
        let pool = (category == .headphone ? headphoneDevices : speakerDevices)
            .filter { $0.isConnected && !priorityManager.isNeverUse($0) }
        guard pool.count > 1, let index = pool.firstIndex(where: { $0.uid == device.uid }) else { return nil }
        return pool[(index + 1) % pool.count]
    }

    private func activateOutput(_ device: AudioDevice, category: OutputCategory, applyMode: Bool, silent: Bool) {
        if applyMode {
            currentMode = category
            priorityManager.currentMode = category
        }
        if silent, let outgoing = currentOutputDevice, outgoing.uid != device.uid {
            // Do not let the first, protective click on every device leave a
            // trail of mutes. Preserve explicit mute-button choices, but drop
            // only the intent created by selecting the previous device.
            ledger.setSelectionIntent(muted: false, for: outgoing.muteKey)
        }
        if silent {
            ledger.setSelectionIntent(muted: true, for: device.muteKey)
        }
        applyOutputDevice(device, makeAudible: !silent)
    }

    func outputPresentation(for device: AudioDevice) -> OutputPresentation {
        guard device.id == currentOutputId else { return .unselected }
        return isDeviceMuted(device) ? .muted : .unmuted
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
        // Never record a muted device's zero as its remembered level, or the
        // next switch back restores silence.
        if let outgoing = currentOutputDevice, !isDeviceMuted(outgoing) {
            saveLevel(deviceService.getDeviceVolume(outgoing.id), for: outgoing.id, type: .output)
        }
        deviceService.setDefaultDevice(device.id, type: .output)
        currentOutputId = device.id
        if makeAudible {
            ledger.pinLatchAsIntents(connectedOutputsForControl.map(\.muteKey))
            isMuteAllActive = false
            makeOutputAudible(device)
        } else if ledger.wantsMuted(device.muteKey) {
            // "Keep muted when switching" is on: the device the user picked
            // stays silent instead of surprising them with sound.
            silence(device)
        } else {
            restoreLevel(for: currentOutputId, type: .output)
        }
        refreshVolume()
        refreshMuteStatus()
    }

    private func makeOutputAudible(_ device: AudioDevice) {
        let key = device.muteKey
        ledger.setIntent(muted: false, for: key)
        _ = deviceService.setDeviceMuted(false, deviceId: device.id, type: .output)
        let restored = MuteLedger.usableRestoredVolume(
            saved: perDeviceLevelsEnabled
                ? (priorityManager.deviceLevel(for: device.uid) ?? ledger.takeSavedLevel(for: key))
                : ledger.takeSavedLevel(for: key),
            current: deviceService.readDeviceVolume(device.id, type: .output),
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
