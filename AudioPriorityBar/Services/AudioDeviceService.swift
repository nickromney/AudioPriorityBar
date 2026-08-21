import Foundation
import CoreAudio
import AudioToolbox

/// The CoreAudio boundary used by `AudioManager`.
///
/// Keeping this interface small makes the stateful manager testable without
/// touching the user's actual audio devices.
protocol AudioDeviceServicing: AnyObject {
    var onDevicesChanged: (() -> Void)? { get set }
    var onMuteOrVolumeChanged: (() -> Void)? { get set }

    func getDevices() -> [AudioDevice]
    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID?
    func setDefaultDevice(_ deviceId: AudioObjectID, type: AudioDeviceType)
    func getOutputVolume() -> Float
    func setOutputVolume(_ volume: Float, force: Bool)
    func getInputVolume() -> Float
    func setInputVolume(_ volume: Float, force: Bool)
    func getDeviceVolume(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Float
    /// `nil` when the device exposes no readable volume at all. That is a very
    /// different answer from "full volume", and treating the two the same is
    /// why a device could never be seen as muted.
    func readDeviceVolume(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Float?
    func setDeviceVolume(_ volume: Float, deviceId: AudioObjectID, type: AudioDeviceType, force: Bool) -> Bool
    func supportsDeviceVolumeControl(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool
    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool
    func setDeviceMuted(_ muted: Bool, deviceId: AudioObjectID, type: AudioDeviceType) -> Bool
    func startListening()
}

extension AudioDeviceServicing {
    func setOutputVolume(_ volume: Float) { setOutputVolume(volume, force: false) }
    func setInputVolume(_ volume: Float) { setInputVolume(volume, force: false) }
    func getDeviceVolume(_ deviceId: AudioObjectID) -> Float {
        getDeviceVolume(deviceId, type: .output)
    }
}

class AudioDeviceService: AudioDeviceServicing {
    var onDevicesChanged: (() -> Void)?
    var onMuteOrVolumeChanged: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var muteVolumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var monitoredDeviceIds: Set<AudioObjectID> = []

    func getDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIds = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        )

        guard status == noErr else { return [] }

        var devices: [AudioDevice] = []

        for deviceId in deviceIds {
            if let inputDevice = createDevice(id: deviceId, type: .input) {
                devices.append(inputDevice)
            }
            if let outputDevice = createDevice(id: deviceId, type: .output) {
                devices.append(outputDevice)
            }
        }

        return devices
    }

    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceId: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceId
        )

