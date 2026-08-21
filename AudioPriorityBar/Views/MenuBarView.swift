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

    private let popoverWidth: CGFloat = 480
    private let listHeight: CGFloat = 480
    private let gutter: CGFloat = 16

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
            EnormousDeviceGrid(
                title: "Speakers",
                icon: "speaker.wave.2.fill",
                devices: audioManager.speakerDevices,
                currentDeviceId: audioManager.currentOutputId,
                category: .speaker,
                showCategoryPicker: true,
                onSelect: { audioManager.selectOutputDevice($0, category: .speaker, applyMode: false) },
                onCycle: { audioManager.cycleOutputPresentation($0, category: .speaker) },
                onMove: audioManager.moveSpeakerDevice,
                onHide: { audioManager.hideDevice($0, category: .speaker) }
            )
            EnormousDeviceGrid(
                title: "Headphones",
                icon: "headphones",
                devices: audioManager.headphoneDevices,
                currentDeviceId: audioManager.currentOutputId,
                category: .headphone,
                showCategoryPicker: true,
                onSelect: { audioManager.selectOutputDevice($0, category: .headphone, applyMode: false) },
                onCycle: { audioManager.cycleOutputPresentation($0, category: .headphone) },
                onMove: audioManager.moveHeadphoneDevice,
                onHide: { audioManager.hideDevice($0, category: .headphone) }
            )
            EnormousDeviceGrid(
                title: "Microphones",
                icon: "mic.fill",
                devices: audioManager.inputDevices,
                currentDeviceId: audioManager.currentInputId,
                onSelect: audioManager.setInputDevice,
                onMove: audioManager.moveInputDevice,
                onHide: { audioManager.hideDevice($0, category: nil) }
            )
        } else {
            EnormousDeviceGrid(
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
                        audioManager.selectOutputDevice(device, category: selectedTab == .speaker ? .speaker : .headphone)
                    }
                },
                onCycle: selectedTab == .microphone ? nil : { device in
                    audioManager.cycleOutputPresentation(
                        device,
                        category: selectedTab == .speaker ? .speaker : .headphone
                    )
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

struct EnormousDeviceGrid: View {
    @EnvironmentObject var audioManager: AudioManager
    var title: String? = nil
    let icon: String
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    var category: OutputCategory? = nil
    var showCategoryPicker: Bool = false
    let onSelect: (AudioDevice) -> Void
    var onCycle: ((AudioDevice) -> Void)? = nil
    var onMove: ((IndexSet, Int) -> Void)? = nil
    var onHide: ((AudioDevice) -> Void)? = nil

    @State private var dropTargetUID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }

            if devices.isEmpty {
                Text("No devices connected")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 12) {
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
        let isDropTarget = dropTargetUID == device.uid
        return HStack(spacing: 16) {
            Image(systemName: cardIcon(for: device, isMuted: isMuted))
                .font(.system(size: 24))
                .frame(width: 48)

            DeviceDragHandle(
                index: index,
                uid: device.uid,
                isLarge: true,
                foreground: isSelected ? .white : .secondary
            )

            Text(device.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
            }
        }
        .foregroundColor(isSelected ? .white : .primary)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                DropIndicatorLine()
                    .padding(.horizontal, 8)
                    .offset(y: -8)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onCycle?(device)
        }
        .onTapGesture(count: 1) {
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
        guard onCycle != nil else { return "Click to listen. Drag the numbered handle to reorder." }
        if !isSelected {
            return "Click to listen. Double-click cycles mute, then switch away."
        }
        if isMuted {
            return "Muted. Double-click to switch to another device."
        }
        return "Click to listen. Double-click to mute."
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

    private func cardIcon(for device: AudioDevice, isMuted: Bool) -> String {
        if isMuted {
            return device.type == .input ? "mic.slash.fill" : "speaker.slash.fill"
        }
        return icon
    }
}

struct MuteAllButton: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        Button {
            audioManager.setAllOutputsMuted(!audioManager.areAllOutputsMuted)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: audioManager.areAllOutputsMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 32, height: 30)

                Text(audioManager.areAllOutputsMuted ? "Unmute All Output" : "Mute All Output")
                    .font(.system(size: 23, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(audioManager.areAllOutputsMuted ? Color.green : Color.red)
            )
        }
        .buttonStyle(.plain)
        .animation(nil, value: audioManager.areAllOutputsMuted)
        .disabled(audioManager.allConnectedOutputDevices.isEmpty)
        .help(audioManager.areAllOutputsMuted ? "Unmute all output" : "Mute all output")
    }
}

struct MuteMicrophonesButton: View {
    @EnvironmentObject var audioManager: AudioManager

    static func iconName(isMuted: Bool) -> String {
        isMuted ? "mic.slash.fill" : "mic.fill"
    }

    var body: some View {
        Button {
            audioManager.setAllInputsMuted(!audioManager.areAllInputsMuted)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: Self.iconName(isMuted: audioManager.areAllInputsMuted))
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 32, height: 30)

                Text(audioManager.areAllInputsMuted ? "Unmute All Microphones" : "Mute All Microphones")
                    .font(.system(size: 23, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(audioManager.areAllInputsMuted ? Color.green : Color.orange)
            )
        }
        .buttonStyle(.plain)
        .disabled(audioManager.allConnectedInputDevices.isEmpty)
        .help(audioManager.areAllInputsMuted ? "Unmute all microphones" : "Mute all microphones")
    }
}

struct OutputMuteStatusView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(audioManager.allConnectedOutputDevices.isEmpty ? Color.secondary : (audioManager.areAllOutputsMuted ? Color.red : Color.green))
                .frame(width: 12, height: 12)

            Text(statusText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private var statusText: String {
        if audioManager.allConnectedOutputDevices.isEmpty {
            return "No output connected"
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
                title: "Remember volume per device",
                subtitle: "Restore each device’s last level when you switch",
                isOn: Binding(
                    get: { audioManager.perDeviceLevelsEnabled },
                    set: { audioManager.setPerDeviceLevelsEnabled($0) }
                )
            )

            SettingsToggleRow(
                title: "Keep muted when switching",
                subtitle: "Stay muted when you select another speaker or headphone. Off means the device you pick comes up live.",
                isOn: Binding(
                    get: { audioManager.keepMutedWhenChangingSelection },
                    set: { audioManager.setKeepMutedWhenChangingSelection($0) }
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
                            .font(.system(size: 18))
                        Text(tab.label)
                            .font(.system(size: 17, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 17)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10)
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
                    .font(.system(size: 18))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 17)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(audioManager.isCustomMode ? Color.orange : Color.clear)
                    )
                    .foregroundColor(audioManager.isCustomMode ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .help("Manual — choose devices yourself")
            .accessibilityLabel("Manual")
        }
        .padding(4)
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: 12)
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
        VolumeSliderView.showsMutedIcon(volume: audioManager.volume)
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
