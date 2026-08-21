import XCTest
@testable import AudioPriorityBarCore

final class AudioDeviceTests: XCTestCase {
    func testUSBCompositeOutputsWithTheSameSerialAreTheSameHardware() {
        let first = AudioDevice(
            id: 5,
            uid: "AppleUSBAudioEngine:Samson Technologies:Samson Q2U Microphone:14100000:1",
            name: "Samson Q2U Microphone",
            type: .output
        )
        let second = AudioDevice(
            id: 6,
            uid: "AppleUSBAudioEngine:Samson Technologies:Samson Q2U Microphone:14100000:2",
            name: "Samson Q2U Microphone",
            type: .output
        )

        XCTAssertTrue(first.isSameHardware(as: second))
        XCTAssertEqual(AudioDevice.uniqued([first, second], preferring: 6).map(\.id), [6])
        XCTAssertEqual(AudioDevice.uniqued([first, second]).map(\.id), [5])
    }

    func testDistinctDevicesKeepSeparateRowsEvenWithTheSameName() {
        let builtIn = AudioDevice(id: 1, uid: "BuiltInSpeakerDevice", name: "Mac mini Speakers", type: .output)
        let display = AudioDevice(id: 2, uid: "DisplayAudio-123", name: "Mac mini Speakers", type: .output)

        XCTAssertFalse(builtIn.isSameHardware(as: display))
        XCTAssertEqual(AudioDevice.uniqued([builtIn, display]).map(\.id), [1, 2])
    }

    func testInputAndOutputOfTheSameUSBDeviceStaySeparate() {
        let input = AudioDevice(
            id: 5,
            uid: "AppleUSBAudioEngine:Samson Technologies:Samson Q2U Microphone:14100000:1",
            name: "Samson Q2U Microphone",
            type: .input
        )
        let output = AudioDevice(
            id: 5,
            uid: "AppleUSBAudioEngine:Samson Technologies:Samson Q2U Microphone:14100000:1",
            name: "Samson Q2U Microphone",
            type: .output
        )

        XCTAssertFalse(input.isSameHardware(as: output))
        XCTAssertEqual(AudioDevice.uniqued([input, output]).count, 2)
    }

    func testNamedMicrophoneOutputsCollapseEvenWithoutUSBUIDs() {
        let first = AudioDevice(id: 5, uid: "uid-a", name: "Samson Q2U Microphone", type: .output)
        let second = AudioDevice(id: 6, uid: "uid-b", name: "Samson Q2U Microphone", type: .output)

        XCTAssertTrue(first.isSameHardware(as: second))
        XCTAssertEqual(AudioDevice.uniqued([first, second]).map(\.id), [5])
    }
}