        return status == noErr ? deviceId : nil
    }

    func setDefaultDevice(_ deviceId: AudioObjectID, type: AudioDeviceType) {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceId = deviceId
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceId
        )
    }

    func getOutputVolume() -> Float {
        guard let deviceId = getCurrentDefaultDevice(type: .output) else { return 0 }
        return getDeviceVolume(deviceId, type: .output)
    }

    func setOutputVolume(_ volume: Float) {
        setOutputVolume(volume, force: false)
    }

    func setOutputVolume(_ volume: Float, force: Bool) {
        guard let deviceId = getCurrentDefaultDevice(type: .output) else { return }
        setDeviceVolume(volume, deviceId: deviceId, type: .output, force: force)
    }

    func getInputVolume() -> Float {
        guard let deviceId = getCurrentDefaultDevice(type: .input) else { return 1 }
        return getDeviceVolume(deviceId, type: .input)
    }

    func setInputVolume(_ volume: Float) {
        setInputVolume(volume, force: false)
    }

    func setInputVolume(_ volume: Float, force: Bool) {
        guard let deviceId = getCurrentDefaultDevice(type: .input) else { return }
        setDeviceVolume(volume, deviceId: deviceId, type: .input, force: force)
    }

    func getDeviceVolume(_ deviceId: AudioObjectID, type: AudioDeviceType = .output) -> Float {
        // Only for display. Mute decisions must use `readDeviceVolume`, which
        // keeps "unreadable" distinguishable from "loud".
        readDeviceVolume(deviceId, type: type) ?? 1.0
    }

    func readDeviceVolume(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Float? {
        let scope = type == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput

        if let volume = readVolume(deviceId: deviceId, selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, element: kAudioObjectPropertyElementMain) {
            return volume
        }

        // HDMI / display devices often expose scalar volume on many channels,
        // not just a stereo pair or a virtual main volume.
        let channelVolumes = volumeElements(deviceId: deviceId, selector: kAudioDevicePropertyVolumeScalar, scope: scope).compactMap { element in
            readVolume(deviceId: deviceId, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: element)
        }
        return channelVolumes.first
    }

    /// Writes the level, then reads it back. A write that returns `noErr` and
    /// changes nothing is common on HDMI, so the return value of the CoreAudio
    /// call on its own is not evidence that the user will hear the difference.
    @discardableResult
    func setDeviceVolume(_ volume: Float, deviceId: AudioObjectID, type: AudioDeviceType, force: Bool = false) -> Bool {
        let scope = type == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        let requireSettable = !force
        var didWrite = writeVolume(
            deviceId: deviceId,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: scope,
            element: kAudioObjectPropertyElementMain,
            volume: volume,
            requireSettable: requireSettable
        )

        // Write every scalar channel as well. Some displays accept a virtual
        // main-volume write that does not actually change the heard level.
        for element in volumeElements(deviceId: deviceId, selector: kAudioDevicePropertyVolumeScalar, scope: scope) {
            didWrite = writeVolume(
                deviceId: deviceId,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: scope,
                element: element,
                volume: volume,
                requireSettable: requireSettable
            ) || didWrite
        }

        guard didWrite else { return false }
        guard let readBack = readDeviceVolume(deviceId, type: type) else {
            // Write-only device: we cannot prove it took, so do not claim it.
            return false
        }
        return abs(readBack - volume) <= 0.02
    }

    func supportsDeviceVolumeControl(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope = type == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        if isVolumeSettable(deviceId: deviceId, selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, element: kAudioObjectPropertyElementMain) {
            return true
        }
        return volumeElements(deviceId: deviceId, selector: kAudioDevicePropertyVolumeScalar, scope: scope).contains { element in
            isVolumeSettable(deviceId: deviceId, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: element)
        }
    }

    private func volumeElements(
        deviceId: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> [AudioObjectPropertyElement] {
        var elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain]
        for index in 1...16 {
            elements.append(AudioObjectPropertyElement(index))
        }
        return elements.filter { element in
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
            return AudioObjectHasProperty(deviceId, &address)
        }
    }

    private func readVolume(deviceId: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Float? {
        var propertyAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, &volume)
        return status == noErr ? volume : nil
    }

    private func writeVolume(deviceId: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement, volume: Float, requireSettable: Bool = true) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(deviceId, &propertyAddress) else { return false }
        if requireSettable && !isVolumeSettable(deviceId: deviceId, selector: selector, scope: scope, element: element) { return false }
        var mutableVolume = volume
        let dataSize = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(deviceId, &propertyAddress, 0, nil, dataSize, &mutableVolume) == noErr
    }

    private func isVolumeSettable(deviceId: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(deviceId, &propertyAddress) else { return false }
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceId, &propertyAddress, &settable)
        return status == noErr && settable.boolValue
    }

    /// What the hardware says right now. Only used as corroboration: the app's
    /// own record of what the user asked for is the source of truth, because a
    /// device with no readable mute and no readable volume can answer nothing
    /// at all here.
    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        if let muted = readMuteProperty(deviceId: deviceId, scope: scope), muted {
            return true
        }

        // A device sitting at zero is muted in every way the user cares about.
        if let volume = readDeviceVolume(deviceId, type: type) {
            return volume <= 0.01
        }

        // Nothing readable: claiming silence here is how the app ended up
        // telling the user it was muted while sound kept coming out.
        return false
    }

    /// Writes the mute property on every element that has one, then reads it
    /// back. Returns true only when the device now reports the state we asked
    /// for: a device that accepts the write and keeps playing must not be able
    /// to tell the app it went quiet.
    @discardableResult
    func setDeviceMuted(_ muted: Bool, deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        let elements = volumeElements(deviceId: deviceId, selector: kAudioDevicePropertyMute, scope: scope)
        guard !elements.isEmpty else { return false }

        var didWrite = false
        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: scope,
                mElement: element
            )
            var value: UInt32 = muted ? 1 : 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            didWrite = AudioObjectSetPropertyData(deviceId, &address, 0, nil, size, &value) == noErr || didWrite
        }

        guard didWrite else { return false }
        return readMuteProperty(deviceId: deviceId, scope: scope) == muted
    }

    /// The device's own answer to "are you muted", or `nil` when it has no
    /// readable mute property.
    private func readMuteProperty(deviceId: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool? {
        var readings: [Bool] = []
        for element in volumeElements(deviceId: deviceId, selector: kAudioDevicePropertyMute, scope: scope) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: scope,
                mElement: element
            )
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &value) == noErr {
                readings.append(value != 0)
            }
        }
        guard !readings.isEmpty else { return nil }
        // Any element still unmuted means sound can get out.
        return readings.allSatisfy { $0 }
    }

    func startListening() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        listenerBlock = { [weak self] _, _ in
            self?.onDevicesChanged?()
            // Re-register mute/volume listeners when devices change
            self?.updateMuteVolumeListeners()
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        // Also listen to default device changes
        var inputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDefaultAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        var outputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDefaultAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        // Initial setup of mute/volume listeners
        updateMuteVolumeListeners()
    }

    func updateMuteVolumeListeners() {
        // Remove old listeners
        removeMuteVolumeListeners()

        // Create listener block
        muteVolumeListenerBlock = { [weak self] _, _ in
            self?.onMuteOrVolumeChanged?()
        }

        // Get all current device IDs
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIds = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        )

        guard status == noErr else { return }

        // Register listeners for each device
        for deviceId in deviceIds {
            // Listen to mute on output scope
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &muteAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            // Listen to mute on input scope
            muteAddress.mScope = kAudioDevicePropertyScopeInput
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &muteAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            // Listen to volume changes
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                deviceId,
                &volumeAddress,
                DispatchQueue.main,
                muteVolumeListenerBlock!
            )

            monitoredDeviceIds.insert(deviceId)
        }
    }

    private func removeMuteVolumeListeners() {
        guard let block = muteVolumeListenerBlock else { return }

        for deviceId in monitoredDeviceIds {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceId, &muteAddress, DispatchQueue.main, block)

            muteAddress.mScope = kAudioDevicePropertyScopeInput
            AudioObjectRemovePropertyListenerBlock(deviceId, &muteAddress, DispatchQueue.main, block)

            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceId, &volumeAddress, DispatchQueue.main, block)
        }

        monitoredDeviceIds.removeAll()
        muteVolumeListenerBlock = nil
    }

    func stopListening() {
        // Remove mute/volume listeners first
        removeMuteVolumeListeners()

        guard let block = listenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )

        // Also remove default device change listeners
        var inputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDefaultAddress,
            DispatchQueue.main,
            block
        )

        var outputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDefaultAddress,
            DispatchQueue.main,
            block
        )

        listenerBlock = nil
    }

    private func createDevice(id: AudioObjectID, type: AudioDeviceType) -> AudioDevice? {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        guard hasStreams(deviceId: id, scope: scope) else { return nil }

        guard let name = getDeviceName(id: id) else { return nil }
        guard let uid = getDeviceUID(id: id) else { return nil }

        return AudioDevice(id: id, uid: uid, name: name, type: type, isBuiltIn: isBuiltIn(id: id))
    }

    private func isBuiltIn(id: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &transportType)
        return status == noErr && transportType == kAudioDeviceTransportTypeBuiltIn
    }

    private func hasStreams(deviceId: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    private func getDeviceName(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String? : nil
    }

    private func getDeviceUID(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        return status == noErr ? uid as String? : nil
    }

    deinit {
        stopListening()
    }
}
