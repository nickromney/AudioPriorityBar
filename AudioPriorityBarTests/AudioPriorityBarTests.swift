import XCTest
import CoreAudio
@testable import AudioPriorityBar

@MainActor
final class AudioPriorityBarTests: XCTestCase {
    func testInjectedPriorityManagerUsesIsolatedDefaults() {
        let defaults = UserDefaults(suiteName: "AudioPriorityBarXcodeTests")!
        defaults.removePersistentDomain(forName: "AudioPriorityBarXcodeTests")
        let manager = PriorityManager(defaults: defaults)
        let device = AudioDevice(id: 1, uid: "test-speaker", name: "Test Speaker", type: .output)

        manager.setNeverUse(device, neverUse: true)

        XCTAssertTrue(manager.isNeverUse(device))
    }

    func testMuteAllTogglesForDevicesUsingSoftwareMuteFallback() {
        let service = FakeAudioService(devices: [
            AudioDevice(id: 1, uid: "display", name: "Display Speakers", type: .output)
        ])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        service.volumeWrites.removeAll()

        XCTAssertFalse(manager.areAllOutputsMuted)

        manager.setAllOutputsMuted(true)

        XCTAssertTrue(manager.areAllOutputsMuted)
        XCTAssertTrue(manager.isActiveOutputMuted)
        XCTAssertTrue(service.volumeWrites.contains { $0.1 == 0 })

        manager.setAllOutputsMuted(false)

        XCTAssertFalse(manager.areAllOutputsMuted)
        XCTAssertFalse(manager.isActiveOutputMuted)
        XCTAssertTrue(service.volumeWrites.contains { $0.1 > 0.01 })
    }

    func testUnmuteAllRestoresAUsableVolumeAfterMuteStateSurvivesRestart() {
        let service = FakeAudioService(devices: [
            AudioDevice(id: 1, uid: "display", name: "Display Speakers", type: .output)
        ])
        let firstManager = AudioManager(deviceService: service, priorityManager: PriorityManager(defaults: isolatedDefaults()))
        firstManager.setAllOutputsMuted(true)

        let restartedManager = AudioManager(deviceService: service, priorityManager: PriorityManager(defaults: isolatedDefaults()))
        XCTAssertTrue(restartedManager.areAllOutputsMuted)

        restartedManager.setAllOutputsMuted(false)

        XCTAssertFalse(restartedManager.areAllOutputsMuted)
        XCTAssertGreaterThan(service.outputVolume, 0)
    }

    func testSelectingOutputSurvivesDefaultDeviceChangeNotification() async throws {
        let speakers = AudioDevice(id: 2, uid: "speakers", name: "Desk Speakers", type: .output)
        let q2u = AudioDevice(id: 3, uid: "q2u", name: "Samsung Q2U Speakers", type: .output)
        let service = FakeAudioService(devices: [speakers, q2u])
        let manager = AudioManager(deviceService: service, priorityManager: PriorityManager(defaults: isolatedDefaults()))

        manager.selectOutputDevice(q2u, category: .speaker)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(manager.currentOutputId, q2u.id)
        XCTAssertEqual(service.defaultOutputId, q2u.id)
    }

    func testRelaunchOpensAFreshApplicationInstance() {
        XCTAssertTrue(AppProcess.relaunchConfiguration().createsNewApplicationInstance)
        XCTAssertTrue(AppProcess.relaunchConfiguration().activates)
    }

    func testMuteMicrophonesButtonUsesSlashedIconWhenMuted() {
        XCTAssertEqual(MuteMicrophonesButton.iconName(isMuted: false), "mic.fill")
        XCTAssertEqual(MuteMicrophonesButton.iconName(isMuted: true), "mic.slash.fill")
    }

    func testVolumeSliderHidesSlashWhenLevelIsNonZero() {
        XCTAssertTrue(VolumeSliderView.showsMutedIcon(volume: 0))
        XCTAssertFalse(VolumeSliderView.showsMutedIcon(volume: 0.58))
    }

