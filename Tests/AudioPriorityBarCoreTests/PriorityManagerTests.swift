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

    func testLegacyDebugImportPreservesExistingPreferencesAndSkipsStatusItemState() {
        manager.defaultOutputCategory = .headphone
        manager.importLegacyDebugPreferences([
            "defaultOutputCategory": "speaker",
            "speakerPriorities": ["desk", "display"],
            "NSStatusItem Preferred Position AudioPriorityBar.main": 120,
            "NSStatusItem Visible AudioPriorityBar.main": false
        ])
        XCTAssertEqual(manager.defaultOutputCategory, .headphone)
        XCTAssertEqual(defaults.stringArray(forKey: "speakerPriorities"), ["desk", "display"])
        XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position AudioPriorityBar.main"))
        XCTAssertNil(defaults.object(forKey: "NSStatusItem Visible AudioPriorityBar.main"))

        defaults.removeObject(forKey: "speakerPriorities")
        manager.importLegacyDebugPreferences(["speakerPriorities": ["old"]])
        XCTAssertNil(defaults.object(forKey: "speakerPriorities"))
    }

    func testPanelSectionsDefaultToAllAndPersistInDisplayOrder() {
        XCTAssertEqual(manager.visibleDeviceTabs, DeviceTab.allCases)
        manager.visibleDeviceTabs = [.microphone, .speaker, .speaker]
        XCTAssertEqual(PriorityManager(defaults: defaults).visibleDeviceTabs, [.speaker, .microphone])
    }

    func testPanelCannotHideEverySection() {
        manager.visibleDeviceTabs = [.microphone]
        manager.visibleDeviceTabs = []
        XCTAssertEqual(manager.visibleDeviceTabs, [.microphone])
        XCTAssertEqual(manager.defaultDeviceTab, .microphone)
    }

    func testHiddenDefaultFallsBackWithoutLosingPreferredTab() {
        manager.defaultOutputCategory = .headphone
        XCTAssertEqual(manager.defaultDeviceTab, .headphone)
        manager.defaultDeviceTab = .microphone
        manager.visibleDeviceTabs = [.speaker]
        XCTAssertEqual(manager.defaultDeviceTab, .speaker)
        manager.defaultDeviceTab = .headphone
        manager.visibleDeviceTabs = [.speaker, .microphone]
        XCTAssertEqual(manager.defaultDeviceTab, .microphone)
    }

    func testInvalidStoredSectionsRecoverToAUsablePanel() {
        defaults.set(["unknown"], forKey: "visibleDeviceTabs")
        XCTAssertEqual(manager.visibleDeviceTabs, DeviceTab.allCases)
        defaults.set([], forKey: "visibleDeviceTabs")
        XCTAssertFalse(manager.visibleDeviceTabs.isEmpty)
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
        XCTAssertTrue(manager.keepApplicationInForegroundAfterSourceChange)
    }
}

extension PriorityManagerTests {
    func testReorderingVisibleDevicesPersists() {
        let a = AudioDevice(id: 1, uid: "a", name: "A", type: .output)
        let b = AudioDevice(id: 2, uid: "b", name: "B", type: .output)
        let c = AudioDevice(id: 3, uid: "c", name: "C", type: .output)
        manager.savePriorities([a, b, c], category: .speaker)

        // Move C up one place, the way the row arrows do.
        manager.savePriorities([a, c, b], category: .speaker)

        XCTAssertEqual(
            manager.sortByPriority([a, b, c], category: .speaker).map(\.uid),
            ["a", "c", "b"],
            "a reorder that does not survive the next refresh is not a reorder"
        )
    }

    func testReorderingKeepsADisconnectedDeviceInItsSlot() {
        let a = AudioDevice(id: 1, uid: "a", name: "A", type: .output)
        let gone = AudioDevice(id: 2, uid: "gone", name: "Gone", type: .output)
        let b = AudioDevice(id: 3, uid: "b", name: "B", type: .output)
        let c = AudioDevice(id: 4, uid: "c", name: "C", type: .output)
        manager.savePriorities([a, gone, b, c], category: .speaker)

        // "gone" is no longer connected, so it is not on screen to be reordered.
        manager.savePriorities([a, c, b], category: .speaker)

        XCTAssertEqual(
            manager.sortByPriority([a, gone, b, c], category: .speaker).map(\.uid),
            ["a", "gone", "c", "b"]
        )
    }
}
