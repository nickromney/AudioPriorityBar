import XCTest
@testable import AudioPriorityBarCore

final class MuteLedgerTests: XCTestCase {
    private let macMini = MuteKey(type: .output, uid: "mac-mini")
    private let display = MuteKey(type: .output, uid: "display")
    private let mic = MuteKey(type: .input, uid: "q2u")

    func testMuteAllLatchCoversOutputsButNotInputs() {
        var ledger = MuteLedger()
        ledger.engageAllOutputs()

        XCTAssertTrue(ledger.wantsMuted(macMini))
        XCTAssertTrue(ledger.wantsMuted(display))
        XCTAssertFalse(ledger.wantsMuted(mic))
    }

    func testReleasingTheLatchKeepsIndividuallyMutedDevicesMuted() {
        var ledger = MuteLedger()
        ledger.setIntent(muted: true, for: display)
        ledger.engageAllOutputs()
        XCTAssertTrue(ledger.wantsMuted(macMini))

        ledger.releaseAllOutputs()

        XCTAssertFalse(ledger.wantsMuted(macMini), "the latch silenced it, so releasing the latch frees it")
        XCTAssertTrue(ledger.wantsMuted(display), "the user muted this one by hand")
    }

    func testOnlyLatchMutedDevicesAreRestoredWhenTheLatchDrops() {
        var ledger = MuteLedger()
        ledger.setIntent(muted: true, for: display)
        ledger.engageAllOutputs()

        XCTAssertTrue(ledger.isMutedOnlyByAllOutputs(macMini))
        XCTAssertFalse(ledger.isMutedOnlyByAllOutputs(display))
    }

    func testUnmuteAllClearsHandMutedDevicesToo() {
        var ledger = MuteLedger()
        ledger.setIntent(muted: true, for: display)
        ledger.engageAllOutputs()

        ledger.releaseAllOutputsAndIntents()

        XCTAssertFalse(ledger.wantsMuted(display))
        XCTAssertFalse(ledger.wantsMuted(macMini))
    }

    func testADeviceThatRefusedTheMuteIsReportedAsStillAudible() {
        var ledger = MuteLedger()
        ledger.engageAllOutputs()
        ledger.record(.silenced, for: macMini)
        ledger.record(.refused, for: display)

        XCTAssertFalse(ledger.isKnownAudibleDespiteIntent(macMini))
        XCTAssertTrue(ledger.isKnownAudibleDespiteIntent(display))
        XCTAssertEqual(ledger.refusedKeys(), [display])
    }

    func testRefusalsAreForgottenOnceTheDeviceIsUnmuted() {
        var ledger = MuteLedger()
        ledger.setIntent(muted: true, for: display)
        ledger.record(.refused, for: display)

        ledger.setIntent(muted: false, for: display)

        XCTAssertTrue(ledger.refusedKeys().isEmpty)
        XCTAssertFalse(ledger.isKnownAudibleDespiteIntent(display))
    }

    func testRestoredVolumeNeverLandsOnSilence() {
        XCTAssertEqual(MuteLedger.usableRestoredVolume(saved: 0.42, current: 0, fallback: 0), 0.42, accuracy: 0.001)
        XCTAssertEqual(MuteLedger.usableRestoredVolume(saved: 0, current: 0.3, fallback: 0), 0.3, accuracy: 0.001)
        XCTAssertEqual(MuteLedger.usableRestoredVolume(saved: nil, current: nil, fallback: 0.2), 0.2, accuracy: 0.001)
        XCTAssertEqual(MuteLedger.usableRestoredVolume(saved: 0, current: 0, fallback: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(
            MuteLedger.usableRestoredVolume(saved: nil, current: nil, fallback: 0),
            0.5,
            accuracy: 0.001,
            "an unreadable device must not restore to zero"
        )
    }

    func testSavingASilentLevelIsIgnored() {
        var ledger = MuteLedger()
        ledger.saveLevel(0.6, for: macMini)
        ledger.saveLevel(0, for: macMini)

        XCTAssertEqual(ledger.savedLevel(for: macMini), 0.6)
    }

    func testVolumeRisingElsewhereCountsAsTheUserUnmuting() {
        var ledger = MuteLedger()
        ledger.setIntent(muted: true, for: macMini)
        ledger.record(.silenced, for: macMini)

        XCTAssertTrue(ledger.externalUnmuteDetected(for: macMini, level: 0.4))
        XCTAssertFalse(ledger.externalUnmuteDetected(for: macMini, level: 0))
    }

    func testADeviceThatIgnoredTheMuteIsNotTreatedAsExternallyUnmuted() {
        var ledger = MuteLedger()
        ledger.engageAllOutputs()
        ledger.record(.refused, for: display)

        XCTAssertFalse(
            ledger.externalUnmuteDetected(for: display, level: 0.58),
            "the display never went quiet, so its level says nothing about intent"
        )
    }

    func testKeysDistinguishInputAndOutputOnTheSameHardware() {
        var ledger = MuteLedger()
        let q2uOutput = MuteKey(type: .output, uid: "q2u")

        ledger.setIntent(muted: true, for: mic)

        XCTAssertTrue(ledger.wantsMuted(mic))
        XCTAssertFalse(ledger.wantsMuted(q2uOutput), "muting the mic must not silence the headphone jack")
    }
}

extension MuteLedgerTests {
    func testLettingOneDeviceThroughLeavesTheRestMuted() {
        let macMini = MuteKey(type: .output, uid: "mac-mini")
        let display = MuteKey(type: .output, uid: "display")
        var ledger = MuteLedger()
        ledger.engageAllOutputs()

        ledger.pinLatchAsIntents([macMini, display])
        ledger.setIntent(muted: false, for: macMini)

        XCTAssertFalse(ledger.wantsMuted(macMini))
        XCTAssertTrue(ledger.wantsMuted(display), "Mute All must not be undone by unmuting one device")
        XCTAssertFalse(ledger.allOutputsEngaged)
    }
}
