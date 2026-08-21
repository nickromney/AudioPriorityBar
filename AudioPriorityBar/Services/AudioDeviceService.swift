import Foundation
import CoreAudio
import AudioToolbox

class AudioDeviceService {
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
        let scope = type == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput

        if let volume = readVolume(deviceId: deviceId, selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, element: kAudioObjectPropertyElementMain) {
            return volume
        }

        // Some devices, notably HDMI displays, expose volume per output
        // channel rather than through the virtual main-volume property.
        let channelVolumes = (1...2).compactMap { element in
            readVolume(deviceId: deviceId, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: AudioObjectPropertyElement(element))
        }
        return channelVolumes.first ?? 1.0
    }

    @discardableResult
    func setDeviceVolume(_ volume: Float, deviceId: AudioObjectID, type: AudioDeviceType, force: Bool = false) -> Bool {
        let scope = type == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput

        if writeVolume(deviceId: deviceId, selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, element: kAudioObjectPropertyElementMain, volume: volume, requireSettable: !force) {
            return true
        }

        // Fall back to the writable left/right scalar volume controls used by
        // some HDMI and display audio devices.
        var didWrite = false
        for element in 1...2 {
            didWrite = writeVolume(deviceId: deviceId, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: AudioObjectPropertyElement(element), volume: volume, requireSettable: !force) || didWrite
        }
        return didWrite
    }

    func supportsDeviceVolumeControl(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope = type == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        if isVolumeSettable(deviceId: deviceId, selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, element: kAudioObjectPropertyElementMain) {
            return true
        }
        return (1...2).contains { element in
            isVolumeSettable(deviceId: deviceId, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: AudioObjectPropertyElement(element))
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

    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        // Try kAudioDevicePropertyMute (per-channel, element 0 is master)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var muted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        var status = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &muted
        )

        if status == noErr && muted != 0 {
            return true
        }

        // Try element 1 (first channel) if master didn't work
        propertyAddress.mElement = 1
        status = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &muted
        )

        if status == noErr && muted != 0 {
            return true
        }

        // Check if volume is essentially zero (some devices report this as muted)
        if type == .output {
            let volume = getDeviceVolume(deviceId)
            if volume < 0.01 {
                return true
            }
        }

        return false
    }

    @discardableResult
    func setDeviceMuted(_ muted: Bool, deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let scope: AudioObjectPropertyScope = type == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput

        var didWrite = false
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: scope,
                mElement: element
            )
            guard AudioObjectHasProperty(deviceId, &address) else { continue }
            var value: UInt32 = muted ? 1 : 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            didWrite = AudioObjectSetPropertyData(deviceId, &address, 0, nil, size, &value) == noErr || didWrite
        }
        return didWrite
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

        return AudioDevice(id: id, uid: uid, name: name, type: type)
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
