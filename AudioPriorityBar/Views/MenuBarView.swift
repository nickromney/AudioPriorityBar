import SwiftUI
import CoreAudio
import AppKit

enum DeviceTab: Hashable {
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

struct MenuBarView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var selectedTab: DeviceTab = .speaker
    @State private var showingSettings = false

    private let popoverWidth = PanelMetrics.width
    private let listHeight: CGFloat = 460
    private let gutter = PanelMetrics.gutter

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                SettingsPanel()
                    .frame(height: listHeight)
            } else {
            // Header with mode toggle and volume
            VStack(spacing: 14) {
                ModeToggleView(selectedTab: $selectedTab)
                if selectedTab == .microphone && !audioManager.isCustomMode {
                    if audioManager.currentInputSupportsSystemVolumeControl {
                        InputGainSliderView()
                    } else {
                        HardwareLevelNotice(text: "Use this device’s hardware controls")
                    }
                } else {
                    if audioManager.currentOutputSupportsSystemVolumeControl {
                        VolumeSliderView()
                    } else {
                        HardwareLevelNotice(text: "Use this device’s hardware controls")
                    }
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))

            Divider()
                .padding(.horizontal, gutter)

            ScrollView {
                VStack(spacing: 20) {
                    deviceListContent
                }
                .padding(.vertical, 14)
            }
            .padding(.horizontal, gutter)
            .frame(height: listHeight)

            Divider()
                .padding(.horizontal, gutter)
            }

            BottomChrome(showingSettings: $showingSettings)
        }
        .frame(width: popoverWidth)
        .onAppear {
            selectedTab = audioManager.defaultOutputCategory == .headphone ? .headphone : .speaker
        }
        .onChange(of: audioManager.currentMode) { mode in
            if !audioManager.isCustomMode {
                selectedTab = mode == .headphone ? .headphone : .speaker
            }
        }
        // Keep the MenuBarExtra window intrinsic. On newer macOS releases a
        // ScrollView with only a max height can otherwise collapse to zero.
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var deviceListContent: some View {
        if audioManager.isEditMode {
            compactDeviceSections
        } else if audioManager.isCustomMode {
            DeviceCardList(
                title: "Speakers",
                icon: "speaker.wave.2.fill",
                devices: audioManager.speakerDevices,
                currentDeviceId: audioManager.currentOutputId,
                category: .speaker,
                showCategoryPicker: true,
                onSelect: { audioManager.cycleOutputPresentation($0, category: .speaker, applyMode: false) },
                onMove: audioManager.moveSpeakerDevice,
                onHide: { audioManager.hideDevice($0, category: .speaker) }
            )
            DeviceCardList(
                title: "Headphones",
                icon: "headphones",
                devices: audioManager.headphoneDevices,
                currentDeviceId: audioManager.currentOutputId,
                category: .headphone,
                showCategoryPicker: true,
                onSelect: { audioManager.cycleOutputPresentation($0, category: .headphone, applyMode: false) },
                onMove: audioManager.moveHeadphoneDevice,
                onHide: { audioManager.hideDevice($0, category: .headphone) }
            )
            DeviceCardList(
                title: "Microphones",
                icon: "mic.fill",
                devices: audioManager.inputDevices,
                currentDeviceId: audioManager.currentInputId,
                onSelect: audioManager.setInputDevice,
                onMove: audioManager.moveInputDevice,
                onHide: { audioManager.hideDevice($0, category: nil) }
            )
        } else {
            DeviceCardList(
                icon: selectedTab.icon,
                devices: selectedTab == .speaker ? audioManager.speakerDevices :
                    (selectedTab == .headphone ? audioManager.headphoneDevices : audioManager.inputDevices),
                currentDeviceId: selectedTab == .microphone ? audioManager.currentInputId : audioManager.currentOutputId,
                category: selectedTab == .speaker ? .speaker : (selectedTab == .headphone ? .headphone : nil),
                showCategoryPicker: selectedTab != .microphone,
                onSelect: { device in
                    if selectedTab == .microphone {
                        audioManager.setInputDevice(device)
                    } else {
                        audioManager.cycleOutputPresentation(device, category: selectedTab == .speaker ? .speaker : .headphone)
                    }
                },
                onMove: selectedTab == .speaker ? audioManager.moveSpeakerDevice :
                    (selectedTab == .headphone ? audioManager.moveHeadphoneDevice : audioManager.moveInputDevice),
                onHide: { device in
                    if selectedTab == .microphone {
                        audioManager.hideDevice(device, category: nil)
                    } else {
                        audioManager.hideDevice(device, category: selectedTab == .speaker ? .speaker : .headphone)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var compactDeviceSections: some View {
        if selectedTab == .speaker || audioManager.isCustomMode {
            DeviceSectionView(
                title: "Speakers",
                icon: "speaker.wave.2.fill",
                devices: audioManager.speakerDevices,
                currentDeviceId: audioManager.currentOutputId,
                onMove: audioManager.moveSpeakerDevice,
                onSelect: { device in
                    selectedTab = .speaker
                    audioManager.selectOutputDevice(device, category: .speaker, applyMode: !audioManager.isCustomMode)
                },
                onHide: { audioManager.hideDevice($0, category: .speaker) },
                onUnhide: { audioManager.unhideDevice($0, category: .speaker) },
                category: .speaker,
                showCategoryPicker: true,
                isActiveCategory: audioManager.currentMode == .speaker || audioManager.isCustomMode
            )
        }

        if selectedTab == .headphone || audioManager.isCustomMode {
            DeviceSectionView(
                title: "Headphones",
                icon: "headphones",
                devices: audioManager.headphoneDevices,
                currentDeviceId: audioManager.currentOutputId,
                onMove: audioManager.moveHeadphoneDevice,
                onSelect: { device in
                    selectedTab = .headphone
                    audioManager.selectOutputDevice(device, category: .headphone, applyMode: !audioManager.isCustomMode)
                },
                onHide: { audioManager.hideDevice($0, category: .headphone) },
                onUnhide: { audioManager.unhideDevice($0, category: .headphone) },
                category: .headphone,
                showCategoryPicker: true,
                isActiveCategory: audioManager.currentMode == .headphone || audioManager.isCustomMode
            )
        }

        if selectedTab == .microphone || audioManager.isCustomMode {
            DeviceSectionView(
                title: "Microphones",
                icon: "mic.fill",
                devices: audioManager.inputDevices,
                currentDeviceId: audioManager.currentInputId,
                onMove: audioManager.moveInputDevice,
                onSelect: audioManager.setInputDevice,
                onHide: { audioManager.hideDevice($0, category: nil) },
                onUnhide: { audioManager.unhideDevice($0, category: nil) },
                category: nil,
                showCategoryPicker: false
            )
        }
    }
}

/// One shared scale for the whole panel.
///
/// The controls had drifted into two unrelated sizes — 23pt emergency buttons
/// above an 11pt slider — which is what made a working panel look unfinished.
enum PanelMetrics {
    static let width: CGFloat = 480
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let cardMinHeight: CGFloat = 60
    static let controlHeight: CGFloat = 44
    static let tapTarget: CGFloat = 34
}

enum PanelType {
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let deviceName = Font.system(size: 15, weight: .medium)
    static let status = Font.system(size: 11)
    static let control = Font.system(size: 13, weight: .medium)
    static let emergency = Font.system(size: 15, weight: .semibold)
}

/// The main surface: one row per device, with selection and mute as two
/// separate controls.
struct DeviceCardList: View {
    @EnvironmentObject var audioManager: AudioManager
    var title: String? = nil
    let icon: String
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    var category: OutputCategory? = nil
    var showCategoryPicker: Bool = false
    let onSelect: (AudioDevice) -> Void
    var onMove: ((IndexSet, Int) -> Void)? = nil
    var onHide: ((AudioDevice) -> Void)? = nil

    @State private var dropTargetUID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(PanelType.sectionHeader)
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(PanelType.sectionHeader)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
            }

            if devices.isEmpty {
                Text("No devices connected")
                    .font(PanelType.control)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: PanelMetrics.cardMinHeight)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(devices.enumerated()), id: \.element.uid) { index, device in
                        deviceCard(index: index, device: device)
                    }
                }
            }
        }
    }

    private func deviceCard(index: Int, device: AudioDevice) -> some View {
        let isSelected = device.id == currentDeviceId
        let isMuted = audioManager.isDeviceMuted(device)
        let isIgnoringMute = audioManager.isDeviceIgnoringMute(device)
        let isDropTarget = dropTargetUID == device.uid

        return HStack(spacing: 12) {
            DeviceRankControl(
                index: index,
                uid: device.uid,
                count: devices.count,
                foreground: isSelected ? Color.white.opacity(0.85) : .secondary,
                onMove: onMove
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(PanelType.deviceName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let status = statusText(isSelected: isSelected, isMuted: isMuted, isIgnoringMute: isIgnoringMute) {
                    Text(status)
                        .font(PanelType.status)
                        .lineLimit(1)
                        .foregroundStyle(statusTint(isSelected: isSelected, isIgnoringMute: isIgnoringMute))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
            }

            muteButton(for: device, isMuted: isMuted, isIgnoringMute: isIgnoringMute, isSelected: isSelected)
        }
        .foregroundColor(isSelected ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: PanelMetrics.cardMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                DropIndicatorLine()
                    .padding(.horizontal, 8)
                    .offset(y: -6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        // One plain single click per state change. A double-click gesture used
        // to sit on top of this one and fire it first, so muting a device also
        // reselected it — the interaction that felt broken.
        .onTapGesture {
            onSelect(device)
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, onto: device)
        } isTargeted: { targeted in
            dropTargetUID = targeted ? device.uid : nil
        }
        .contextMenu {
            DeviceContextMenu(
                device: device,
                category: category,
                showCategoryPicker: showCategoryPicker,
                onHide: onHide
            )
        }
        .help(cardHelp(isSelected: isSelected, isMuted: isMuted))
    }

    private func cardHelp(isSelected: Bool, isMuted: Bool) -> String {
        if !isSelected { return "Click to make this the output, silent at first." }
        if isMuted { return "Click to unmute. Click again to hand over to the next device." }
        return "Click to hand over to the next device. The speaker icon mutes this one."
    }

    /// Muting a device is its own control so it never has to fight with
    /// selecting one.
    private func muteButton(for device: AudioDevice, isMuted: Bool, isIgnoringMute: Bool, isSelected: Bool) -> some View {
        Button {
            audioManager.toggleMute(for: device)
        } label: {
            Image(systemName: muteGlyph(for: device, isMuted: isMuted, isIgnoringMute: isIgnoringMute))
                .font(.system(size: 14))
                .frame(width: PanelMetrics.tapTarget, height: PanelMetrics.tapTarget)
                .background(
                    Circle().fill(isSelected ? Color.white.opacity(0.18) : Color.primary.opacity(0.07))
                )
                .foregroundStyle(muteTint(isMuted: isMuted, isIgnoringMute: isIgnoringMute, isSelected: isSelected))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!device.isConnected)
        .help(muteHelp(isMuted: isMuted, isIgnoringMute: isIgnoringMute))
    }

    private func muteGlyph(for device: AudioDevice, isMuted: Bool, isIgnoringMute: Bool) -> String {
        if isIgnoringMute { return "exclamationmark.triangle.fill" }
        if isMuted {
            return device.type == .input ? "mic.slash.fill" : "speaker.slash.fill"
        }
        return device.type == .input ? "mic.fill" : "speaker.wave.2.fill"
    }

    private func muteTint(isMuted: Bool, isIgnoringMute: Bool, isSelected: Bool) -> Color {
        if isIgnoringMute { return .orange }
        if isMuted { return isSelected ? .white : .red }
        return isSelected ? .white : .secondary
    }

    private func muteHelp(isMuted: Bool, isIgnoringMute: Bool) -> String {
        if isIgnoringMute { return "This device ignored the mute. Use its own volume control." }
        return isMuted ? "Unmute this device" : "Mute this device"
    }

    private func statusText(isSelected: Bool, isMuted: Bool, isIgnoringMute: Bool) -> String? {
        if isIgnoringMute { return "Still playing — use its own controls" }
        if isMuted { return "Muted" }
        if isSelected { return "Listening" }
        return nil
    }

    private func statusTint(isSelected: Bool, isIgnoringMute: Bool) -> Color {
        if isIgnoringMute { return .orange }
        return isSelected ? Color.white.opacity(0.85) : .secondary
    }

    private func drop(_ uids: [String], onto device: AudioDevice) -> Bool {
        guard let onMove,
              let draggedUID = uids.first,
              let move = DeviceReorder.move(
                draggingUID: draggedUID,
                ontoUID: device.uid,
                in: devices.map(\.uid)
              ) else { return false }
        onMove(move.from, move.to)
        return true
    }
}

/// The panic button. Sized to be hit without aiming, but no longer shouting
/// over the rest of the panel.
struct MuteAllButton: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        EmergencyButton(
            title: audioManager.areAllOutputsMuted ? "Unmute All Output" : "Mute All Output",
            systemImage: audioManager.areAllOutputsMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
            tint: audioManager.areAllOutputsMuted ? .green : .red,
            isDisabled: audioManager.allConnectedOutputDevices.isEmpty
        ) {
            audioManager.setAllOutputsMuted(!audioManager.areAllOutputsMuted)
        }
        .animation(nil, value: audioManager.areAllOutputsMuted)
    }
}

