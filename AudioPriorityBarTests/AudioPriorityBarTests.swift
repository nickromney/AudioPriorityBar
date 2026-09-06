import XCTest
import CoreAudio
import SwiftUI
import AppKit
@testable import AudioPriorityBar

@MainActor
final class AudioPriorityBarTests: XCTestCase {
    func testPanelFitsSmallScreensInBothAppearances() throws {
        let service = FakeAudioService(devices: [
            AudioDevice(id: 1, uid: "desk", name: "Studio Display", type: .output),
            AudioDevice(id: 2, uid: "builtin", name: "MacBook Pro Speakers", type: .output),
            AudioDevice(id: 3, uid: "mic", name: "MacBook Pro Microphone", type: .input)
        ])
        let manager = AudioManager(deviceService: service, priorityManager: PriorityManager(defaults: isolatedDefaults()))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for settings in [false, true] {
                let view = NSHostingView(rootView: MenuBarView(showingSettings: .constant(settings))
                    .environmentObject(manager)
                    .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
                    .background(Color(nsColor: .windowBackgroundColor)))
                let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = view
                window.appearance = NSAppearance(named: appearance)
                view.appearance = NSAppearance(named: appearance)
                let size = view.fittingSize
                XCTAssertEqual(size.width, 480, accuracy: 1)
                XCTAssertGreaterThan(size.height, 400)
                XCTAssertLessThan(size.height, 700, "Panel should fit below the menu bar on a 768-point screen")
                view.frame = NSRect(origin: .zero, size: size)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        let name = "AudioPriorityBar-\(settings ? "settings" : "controls")-\(appearance.rawValue).png"
                        try png.write(to: URL(fileURLWithPath: "/tmp").appendingPathComponent(name))
                    }
                }
            }
        }
    }

    func testChangingPanelVisibilityKeepsAudioRoutingAndOneSection() {
        let service = FakeAudioService(devices: [
            AudioDevice(id: 1, uid: "vocaster", name: "Vocaster", type: .output),
            AudioDevice(id: 2, uid: "mic", name: "Microphone", type: .input)
        ])
        let manager = AudioManager(deviceService: service, priorityManager: PriorityManager(defaults: isolatedDefaults()))
        let output = manager.currentOutputId
        let input = manager.currentInputId
        service.volumeWrites.removeAll()
        manager.setDeviceTab(.headphone, visible: false)
        manager.setDeviceTab(.speaker, visible: false)
        manager.setDeviceTab(.microphone, visible: false)
        XCTAssertEqual(manager.visibleDeviceTabs, [.microphone])
        XCTAssertEqual(manager.defaultDeviceTab, .microphone)
        XCTAssertEqual(manager.currentOutputId, output)
        XCTAssertEqual(manager.currentInputId, input)
        XCTAssertTrue(service.volumeWrites.isEmpty)
    }

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
        XCTAssertTrue(manager.isMuteAllActive)
        XCTAssertTrue(manager.isActiveOutputMuted)
        XCTAssertTrue(service.volumeWrites.contains { $0.1 == 0 })

        manager.setAllOutputsMuted(false)

        XCTAssertFalse(manager.areAllOutputsMuted)
        XCTAssertFalse(manager.isMuteAllActive)
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
        XCTAssertTrue(restartedManager.isMuteAllActive)

        restartedManager.setAllOutputsMuted(false)

        XCTAssertFalse(restartedManager.areAllOutputsMuted)
        XCTAssertFalse(restartedManager.isMuteAllActive)
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

    func testRelaunchPassesCurrentProcessForStatusItemHandoff() {
        XCTAssertEqual(AppProcess.relaunchArguments(), [
            "--relaunch-after", String(ProcessInfo.processInfo.processIdentifier)
        ])
    }

    func testNormalLaunchDoesNotWaitForAnotherProcess() {
        XCTAssertTrue(AppProcess.waitForPreviousInstance(arguments: ["AudioPriorityBar"]))
        XCTAssertTrue(AppProcess.waitForPreviousInstance(arguments: ["AudioPriorityBar", "--relaunch-after"]))
        XCTAssertTrue(AppProcess.waitForPreviousInstance(arguments: ["AudioPriorityBar", "--relaunch-after", "invalid"]))
    }

    func testRelaunchWaitsForPreviousProcessToExit() throws {
        let previous = Process()
        previous.executableURL = URL(fileURLWithPath: "/bin/sleep")
        previous.arguments = ["0.2"]
        try previous.run()
        let finished = expectation(description: "Previous process exited")
        DispatchQueue.global().async {
            previous.waitUntilExit()
            finished.fulfill()
        }
        XCTAssertTrue(AppProcess.waitForPreviousInstance(arguments: [
            "AudioPriorityBar", "--relaunch-after", String(previous.processIdentifier)
        ]))
        XCTAssertFalse(previous.isRunning)
        wait(for: [finished], timeout: 2)
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
        XCTAssertTrue(manager.isMuteAllActive)

        manager.selectOutputDevice(macMini, category: .speaker)

        XCTAssertEqual(manager.currentOutputId, macMini.id)
        XCTAssertFalse(manager.areAllOutputsMuted)
        XCTAssertFalse(manager.isDeviceMuted(macMini))
        XCTAssertGreaterThan(manager.volume, 0.01)
        XCTAssertGreaterThan(service.getDeviceVolume(macMini.id, type: .output), 0.01)
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
        XCTAssertFalse(manager.isMuteAllActive)
        XCTAssertFalse(manager.isDeviceMuted(speakers))
        XCTAssertFalse(VolumeSliderView.showsMutedIcon(volume: manager.volume))
    }

    func testClickingADeviceWalksNeutralThenSilentThenLive() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let desk = AudioDevice(id: 2, uid: "desk", name: "Desk Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini, desk])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults(keepPanelOpen: true))
        )
        manager.selectOutputDevice(desk, category: .speaker)
        XCTAssertEqual(manager.outputPresentation(for: macMini), .unselected)

        manager.cycleOutputPresentation(macMini, category: .speaker)
        XCTAssertEqual(manager.outputPresentation(for: macMini), .muted)
        XCTAssertEqual(manager.currentOutputId, macMini.id, "it is the output, it is just not making sound yet")
        XCTAssertFalse(service.isAudible(macMini.id))

        manager.cycleOutputPresentation(macMini, category: .speaker)
        XCTAssertEqual(manager.outputPresentation(for: macMini), .unmuted)
        XCTAssertTrue(service.isAudible(macMini.id))
        XCTAssertGreaterThan(manager.volume, 0.01)
    }

    func testAutoCloseSelectionMakesDifferentOutputAudible() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let desk = AudioDevice(id: 2, uid: "desk", name: "Desk Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini, desk])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults(keepPanelOpen: false))
        )

        manager.selectOutputDevice(desk, category: .speaker)
        manager.cycleOutputPresentation(macMini, category: .speaker)

        XCTAssertEqual(manager.currentOutputId, macMini.id)
        XCTAssertTrue(service.isAudible(macMini.id))
        XCTAssertFalse(manager.isDeviceMuted(macMini))
    }

    func testAThirdClickHandsOverToTheNextDeviceSilently() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let desk = AudioDevice(id: 2, uid: "desk", name: "Desk Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini, desk])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults(keepPanelOpen: true))
        )
        // Start from neutral: the fake hands out the first device as the
        // current default, exactly as CoreAudio would.
        manager.selectOutputDevice(desk, category: .speaker)
        manager.cycleOutputPresentation(macMini, category: .speaker)
        manager.cycleOutputPresentation(macMini, category: .speaker)
        XCTAssertEqual(manager.outputPresentation(for: macMini), .unmuted)

        manager.cycleOutputPresentation(macMini, category: .speaker)

        XCTAssertEqual(manager.outputPresentation(for: macMini), .unselected)
        XCTAssertEqual(manager.currentOutputId, desk.id)
        XCTAssertFalse(service.isAudible(desk.id), "the device taking over is silent until you click it")
    }

    func testTheLastDeviceStandingTogglesInsteadOfHandingOver() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults(keepPanelOpen: true))
        )
        manager.cycleOutputPresentation(macMini, category: .speaker)
        manager.cycleOutputPresentation(macMini, category: .speaker)
        XCTAssertEqual(manager.outputPresentation(for: macMini), .unmuted)

        // Nowhere to hand over to, so the click must still do something.
        manager.cycleOutputPresentation(macMini, category: .speaker)

        XCTAssertEqual(manager.outputPresentation(for: macMini), .muted)
        XCTAssertEqual(manager.currentOutputId, macMini.id)
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
            priorityManager: PriorityManager(defaults: isolatedDefaults(keepPanelOpen: true))
        )

        XCTAssertEqual(manager.speakerDevices.filter { $0.name == "Samson Q2U Microphone" }.count, 1)

        manager.setAllOutputsMuted(true)
        XCTAssertEqual(Set(service.volumeWrites.map(\.0)), [vocaster.id, q2uA.id, q2uB.id])
    }

    // MARK: - Mute model

    func testMuteAllOwnsUpToTheDeviceItCannotSilence() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let service = FakeAudioService(devices: [macMini, display], behaviors: [display.id: .ignoresWrites])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults(keepPanelOpen: true))
        )
        manager.selectOutputDevice(display, category: .speaker)
        // Without the redirect there is nothing left to do but report honestly.
        manager.setRedirectMuteAllToBuiltIn(false)

        manager.setAllOutputsMuted(true)

        XCTAssertTrue(manager.areAllOutputsMuted, "the latch drives the button, not agreement from every device")
        XCTAssertFalse(service.isAudible(macMini.id))
        XCTAssertTrue(manager.isDeviceMuted(macMini))

        XCTAssertTrue(service.isAudible(display.id), "the display ignored the write and is what you are hearing")
        XCTAssertFalse(manager.isDeviceMuted(display), "so the app must not claim it is muted")
        XCTAssertTrue(manager.isDeviceIgnoringMute(display))
        XCTAssertEqual(manager.outputsIgnoringMute, ["PL2792Q"])
    }

    func testADeviceThatIsNotTheOutputIsNeverReportedAsStillPlaying() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let service = FakeAudioService(devices: [macMini, display], behaviors: [display.id: .ignoresWrites])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(macMini, category: .speaker)

        manager.setAllOutputsMuted(true)

        // The display refused the mute, but macOS only sends audio to the
        // default device, so nothing is coming out of it and saying otherwise
        // sends the user hunting for a sound that is not there.
        XCTAssertTrue(manager.isDeviceUnmutable(display))
        XCTAssertFalse(manager.isDeviceIgnoringMute(display))
        XCTAssertEqual(manager.outputsIgnoringMute, [])
    }

    func testLettingOneDeviceThroughAfterMuteAllLeavesTheRestMuted() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let desk = AudioDevice(id: 2, uid: "desk", name: "Desk Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini, desk])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(desk, category: .speaker)
        manager.setAllOutputsMuted(true)

        // Click the card twice: active but silent, then audible.
        manager.cycleOutputPresentation(macMini, category: .speaker)
        XCTAssertEqual(manager.currentOutputId, macMini.id)
        XCTAssertFalse(service.isAudible(macMini.id), "selecting a device must not blast sound at you")

        manager.cycleOutputPresentation(macMini, category: .speaker)

        XCTAssertTrue(service.isAudible(macMini.id))
        XCTAssertFalse(service.isAudible(desk.id), "Mute All is not undone by letting one device through")
        XCTAssertTrue(manager.isDeviceMuted(desk))
    }

    func testADeviceMutedOnItsOwnStaysMutedWhenTheLatchIsReleased() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let desk = AudioDevice(id: 2, uid: "desk", name: "Desk Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini, desk])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.toggleMute(for: desk)
        manager.setAllOutputsMuted(true)

        manager.selectOutputDevice(macMini, category: .speaker)

        XCTAssertTrue(service.isAudible(macMini.id))
        XCTAssertFalse(service.isAudible(desk.id), "the user muted this one by hand, so leave it muted")
        XCTAssertTrue(manager.isDeviceMuted(desk))
    }

    func testMutingADeviceFromItsRowDoesNotChangeWhichDeviceIsSelected() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let desk = AudioDevice(id: 2, uid: "desk", name: "Desk Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini, desk])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(macMini, category: .speaker)

        manager.toggleMute(for: desk)

        XCTAssertEqual(manager.currentOutputId, macMini.id, "muting another device must not switch the output")
        XCTAssertTrue(manager.isDeviceMuted(desk))
        XCTAssertTrue(service.isAudible(macMini.id))

        manager.toggleMute(for: desk)

        XCTAssertFalse(manager.isDeviceMuted(desk))
        XCTAssertTrue(service.isAudible(desk.id))
        XCTAssertEqual(manager.currentOutputId, macMini.id)
    }

    func testMutingTheMicrophoneLeavesTheSameDevicesHeadphoneJackAlone() {
        let q2uInput = AudioDevice(id: 5, uid: "q2u", name: "Samson Q2U Microphone", type: .input)
        let q2uOutput = AudioDevice(id: 5, uid: "q2u", name: "Samson Q2U Microphone", type: .output)
        let service = FakeAudioService(devices: [q2uInput, q2uOutput])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )

        manager.toggleMute(for: q2uInput)

        XCTAssertTrue(manager.isDeviceMuted(q2uInput))
        XCTAssertFalse(manager.isDeviceMuted(q2uOutput))
    }

    func testADeviceWhoseLevelCannotBeReadStillReportsAsMuted() {
        let vocaster = AudioDevice(id: 1, uid: "vocaster", name: "Vocaster Two", type: .output)
        let service = FakeAudioService(devices: [vocaster], behaviors: [vocaster.id: .noReadableVolume])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )

        manager.setAllOutputsMuted(true)

        XCTAssertTrue(
            manager.isDeviceMuted(vocaster),
            "an unreadable level used to look identical to full volume, so mute never showed"
        )
        XCTAssertFalse(service.isAudible(vocaster.id))
        XCTAssertEqual(manager.volume, 0, accuracy: 0.01)
    }

    func testUnmutingADeviceWhoseLevelCannotBeReadLandsOnSomethingAudible() {
        let vocaster = AudioDevice(id: 1, uid: "vocaster", name: "Vocaster Two", type: .output)
        let service = FakeAudioService(devices: [vocaster], behaviors: [vocaster.id: .noReadableVolume])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.setAllOutputsMuted(true)

        manager.setAllOutputsMuted(false)

        XCTAssertFalse(manager.isDeviceMuted(vocaster))
        XCTAssertTrue(service.isAudible(vocaster.id), "unmuting must never restore silence")
    }

    func testRaisingTheVolumeOutsideTheAppReleasesTheMute() async throws {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.setAllOutputsMuted(true)
        XCTAssertTrue(manager.areAllOutputsMuted)

        // The volume keys, System Settings, or the device's own knob.
        service.simulateExternalVolumeChange(0.4, deviceId: macMini.id)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(manager.areAllOutputsMuted, "sound is coming out, so the app must not still say muted")
        XCTAssertFalse(manager.isMuteAllActive)
        XCTAssertFalse(manager.isDeviceMuted(macMini))
        XCTAssertEqual(manager.volume, 0.4, accuracy: 0.01)
    }

    func testADisplayThatIgnoresMuteIsNotMistakenForTheUserUnmuting() async throws {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let service = FakeAudioService(devices: [macMini, display], behaviors: [display.id: .ignoresWrites])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.setAllOutputsMuted(true)

        // The display never went quiet, so its notifications must not be read
        // as the user asking for sound back.
        service.simulateExternalVolumeChange(0.58, deviceId: display.id)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(manager.areAllOutputsMuted)
        XCTAssertTrue(manager.isMuteAllActive)
        XCTAssertTrue(manager.isDeviceMuted(macMini), "the device that did mute stays muted")
        XCTAssertTrue(manager.isDeviceUnmutable(display), "we still know the display refused")
    }

    func testSelectingAMutedDeviceBringsItUpLive() {
        let macMini = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output)
        let desk = AudioDevice(id: 2, uid: "desk", name: "Desk Speakers", type: .output)
        let service = FakeAudioService(devices: [macMini, desk])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(macMini, category: .speaker)
        manager.toggleMute(for: desk)

        manager.selectOutputDevice(desk, category: .speaker)

        XCTAssertEqual(manager.currentOutputId, desk.id)
        XCTAssertFalse(manager.isDeviceMuted(desk))
        XCTAssertTrue(service.isAudible(desk.id))
        XCTAssertGreaterThan(manager.volume, 0.01)
    }

    func testSelectingSeveralOutputsDoesNotAccumulateSelectionMutes() {
        let fifth = AudioDevice(id: 5, uid: "fifth", name: "Fifth", type: .output)
        let fourth = AudioDevice(id: 4, uid: "fourth", name: "Fourth", type: .output)
        let third = AudioDevice(id: 3, uid: "third", name: "Third", type: .output)
        let service = FakeAudioService(devices: [fifth, fourth, third])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )

        manager.cycleOutputPresentation(fifth, category: .speaker)
        manager.cycleOutputPresentation(fourth, category: .speaker)
        manager.cycleOutputPresentation(third, category: .speaker)

        XCTAssertFalse(manager.isDeviceMuted(fifth))
        XCTAssertFalse(manager.isDeviceMuted(fourth))
        XCTAssertTrue(manager.isDeviceMuted(third))
        XCTAssertEqual(manager.currentOutputId, third.id)
    }

    func testMuteAllMicrophonesTogglesAndRestoresInputDevices() {
        let q2u = AudioDevice(id: 5, uid: "q2u", name: "Samson Q2U", type: .input)
        let vocaster = AudioDevice(id: 4, uid: "vocaster", name: "Vocaster Two", type: .input)
        let service = FakeAudioService(devices: [q2u, vocaster])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )

        manager.setAllInputsMuted(true)

        XCTAssertTrue(manager.areAllInputsMuted)
        XCTAssertFalse(service.isAudible(q2u.id, type: .input))
        XCTAssertFalse(service.isAudible(vocaster.id, type: .input))

        manager.setAllInputsMuted(false)

        XCTAssertFalse(manager.areAllInputsMuted)
        XCTAssertTrue(service.isAudible(q2u.id, type: .input))
        XCTAssertTrue(service.isAudible(vocaster.id, type: .input))
    }

    func testMuteAllMicrophonesKeepsButtonStateWhenHardwareRefuses() {
        let interface = AudioDevice(id: 5, uid: "interface", name: "USB Interface", type: .input)
        let service = FakeAudioService(devices: [interface], behaviors: [interface.id: .ignoresWrites])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )

        manager.setAllInputsMuted(true)

        XCTAssertTrue(manager.areAllInputsMuted)
        XCTAssertFalse(manager.isDeviceMuted(interface), "the UI must not claim refused hardware is muted")
        XCTAssertTrue(manager.isDeviceUnmutable(interface))
    }

    // MARK: - Mute All by moving the output

    func testMuteAllMovesAudioToABuiltInOutputWhenTheCurrentOneWillNotMute() {
        let builtIn = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output, isBuiltIn: true)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let service = FakeAudioService(devices: [builtIn, display], behaviors: [display.id: .ignoresWrites])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(display, category: .speaker)
        XCTAssertTrue(service.isAudible(display.id))

        manager.setAllOutputsMuted(true)

        XCTAssertEqual(manager.currentOutputId, builtIn.id, "audio has to go somewhere it can actually be silenced")
        XCTAssertFalse(service.isAudible(builtIn.id))
        XCTAssertEqual(service.defaultOutputId, builtIn.id, "the machine is genuinely silent, not just reported as muted")
        XCTAssertEqual(manager.redirectedOutputName, "Mac mini Speakers")
        XCTAssertTrue(manager.areAllOutputsMuted)
    }

    func testUnmutingAllHandsTheOutputBackToWhereItWas() {
        let builtIn = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output, isBuiltIn: true)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let service = FakeAudioService(devices: [builtIn, display], behaviors: [display.id: .ignoresWrites])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(display, category: .speaker)
        manager.setAllOutputsMuted(true)

        manager.setAllOutputsMuted(false)

        XCTAssertEqual(manager.currentOutputId, display.id, "the user's device comes back")
        XCTAssertEqual(service.defaultOutputId, display.id)
        XCTAssertNil(manager.redirectedOutputName)
        XCTAssertTrue(service.isAudible(display.id))
    }

    func testTheOutputIsLeftAloneWhenTheUserMovedItThemselvesWhileMuted() {
        let builtIn = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output, isBuiltIn: true)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let desk = AudioDevice(id: 3, uid: "desk", name: "Desk Speakers", type: .output)
        let service = FakeAudioService(devices: [builtIn, display, desk], behaviors: [display.id: .ignoresWrites])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(display, category: .speaker)
        manager.setAllOutputsMuted(true)

        manager.selectOutputDevice(desk, category: .speaker)
        manager.setAllOutputsMuted(false)

        XCTAssertEqual(manager.currentOutputId, desk.id, "do not drag the user back to a device they moved away from")
    }

    func testTheOutputStaysPutWhenTheRedirectIsTurnedOff() {
        let builtIn = AudioDevice(id: 1, uid: "mac-mini", name: "Mac mini Speakers", type: .output, isBuiltIn: true)
        let display = AudioDevice(id: 2, uid: "display", name: "PL2792Q", type: .output)
        let service = FakeAudioService(devices: [builtIn, display], behaviors: [display.id: .ignoresWrites])
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(display, category: .speaker)
        manager.setRedirectMuteAllToBuiltIn(false)

        manager.setAllOutputsMuted(true)

        XCTAssertEqual(manager.currentOutputId, display.id)
        XCTAssertNil(manager.redirectedOutputName)
        XCTAssertEqual(manager.outputsIgnoringMute, ["PL2792Q"], "and it says so, rather than pretending")
    }

    func testNoRedirectWhenThereIsNowhereSilenceableToGo() {
        let display = AudioDevice(id: 1, uid: "display", name: "PL2792Q", type: .output)
        let vocaster = AudioDevice(id: 2, uid: "vocaster", name: "Vocaster Two", type: .output)
        let service = FakeAudioService(
            devices: [display, vocaster],
            behaviors: [display.id: .ignoresWrites, vocaster.id: .ignoresWrites]
        )
        let manager = AudioManager(
            deviceService: service,
            priorityManager: PriorityManager(defaults: isolatedDefaults())
        )
        manager.selectOutputDevice(display, category: .speaker)

        manager.setAllOutputsMuted(true)

        XCTAssertEqual(manager.currentOutputId, display.id)
        XCTAssertNil(manager.redirectedOutputName)
        XCTAssertTrue(manager.isDeviceIgnoringMute(display))
    }

    private func isolatedDefaults(keepPanelOpen: Bool? = nil) -> UserDefaults {
        let suite = "AudioPriorityBarXcodeTests.Manager"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if let keepPanelOpen {
            defaults.set(keepPanelOpen, forKey: "keepApplicationInForegroundAfterSourceChange")
        }
        return defaults
    }
}

