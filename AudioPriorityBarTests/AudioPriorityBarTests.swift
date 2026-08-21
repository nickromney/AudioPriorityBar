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
        XCTAssertEqual(service.volumeWrites.map(\.1), [0])

        manager.setAllOutputsMuted(false)

        XCTAssertFalse(manager.areAllOutputsMuted)
        XCTAssertFalse(manager.isActiveOutputMuted)
        XCTAssertEqual(service.volumeWrites.map(\.1), [0, 0.5])
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

    func testMuteMicrophonesButtonUsesSlashedIconWhenMuted() {
        XCTAssertEqual(MuteMicrophonesButton.iconName(isMuted: false), "mic.fill")
        XCTAssertEqual(MuteMicrophonesButton.iconName(isMuted: true), "mic.slash.fill")
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
    var outputVolume: Float = 0.5
    var defaultInputId: AudioObjectID = 1
    var defaultOutputId: AudioObjectID = 2

    init(devices: [AudioDevice]) {
        self.devices = devices
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
    func getOutputVolume() -> Float { 0.5 }
    func setOutputVolume(_ volume: Float, force: Bool) {}
    func getInputVolume() -> Float { 0.5 }
    func setInputVolume(_ volume: Float, force: Bool) {}
    func getDeviceVolume(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Float {
        type == .output ? outputVolume : 0.5
    }
    func setDeviceVolume(_ volume: Float, deviceId: AudioObjectID, type: AudioDeviceType, force: Bool) -> Bool {
        volumeWrites.append((deviceId, volume))
        if type == .output { outputVolume = volume }
        return true
    }
    func supportsDeviceVolumeControl(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool { true }
    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        type == .output && outputVolume < 0.01
    }
    func setDeviceMuted(_ muted: Bool, deviceId: AudioObjectID, type: AudioDeviceType) -> Bool { false }
    func startListening() {}
}