struct MuteMicrophonesButton: View {
    @EnvironmentObject var audioManager: AudioManager

    static func iconName(isMuted: Bool) -> String {
        isMuted ? "mic.slash.fill" : "mic.fill"
    }

    var body: some View {
        EmergencyButton(
            title: audioManager.areAllInputsMuted ? "Unmute All Microphones" : "Mute All Microphones",
            systemImage: Self.iconName(isMuted: audioManager.areAllInputsMuted),
            tint: audioManager.areAllInputsMuted ? .green : .orange,
            isDisabled: audioManager.allConnectedInputDevices.isEmpty
        ) {
            audioManager.setAllInputsMuted(!audioManager.areAllInputsMuted)
        }
    }
}

private struct EmergencyButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)

                Text(title)
                    .font(PanelType.emergency)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                    .fill(tint.opacity(isHovering ? 1 : 0.9))
            )
            .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.4 : 1)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .help(title)
    }
}

/// Says what is actually happening, including the case the app cannot fix:
/// hardware that was told to mute and kept playing.
struct OutputMuteStatusView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(PanelType.status)
                .foregroundColor(audioManager.outputsIgnoringMute.isEmpty ? .secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .help(statusText)
    }

    private var indicatorColor: Color {
        if audioManager.allConnectedOutputDevices.isEmpty { return .secondary }
        if audioManager.redirectedOutputName != nil { return .red }
        if !audioManager.outputsIgnoringMute.isEmpty { return .orange }
        return audioManager.areAllOutputsMuted ? .red : .green
    }

    private var statusText: String {
        if audioManager.allConnectedOutputDevices.isEmpty {
            return "No output connected"
        }
        if let redirected = audioManager.redirectedOutputName {
            return "Muted — audio moved to \(redirected) to guarantee silence"
        }
        let ignoring = audioManager.outputsIgnoringMute
        if !ignoring.isEmpty {
            let names = ignoring.joined(separator: ", ")
            return "\(names) ignored the mute — use its own volume control"
        }
        return audioManager.areAllOutputsMuted ? "Output is muted" : "Output is live"
    }
}

