import XCTest
@testable import AudioPriorityBarCore

final class PriorityManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: PriorityManager!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AudioPriorityBarCoreTests")!
        defaults.removePersistentDomain(forName: "AudioPriorityBarCoreTests")
        manager = PriorityManager(defaults: defaults)
    }

    func testNeverUseRoundTripsByUID() {
        let device = AudioDevice(id: 1, uid: "speaker-1", name: "Desk", type: .output)

        XCTAssertFalse(manager.isNeverUse(device))
        manager.setNeverUse(device, neverUse: true)
        XCTAssertTrue(manager.isNeverUse(device))
        manager.setNeverUse(device, neverUse: false)
        XCTAssertFalse(manager.isNeverUse(device))
    }

    func testOutputPrioritiesRemainSeparateByCategory() {
        let speaker = AudioDevice(id: 1, uid: "speaker", name: "Desk", type: .output)
        let headphones = AudioDevice(id: 2, uid: "headphones", name: "Headphones", type: .output)

        manager.savePriorities([speaker], category: .speaker)
        manager.savePriorities([headphones], category: .headphone)

        XCTAssertEqual(manager.sortByPriority([speaker], category: .speaker), [speaker])
        XCTAssertEqual(manager.sortByPriority([headphones], category: .headphone), [headphones])
    }

    func testPerCategoryIgnoreDoesNotHideDeviceFromOtherCategory() {
        let device = AudioDevice(id: 1, uid: "shared", name: "Shared", type: .output)

        manager.hideDevice(device, inCategory: .speaker)

        XCTAssertTrue(manager.isHidden(device, inCategory: .speaker))
        XCTAssertFalse(manager.isHidden(device, inCategory: .headphone))
    }

    func testDeviceLevelIsClampedAndStoredPerUID() {
        manager.saveDeviceLevel(2, for: "mic")
        XCTAssertEqual(manager.deviceLevel(for: "mic"), 1)

        manager.saveDeviceLevel(-1, for: "speaker")
        XCTAssertEqual(manager.deviceLevel(for: "speaker"), 0)
    }

    func testSavePrioritiesKeepsDisconnectedKnownUIDsInOrder() {
        let first = AudioDevice(id: 1, uid: "first", name: "First", type: .input)
        let second = AudioDevice(id: 2, uid: "second", name: "Second", type: .input)
        let replacement = AudioDevice(id: 3, uid: "replacement", name: "Replacement", type: .input)

        manager.savePriorities([first, second], type: .input)
        manager.savePriorities([replacement, second], type: .input)

        XCTAssertEqual(
            manager.sortByPriority([first, second, replacement], type: .input),
            [first, second, replacement]
        )
    }

    func testUIDMigrationMovesStoredPreferencesAndCategory() {
        let old = AudioDevice(id: 1, uid: "old", name: "USB Mic", type: .input)
        let new = AudioDevice(id: 2, uid: "new", name: "USB Mic", type: .input)

        manager.rememberDevice(old.uid, name: old.name, isInput: true)
        manager.setNeverUse(old, neverUse: true)
        manager.saveDeviceLevel(0.4, for: old.uid)
        manager.migrateDeviceUIDIfNeeded(uid: new.uid, name: new.name, isInput: true)

        XCTAssertTrue(manager.isNeverUse(new))
        XCTAssertEqual(manager.deviceLevel(for: new.uid), 0.4)
        XCTAssertNil(manager.getStoredDevice(uid: old.uid))
    }

    func testDefaultsExposeSafeFirstLaunchValues() {
        XCTAssertEqual(manager.currentMode, .speaker)
        XCTAssertEqual(manager.defaultOutputCategory, .speaker)
        XCTAssertTrue(manager.areDeviceLevelsEnabled)
        XCTAssertTrue(manager.isEnormousMode)
        XCTAssertFalse(manager.isCustomMode)
        XCTAssertFalse(manager.keepMutedWhenChangingSelection)
    }
}