/// How a piece of hardware responds to CoreAudio.
///
/// The obedient case is the one that always passed while the user still heard
/// sound, so the awkward ones are modelled here explicitly.
enum FakeDeviceBehavior {
    /// Mute and volume writes both stick.
    case compliant
    /// Accepts every write and changes nothing, like an HDMI display.
    case ignoresWrites
    /// Mute sticks, but the level cannot be read back at all.
    case noReadableVolume
}

private final class FakeAudioService: AudioDeviceServicing {
    var onDevicesChanged: (() -> Void)?
    var onMuteOrVolumeChanged: (() -> Void)?
    let devices: [AudioDevice]
    var volumeWrites: [(AudioObjectID, Float)] = []
    var behaviors: [AudioObjectID: FakeDeviceBehavior] = [:]
    /// CoreAudio scopes level and mute separately for input and output, so a
    /// USB microphone with a headphone jack has two independent sets of
    /// controls behind one device ID.
    private struct Scoped: Hashable {
        let id: AudioObjectID
        let type: AudioDeviceType
    }
    private var volumes: [Scoped: Float] = [:]
    private var muted: Set<Scoped> = []
    var defaultInputId: AudioObjectID = 1
    var defaultOutputId: AudioObjectID = 2

    var outputVolume: Float {
        get { getDeviceVolume(defaultOutputId, type: .output) }
        set { _ = setDeviceVolume(newValue, deviceId: defaultOutputId, type: .output, force: true) }
    }