struct SettingsPanel: View {
    @EnvironmentObject var audioManager: AudioManager
    @StateObject private var launchManager = LaunchAtLoginManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings")
                .font(.system(size: 22, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Open to")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Open to", selection: Binding(
                    get: { audioManager.defaultOutputCategory },
                    set: { audioManager.defaultOutputCategory = $0 }
                )) {
                    Text("Speakers").tag(OutputCategory.speaker)
                    Text("Headphones").tag(OutputCategory.headphone)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SettingsToggleRow(
                title: "Switch to built-in output to mute",
                subtitle: "Some displays and audio interfaces ignore mute. Mute All moves audio to the built-in speakers and mutes those instead, then hands it back when you unmute.",
                isOn: Binding(
                    get: { audioManager.redirectMuteAllToBuiltIn },
                    set: { audioManager.setRedirectMuteAllToBuiltIn($0) }
                )
            )

            SettingsToggleRow(
                title: "Remember volume per device",
                subtitle: "Restore each device’s last level when you switch",
                isOn: Binding(
                    get: { audioManager.perDeviceLevelsEnabled },
                    set: { audioManager.setPerDeviceLevelsEnabled($0) }
                )
            )

            if launchManager.canManageLaunchAtLogin {
                SettingsToggleRow(
                    title: "Open at login",
                    subtitle: "Start Audio Priority Bar when you sign in",
                    isOn: $launchManager.isEnabled
                )
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.vertical, 4)
    }
}

private struct BottomChrome: View {
    @EnvironmentObject var audioManager: AudioManager
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(spacing: 6) {
            if !showingSettings {
                if !audioManager.isEditMode {
                    HiddenDevicesToggleView()
                }

                muteControls
            }

            actionGrid
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
        .animation(.easeInOut(duration: 0.2), value: audioManager.isEditMode)
    }

