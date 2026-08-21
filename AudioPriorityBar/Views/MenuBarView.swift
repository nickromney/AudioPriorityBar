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

enum MenuBarPresentation {
    case menuBar
    case workspace
}

struct MenuBarView: View {
    @EnvironmentObject var audioManager: AudioManager
    let presentation: MenuBarPresentation
    @State private var selectedTab: DeviceTab = .speaker
    @State private var showingSettings = false

    init(presentation: MenuBarPresentation = .menuBar) {
        self.presentation = presentation
    }

    private var usesLargeLayout: Bool {
        presentation == .workspace || audioManager.isEnormousMode
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                SettingsPanel(showingSettings: $showingSettings)
            } else {
            // Header with mode toggle and volume
            VStack(spacing: 14) {
                ModeToggleView(selectedTab: $selectedTab)
                if selectedTab == .microphone && !audioManager.isCustomMode {
                    if audioManager.currentInputSupportsSystemVolumeControl {
                        InputGainSliderView()
                    } else {
                        HardwareLevelNotice(text: "Use the device controls for level")
                    }
                } else {
                    if audioManager.currentOutputSupportsSystemVolumeControl {
                        VolumeSliderView()
                    } else {
                        HardwareLevelNotice(text: "Use the device controls for volume")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))

            Divider()
                .padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 20) {
                    if usesLargeLayout {
                        EnormousDeviceGrid(
                            icon: selectedTab.icon,
                            devices: selectedTab == .speaker ? audioManager.speakerDevices :
                                (selectedTab == .headphone ? audioManager.headphoneDevices : audioManager.inputDevices),
                            currentDeviceId: selectedTab == .microphone ? audioManager.currentInputId : audioManager.currentOutputId,
                            onSelect: { device in
                                if selectedTab == .microphone {
                                    audioManager.setInputDevice(device)
                                } else {
                                    audioManager.selectOutputDevice(device, category: selectedTab == .speaker ? .speaker : .headphone)
                                }
                            }
                        )
                    } else {
                    // Speakers (show in speaker mode or custom mode)
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

                    // Headphones (show in headphone mode or custom mode)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            // Keep the popover geometry stable while switching tabs. The list
            // scrolls inside this fixed-height viewport instead of resizing the
            // menu-bar window around each tab's content.
            .frame(height: usesLargeLayout ? enormousDeviceListHeight : 420)

            Divider()
                .padding(.horizontal, 12)
            }

            // Footer: settings get their own full-width rows so the final
            // action row remains calm and readable.
            VStack(spacing: 6) {
                if showingSettings {
                    Button {
                        showingSettings = false
                    } label: {
                        Label("Back to controls", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                } else {
                    if !audioManager.isEditMode {
                        HiddenDevicesToggleView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    if presentation == .menuBar {
                        Button {
                            WorkspaceWindowController.shared.show(audioManager: audioManager)
                        } label: {
                            Label("Open Large Window", systemImage: "macwindow.on.rectangle")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Spacer()

                    // Edit mode toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            audioManager.toggleEditMode()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: audioManager.isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                                .font(.system(size: 12))
                            Text(audioManager.isEditMode ? "Done" : "Edit")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(audioManager.isEditMode ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: audioManager.isEditMode)

                    // Quit is deliberately labelled; an unlabeled close icon
                    // is too easy to mistake for dismissing the popover.
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit AudioPriorityBar")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Quit AudioPriorityBar")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.2), value: audioManager.isEditMode)

            if !showingSettings {
                if usesLargeLayout {
                    VStack(spacing: 12) {
                        OutputMuteStatusView()
                        MuteAllButton()
                        MuteMicrophonesButton()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                } else {
                    CompactEmergencyControlsView()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
            }
        }
        .frame(width: usesLargeLayout ? 560 : 340)
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var enormousDeviceListHeight: CGFloat {
        guard usesLargeLayout else { return 420 }

        // Size from the largest category, not the selected tab. This keeps
        // the emergency controls anchored while switching between tabs.
        let largestDeviceCount = max(
            audioManager.speakerDevices.count,
            audioManager.headphoneDevices.count,
            audioManager.inputDevices.count
        )
        return max(320, CGFloat(largestDeviceCount) * 96 + 28)
    }
}

struct EnormousDeviceGrid: View {
    @EnvironmentObject var audioManager: AudioManager
    let icon: String
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onSelect: (AudioDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if devices.isEmpty {
                Text("No connected devices")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        let isSelected = device.id == currentDeviceId
                        Button {
                            onSelect(device)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: cardIcon(for: device, isSelected: isSelected))
                                    .font(.system(size: 24))
                                .frame(width: 48)

                                Text("\(index + 1)")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .frame(width: 24)

                                Text(device.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Spacer(minLength: 0)
                            }
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func cardIcon(for device: AudioDevice, isSelected: Bool) -> String {
        if isSelected {
            return "checkmark.circle.fill"
        }
        if audioManager.isDeviceMuted(device) {
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

                Text(audioManager.areAllOutputsMuted ? "Unmute All Audio Output" : "Mute All Audio Output")
                    .font(.system(size: 23, weight: .bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 360, alignment: .leading)
                Spacer()
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
        .help(audioManager.areAllOutputsMuted ? "Unmute all audio output" : "Mute all audio output")
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
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 360, alignment: .leading)

                Spacer()
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

struct CompactEmergencyControlsView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                CompactMuteButton(
                    title: audioManager.areAllOutputsMuted ? "Unmute All Audio Output" : "Mute All Audio Output",
                    icon: audioManager.areAllOutputsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    color: audioManager.areAllOutputsMuted ? .green : .red,
                    isDisabled: audioManager.allConnectedOutputDevices.isEmpty,
                    action: { audioManager.setAllOutputsMuted(!audioManager.areAllOutputsMuted) }
                )

                CompactMuteButton(
                    title: audioManager.areAllInputsMuted ? "Unmute All Microphones" : "Mute All Microphones",
                    icon: audioManager.areAllInputsMuted ? "mic.slash.fill" : "mic.fill",
                    color: audioManager.areAllInputsMuted ? .green : .orange,
                    isDisabled: audioManager.allConnectedInputDevices.isEmpty,
                    action: { audioManager.setAllInputsMuted(!audioManager.areAllInputsMuted) }
                )
            }
        }
        .padding(.top, 4)
    }
}

private struct CompactMuteButton: View {
    let title: String
    let icon: String
    let color: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundColor(color)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
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
            return "No audio output available"
        }
        return audioManager.areAllOutputsMuted ? "Audio output is muted" : "Audio output is available"
    }
}

struct SettingsPanel: View {
    @EnvironmentObject var audioManager: AudioManager
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
            }

            Divider()

            HStack(spacing: 8) {
                ControlModeChoice(
                    title: "Enormous controls",
                    descriptor: "Large emergency controls",
                    isSelected: audioManager.isEnormousMode,
                    action: { audioManager.setEnormousMode(true) }
                )
                ControlModeChoice(
                    title: "Subtle controls",
                    descriptor: "Compact controls",
                    isSelected: !audioManager.isEnormousMode,
                    action: { audioManager.setEnormousMode(false) }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Show first")
                    .font(.system(size: 16, weight: .semibold))
                Picker("Show first", selection: Binding(
                    get: { audioManager.defaultOutputCategory },
                    set: { audioManager.defaultOutputCategory = $0 }
                )) {
                    Text("Speakers").tag(OutputCategory.speaker)
                    Text("Headphones").tag(OutputCategory.headphone)
                }
                .pickerStyle(.segmented)
            }

            PerDeviceLevelsToggle()
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, alignment: .leading)

            LaunchAtLoginToggle()
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(24)
        .frame(height: 420, alignment: .top)
    }
}

private struct ControlModeChoice: View {
    let title: String
    let descriptor: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(descriptor)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .primary.opacity(0.75) : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                            .font(.system(size: audioManager.isEnormousMode ? 18 : 11))
                        Text(tab.label)
                            .font(.system(size: audioManager.isEnormousMode ? 17 : 11, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, audioManager.isEnormousMode ? 12 : 7)
                    .padding(.vertical, audioManager.isEnormousMode ? 17 : 8)
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
                    .font(.system(size: audioManager.isEnormousMode ? 18 : 12))
                    .padding(.horizontal, audioManager.isEnormousMode ? 18 : 12)
                    .padding(.vertical, audioManager.isEnormousMode ? 17 : 8)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(audioManager.isCustomMode ? Color.orange : Color.clear)
                    )
                    .foregroundColor(audioManager.isCustomMode ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .help("Manual mode - disable auto-switching")
        }
        .padding(4)
        .frame(height: audioManager.isEnormousMode ? 70 : 36)
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
        audioManager.volume <= 0 || audioManager.isActiveOutputMuted
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

struct PerDeviceLevelsToggle: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                audioManager.setPerDeviceLevelsEnabled(!audioManager.perDeviceLevelsEnabled)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: audioManager.perDeviceLevelsEnabled ? "slider.horizontal.3" : "slider.horizontal.3")
                    .font(.system(size: 12))
                Text("Remember levels per device")
                    .font(.system(size: 11, weight: .medium))
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(audioManager.perDeviceLevelsEnabled ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(audioManager.perDeviceLevelsEnabled
            ? "Disable remembering volume and microphone levels per device"
            : "Remember volume and microphone levels separately for each device")
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
                Text("No devices")
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
            Text("")
                .frame(height: 1)
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11))
                    Text("\(allHiddenDevices.count) ignored")
                        .font(.system(size: 12))
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(.secondary)
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
                .help("Stop ignoring")
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

struct LaunchAtLoginToggle: View {
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    
    var body: some View {
        if launchManager.canManageLaunchAtLogin {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    launchManager.isEnabled.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: launchManager.isEnabled ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 12))
                    Text("Automatically start at login")
                        .font(.system(size: 11, weight: .medium))
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(launchManager.isEnabled ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(launchManager.isEnabled ? "Do not open at startup" : "Open at startup")
        }
    }
}