    init(devices: [AudioDevice], behaviors: [AudioObjectID: FakeDeviceBehavior] = [:]) {
        self.devices = devices
        self.behaviors = behaviors
        for device in devices {
            volumes[Scoped(id: device.id, type: device.type)] = 0.5
        }
        if let output = devices.first(where: { $0.type == .output }) {
            defaultOutputId = output.id
        }
        if let input = devices.first(where: { $0.type == .input }) {
            defaultInputId = input.id
        }
    }

    private func behavior(_ deviceId: AudioObjectID) -> FakeDeviceBehavior {
        behaviors[deviceId] ?? .compliant
    }

    /// What the user would actually hear from this device.
    func isAudible(_ deviceId: AudioObjectID, type: AudioDeviceType = .output) -> Bool {
        let key = Scoped(id: deviceId, type: type)
        if muted.contains(key) { return false }
        return (volumes[key] ?? 0.5) > 0.01
    }

    /// Simulates the volume changing outside the app: the keyboard keys,
    /// System Settings, or the device's own knob.
    func simulateExternalVolumeChange(_ level: Float, deviceId: AudioObjectID, type: AudioDeviceType = .output) {
        let key = Scoped(id: deviceId, type: type)
        volumes[key] = level
        if level > 0.01 { muted.remove(key) }
        onMuteOrVolumeChanged?()
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
        readDeviceVolume(deviceId, type: type) ?? 1.0
    }
    func readDeviceVolume(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Float? {
        if behavior(deviceId) == .noReadableVolume { return nil }
        let key = Scoped(id: deviceId, type: type)
        if muted.contains(key) { return 0 }
        return volumes[key] ?? 0.5
    }
    func setDeviceVolume(_ volume: Float, deviceId: AudioObjectID, type: AudioDeviceType, force: Bool) -> Bool {
        volumeWrites.append((deviceId, volume))
        let key = Scoped(id: deviceId, type: type)
        switch behavior(deviceId) {
        case .ignoresWrites:
            // Accepted and discarded, exactly like a display that keeps playing.
            return false
        case .noReadableVolume:
            volumes[key] = volume
            // Nothing to read back, so the write cannot be claimed as verified.
            return false
        case .compliant:
            volumes[key] = volume
            if volume > 0.01 { muted.remove(key) }
            return true
        }
    }
    func supportsDeviceVolumeControl(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        behavior(deviceId) == .compliant
    }
    func isDeviceMuted(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        if muted.contains(Scoped(id: deviceId, type: type)) { return true }
        guard let level = readDeviceVolume(deviceId, type: type) else { return false }
        return level <= 0.01
    }
    func setDeviceMuted(_ shouldMute: Bool, deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        guard behavior(deviceId) != .ignoresWrites else { return false }
        let key = Scoped(id: deviceId, type: type)
        if shouldMute {
            muted.insert(key)
        } else {
            muted.remove(key)
        }
        return true
    }
    func startListening() {}
}