    @ViewBuilder
    private var muteControls: some View {
        VStack(spacing: 8) {
            OutputMuteStatusView()
            MuteAllButton()
            MuteMicrophonesButton()
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var actionGrid: some View {
        if showingSettings {
            HStack(spacing: 6) {
                backTile
                relaunchTile
                quitTile
            }
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    settingsTile
                    editTile
                }
                HStack(spacing: 6) {
                    relaunchTile
                    quitTile
                }
            }
        }
    }

    private var settingsTile: some View {
        ControlActionTile(title: "Settings", systemImage: "gearshape") {
            showingSettings = true
        }
    }

    private var editTile: some View {
        ControlActionTile(
            title: audioManager.isEditMode ? "Done" : "Edit",
            systemImage: audioManager.isEditMode ? "checkmark" : "pencil",
            prominence: audioManager.isEditMode ? .accent : .regular
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                audioManager.toggleEditMode()
            }
        }
        .help(audioManager.isEditMode ? "Finish editing" : "Reorder and hide devices")
    }

    private var backTile: some View {
        ControlActionTile(title: "Back", systemImage: "chevron.left", prominence: .accent) {
            showingSettings = false
        }
        .help("Back to controls")
    }

    private var relaunchTile: some View {
        ControlActionTile(title: "Relaunch", systemImage: "arrow.triangle.2.circlepath") {
            AppProcess.relaunch()
        }
        .help("Quit and open Audio Priority Bar again")
    }