    func testSelectingASpeakerAfterMuteAllMakesItAudible() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let service = FakeAudioService(devices: [macMini, display])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )

        manager.selectOutputDevice(display, category: .speaker)
        manager.setAllOutputsMuted(true)
        XCTAssertTrue(manager.areAllOutputsMuted)

        manager.selectOutputDevice(macMini, category: .speaker)

        XCTAssertEqual(manager.currentOutputId, macMini.id)
        XCTAssertFalse(manager.areAllOutputsMuted)
        XCTAssertFalse(manager.isDeviceMuted(macMini))
        XCTAssertGreaterThan(manager.volume, 0.01)
        XCTAssertGreaterThan(service.getDeviceVolume(macMini.id, type: .output), 0.01)
    }

    func testKeepMutedWhenChangingSelectionLeavesTheNewDeviceMuted() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let defaults = isolatedDefaults()
        let manager = AudioManager(
            deviceService: FakeAudioService(devices: [macMini, display]),
            priorityManager: PriorityManager(defaults: defaults)
        )
        manager.selectOutputDevice(display, category: .speaker)
        manager.setAllOutputsMuted(true)
        manager.setKeepMutedWhenChangingSelection(true)

        manager.selectOutputDevice(macMini, category: .speaker)

        XCTAssertTrue(manager.areAllOutputsMuted)
        XCTAssertTrue(manager.isDeviceMuted(macMini))
        XCTAssertEqual(manager.volume, 0, accuracy: 0.01)
    }

    func testRaisingTheVolumeUnmutesAndKeepsTheNewLevel() {
        let speakers = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let service = FakeAudioService(devices: [speakers])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(speakers, category: .speaker)
        manager.setAllOutputsMuted(true)
        XCTAssertEqual(manager.volume, 0, accuracy: 0.01)

        manager.setVolume(0.53)

        XCTAssertEqual(manager.volume, 0.53, accuracy: 0.01)
        XCTAssertEqual(service.getOutputVolume(), 0.53, accuracy: 0.01)
        XCTAssertFalse(manager.areAllOutputsMuted)
        XCTAssertFalse(manager.isDeviceMuted(speakers))
        XCTAssertFalse(VolumeSliderView.showsMutedIcon(volume: manager.volume))
    }

    func testDoubleClickCyclesUnmutedMutedThenUnselected() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let manager = AudioManager(
            deviceService: FakeAudioService(devices: [macMini, display]),
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(macMini, category: .speaker)
        XCTAssertEqual(manager.outputPresentation(for: macMini), .unmuted)

        manager.cycleOutputPresentation(macMini, category: .speaker)
        XCTAssertEqual(manager.outputPresentation(for: macMini), .muted)
        XCTAssertEqual(manager.currentOutputId, macMini.id)

        manager.cycleOutputPresentation(macMini, category: .speaker)
        XCTAssertEqual(manager.currentOutputId, display.id)
        XCTAssertEqual(manager.outputPresentation(for: macMini), .unselected)
        XCTAssertEqual(manager.outputPresentation(for: display), .unmuted)
    }

    func testUSBMicrophoneInterfaceTwinsCollapseToOneSpeakerRow() {
        let vocaster = AudioDevice(id: 1, uid: "vocaster", name: "Vocaster Two", type: .output)
        let q2uA = AudioDevice(
            id: 5,
            uid: "AppleUSBAudioEngine:Samson Technologies:Samson Q2U Microphone:14100000:1",
            name: "Samson Q2U Microphone",
            type: .output
        )
        let q2uB = AudioDevice(
            id: 6,
            uid: "AppleUSBAudioEngine:Samson Technologies:Samson Q2U Microphone:14100000:2",
            name: "Samson Q2U Microphone",
            type: .output
        )
        let service = FakeAudioService(devices: [vocaster, q2uA, q2uB])
        service.defaultOutputId = vocaster.id
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )

        XCTAssertEqual(manager.speakerDevices.filter { $0.name == "Samson Q2U Microphone" }.count, 1)

        manager.setAllOutputsMuted(true)
        XCTAssertEqual(Set(service.volumeWrites.map(\.0)), [vocaster.id, q2uA.id, q2uB.id])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "AudioPriorityBarXcodeTests.Manager"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class FakeAudioService: AudioDeviceServicing {
    var onDevicesChanged: (() -> Void)?
    var onMuteOrVolumeChanged: (() -> Void)?
    let devices: [AudioDevice]
    var volumeWrites: [(AudioObjectID, Float)] = []
    private var volumes: [AudioObjectID: Float] = [:]
    private var mutedIds: Set<AudioObjectID> = []
    var defaultInputId: AudioObjectID = 1
    var defaultOutputId: AudioObjectID = 2

    var outputVolume: Float {
        get { getDeviceVolume(defaultOutputId, type: .output) }
        set { _ = setDeviceVolume(newValue, deviceId: defaultOutputId, type: .output, force: true) }
    }

    init(devices: [AudioDevice]) {
        self.devices = devices
        for device in devices {
            volumes[device.id] = 0.5
        }
        if let output = devices.first(where: { $0.type == .output }) {
            defaultOutputId = output.id
        }
        if let input = devices.first(where: { $0.type == .input }) {
            defaultInputId = input.id
        }
    }

    func getDevices() -> [AudioDevice] { devices }
    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        type == .input ? defaultInputId : defaultOutputId
    }
    func setDefaultDevice(_ deviceId: AudioObjectID, type: AudioDeviceType) {
        if type == .input { defaultInputId = deviceId }
        else { defaultOutputId = deviceId }
        onDevicesChanged?()
    }
    func getOutputVolume() -> Float { getDeviceVolume(defaultOutputId, type: .output) }
    func setOutputVolume(_ volume: Float, force: Bool) {
        _ = setDeviceVolume(volume, deviceId: defaultOutputId, type: .output, force: force)
    }
    func getInputVolume() -> Float { getDeviceVolume(defaultInputId, type: .input) }
    func setInputVolume(_ volume: Float, force: Bool) {
        _ = setDeviceVolume(volume, deviceId: defaultInputId, type: .input, force: force)
    }
    func getDeviceVolume(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Float {
        if mutedIds.contains(deviceId) { return 0 }
        return volumes[deviceId] ?? 0.5
    }
    func setDeviceVolume(_ volume: Float, deviceId: AudioObjectID, type: AudioDeviceType, force: Bool) -> Bool {
        volumeWrites.append((deviceId, volume))
        volumes[deviceId] = volume
        if volume > 0.01 {
            mutedIds.remove(deviceId)
        }
        return true
    }
    func supportsDeviceVolumeControl(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool { true }
    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        mutedIds.contains(deviceId) || getDeviceVolume(deviceId, type: type) < 0.01
    }
    func setDeviceMuted(_ muted: Bool, deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        if muted {
            mutedIds.insert(deviceId)
        } else {
            mutedIds.remove(deviceId)
        }
        return true
    }
    func startListening() {}
}
