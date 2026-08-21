import SwiftUI
import CoreAudio
import AppKit
import UniformTypeIdentifiers

struct DeviceContextMenu: View {
    @EnvironmentObject var audioManager: AudioManager
    let device: AudioDevice
    var category: OutputCategory? = nil
    var showCategoryPicker: Bool = false
    var onHide: ((AudioDevice) -> Void)? = nil
    var onUnhide: ((AudioDevice) -> Void)? = nil
    var isHiddenSection: Bool = false

    var body: some View {
        let ignored = isHiddenSection || audioManager.isDeviceIgnored(device, inCategory: category)

        if ignored {
            Button {
                if let onUnhide {
                    onUnhide(device)
                } else {
                    audioManager.unhideDevice(device, category: category)
                }
            } label: {
                Label("Show Again", systemImage: "eye")
            }
        } else {
            Button {
                if let onHide {
                    onHide(device)
                } else {
                    audioManager.hideDevice(device, category: category)
                }
            } label: {
                Label("Ignore This Device", systemImage: "eye.slash")
            }

            if device.type == .output {
                Button {
                    audioManager.hideDeviceEntirely(device)
                } label: {
                    Label("Ignore Entirely", systemImage: "eye.slash.fill")
                }
            }
        }

        if showCategoryPicker {
            Divider()
            Button {
                audioManager.setCategory(.speaker, for: device)
            } label: {
                Label("Move to Speakers", systemImage: "speaker.wave.2.fill")
            }
            Button {
                audioManager.setCategory(.headphone, for: device)
            } label: {
                Label("Move to Headphones", systemImage: "headphones")
            }
        }

        if device.isConnected {
            Divider()
            Button {
                audioManager.setNeverUse(device, neverUse: !audioManager.isNeverUse(device))
            } label: {
                if audioManager.isNeverUse(device) {
                    Label("Allow Use", systemImage: "checkmark.circle")
                } else {
                    Label("Never Use", systemImage: "nosign")
                }
            }
        }
    }
}

struct DeviceListView: View {
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var showCategoryPicker: Bool = false
    var onHide: ((AudioDevice) -> Void)?
    var onUnhide: ((AudioDevice) -> Void)?
    var isHiddenSection: Bool = false
    var category: OutputCategory? = nil

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(devices.enumerated()), id: \.element.uid) { index, device in
                DraggableDeviceRow(
                    device: device,
                    index: index,
                    isSelected: device.id == currentDeviceId,
                    onSelect: { onSelect(device) },
                    showCategoryPicker: showCategoryPicker,
                    onHide: onHide,
                    onUnhide: onUnhide,
                    isHiddenSection: isHiddenSection,
                    category: category,
                    onDropUID: { drop($0, onto: device) }
                )
            }
        }
    }

    private func drop(_ uid: String, onto device: AudioDevice) -> Bool {
        guard let move = DeviceReorder.move(
            draggingUID: uid,
            ontoUID: device.uid,
            in: devices.map(\.uid)
        ) else { return false }
        onMove(move.from, move.to)
        return true
    }
}

struct DraggableDeviceRow: View {
    @EnvironmentObject var audioManager: AudioManager
    let device: AudioDevice
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    var showCategoryPicker: Bool = false
    var onHide: ((AudioDevice) -> Void)?
    var onUnhide: ((AudioDevice) -> Void)?
    var isHiddenSection: Bool = false
    var category: OutputCategory? = nil
    let onDropUID: (String) -> Bool

    @State private var isHovering = false
    @State private var isDropTargeted = false

    var isDisconnected: Bool {
        !device.isConnected
    }

    var isIgnored: Bool {
        audioManager.isDeviceIgnored(device, inCategory: category)
    }

    var isGrayed: Bool {
        isDisconnected || isHiddenSection
    }

    var isNeverUse: Bool {
        audioManager.isNeverUse(device)
    }

    var statusIcon: String? {
        if isDisconnected {
            return "wifi.slash"
        } else if isIgnored && audioManager.isEditMode {
            return "eye.slash"
        } else if isNeverUse {
            return "nosign"
        }
        return nil
    }

    var lastSeenText: String? {
        guard isDisconnected,
              let stored = audioManager.priorityManager.getStoredDevice(uid: device.uid) else {
            return nil
        }
        return stored.lastSeenRelative
    }

    var isMuted: Bool {
        device.isConnected && audioManager.isDeviceMuted(device)
    }

    var body: some View {
        HStack(spacing: 8) {
            if !isHiddenSection {
                DeviceDragHandle(
                    index: index,
                    uid: device.uid,
                    isLarge: false,
                    foreground: isSelected && !isDisconnected ? .accentColor : .secondary
                )
            }

            // Device name - use HStack with tap gesture instead of Button to not interfere with drag
            HStack(spacing: 8) {
                Text(device.name)
                    .font(.system(size: 13, weight: .regular))
                    .strikethrough(isNeverUse, color: .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isGrayed || isNeverUse ? .secondary : .primary)

                if let icon = statusIcon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                if let lastSeen = lastSeenText {
                    Text(lastSeen)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                if isMuted {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 9))
                            Text("Muted")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(NSColor.windowBackgroundColor))
                                .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        )
                }

                Spacer(minLength: 12)

                if isSelected && !isDisconnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 15))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

            // Actions menu - always reserve space to prevent layout shifts
            ZStack {
                // Invisible placeholder to reserve space
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .opacity(0)
                
                // Actual menu (shown on hover)
                if isHovering {
                    Menu {
                        DeviceContextMenu(
                            device: device,
                            category: category,
                            showCategoryPicker: showCategoryPicker,
                            onHide: onHide,
                            onUnhide: onUnhide,
                            isHiddenSection: isHiddenSection
                        )
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: 32)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .opacity(isGrayed ? 0.6 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected && !isDisconnected ? Color(NSColor.controlBackgroundColor).opacity(0.4) : (isHovering ? Color.primary.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDropTargeted ? Color.accentColor : (isSelected && !isDisconnected ? Color.secondary.opacity(0.2) : Color.clear), lineWidth: isDropTargeted ? 2 : 1)
        )
        .overlay(alignment: .top) {
            if isDropTargeted {
                DropIndicatorLine()
                    .offset(y: -5)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisconnected {
                onSelect()
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let uid = items.first else { return false }
            return onDropUID(uid)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            DeviceContextMenu(
                device: device,
                category: category,
                showCategoryPicker: showCategoryPicker,
                onHide: onHide,
                onUnhide: onUnhide,
                isHiddenSection: isHiddenSection
            )
        }
    }
}

struct DeviceDragHandle: View {
    let index: Int
    let uid: String
    var isLarge: Bool = false
    var foreground: Color = .secondary

    var body: some View {
        VStack(spacing: isLarge ? 4 : 1) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: isLarge ? 13 : 9, weight: .bold))
            Text("\(index + 1)")
                .font(.system(size: isLarge ? 16 : 11, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(foreground)
        .frame(width: isLarge ? 48 : 36, height: isLarge ? 52 : 32)
        .background(
            RoundedRectangle(cornerRadius: isLarge ? 10 : 6)
                .fill(Color.primary.opacity(isLarge ? 0.12 : 0.08))
        )
        .contentShape(Rectangle())
        .help("Drag to reorder")
        .onHover { hovering in
            if hovering {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .draggable(uid)
    }
}

// Drop indicator line
struct DropIndicatorLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.horizontal, 2)
    }
}