    private var quitTile: some View {
        ControlActionTile(title: "Quit", systemImage: "power", prominence: .quiet) {
            NSApplication.shared.terminate(nil)
        }
        .help("Quit Audio Priority Bar")
    }
}

private struct ControlActionTile: View {
    let title: String
    let systemImage: String
    var prominence: Prominence = .regular
    let action: () -> Void
    @State private var isHovering = false

    enum Prominence {
        case regular
        case accent
        case quiet
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 10)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var foreground: Color {
        switch prominence {
        case .accent: return .accentColor
        case .quiet: return .secondary
        case .regular: return isHovering ? .primary : .secondary
        }
    }

    private var fill: Color {
        if prominence == .accent {
            return Color.accentColor.opacity(isHovering ? 0.18 : 0.12)
        }
        return Color.primary.opacity(isHovering ? 0.10 : 0.055)
    }
}

struct ModeToggleView: View {
    @EnvironmentObject var audioManager: AudioManager
    @Binding var selectedTab: DeviceTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach([DeviceTab.speaker, .headphone, .microphone], id: \.self) { tab in
                let isSelected = selectedTab == tab && !audioManager.isCustomMode
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                        if tab != .microphone {
                            if audioManager.isCustomMode {
                                audioManager.setCustomMode(false)
                            }
                            audioManager.setMode(tab == .speaker ? .speaker : .headphone)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.label)
                            .font(PanelType.control)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: PanelMetrics.controlRadius, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .foregroundColor(isSelected ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Custom mode toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    audioManager.setCustomMode(!audioManager.isCustomMode)
                }
            } label: {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: PanelMetrics.controlRadius, style: .continuous)
                            .fill(audioManager.isCustomMode ? Color.orange : Color.clear)
                    )
                    .foregroundColor(audioManager.isCustomMode ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .help("Manual — choose devices yourself")
            .accessibilityLabel("Manual")
        }
        .padding(4)
        .frame(height: PanelMetrics.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .animation(.easeInOut(duration: 0.2), value: audioManager.currentMode)
        .animation(.easeInOut(duration: 0.2), value: audioManager.isCustomMode)
    }
}

struct VolumeSliderView: View {
    @EnvironmentObject var audioManager: AudioManager

    var volumeIcon: String {
        if audioManager.currentMode == .headphone {
            return "headphones"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    var isMuted: Bool {
        // The app's own mute state comes first: a device that is muted but
        // parked at a non-zero level should still read as muted here.
        audioManager.isActiveOutputMuted || VolumeSliderView.showsMutedIcon(volume: audioManager.volume)
    }

    static func showsMutedIcon(volume: Float) -> Bool {
        volume <= 0.01
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: volumeIcon)
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)

                if isMuted {
                    Image(systemName: "line.diagonal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 20, height: 18)

            Slider(
                value: Binding(
                    get: { Double(audioManager.volume) },
                    set: { audioManager.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(.small)

            Text("\(Int(audioManager.volume * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 18, alignment: .trailing)
        }
        .frame(height: 20)
        .onScrollWheel { delta in
            let newVolume = audioManager.volume + Float(delta * 0.02)
            audioManager.setVolume(max(0, min(1, newVolume)))
        }
    }
}

struct InputGainSliderView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
                .frame(width: 20, height: 18)

            Slider(
                value: Binding(
                    get: { Double(audioManager.inputGain) },
                    set: { audioManager.setInputGain(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(.small)

            Text("\(Int(audioManager.inputGain * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 18, alignment: .trailing)
        }
        .frame(height: 20)
        .onScrollWheel { delta in
            let newGain = audioManager.inputGain + Float(delta * 0.02)
            audioManager.setInputGain(max(0, min(1, newGain)))
        }
    }
}

struct HardwareLevelNotice: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "dial.medium.fill")
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
                .frame(width: 20, height: 18)

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(height: 20)
    }
}

// Scroll wheel modifier
struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelReceiver(onScroll: onScroll)
        )
    }
}

struct ScrollWheelReceiver: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.deltaY)
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: action))
    }
}

struct DeviceSectionView: View {
    let title: String
    let icon: String
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?
    var onUnhide: ((AudioDevice) -> Void)?
    var category: OutputCategory?
    var showCategoryPicker: Bool = false
    var isActiveCategory: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isActiveCategory ? .accentColor : .secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            if devices.isEmpty {
                Text("No devices connected")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DeviceListView(
                    devices: devices,
                    currentDeviceId: currentDeviceId,
                    onMove: onMove,
                    onSelect: onSelect,
                    showCategoryPicker: showCategoryPicker,
                    onHide: onHide,
                    onUnhide: onUnhide,
                    category: category
                )
            }
        }
    }
}

struct HiddenDevicesToggleView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var isExpanded = false

    var allHiddenDevices: [AudioDevice] {
        audioManager.hiddenInputDevices +
        audioManager.hiddenSpeakerDevices +
        audioManager.hiddenHeadphoneDevices
    }

    var body: some View {
        if allHiddenDevices.isEmpty {
            EmptyView()
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16)
                    Text(allHiddenDevices.count == 1 ? "1 ignored device" : "\(allHiddenDevices.count) ignored devices")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allHiddenDevices, id: \.id) { device in
                        HiddenDeviceRow(device: device)
                    }
                }
                .padding(12)
                .frame(minWidth: 220)
            }
        }
    }
}

struct HiddenDeviceRow: View {
    @EnvironmentObject var audioManager: AudioManager
    let device: AudioDevice
    @State private var isHovering = false

    var deviceIcon: String {
        if device.type == .input {
            return "mic.fill"
        } else {
            let category = audioManager.priorityManager.getCategory(for: device)
            return category == .headphone ? "headphones" : "speaker.wave.2.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: deviceIcon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 18)

            Text(device.name)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isHovering {
                Button {
                    audioManager.unhideDevice(device)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show again")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
