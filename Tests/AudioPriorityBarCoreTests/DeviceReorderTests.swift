import XCTest
// `Array.move(fromOffsets:toOffset:)` is a SwiftUI extension, and these tests
// exercise the indices the app hands to it.
import SwiftUI
@testable import AudioPriorityBarCore

final class DeviceReorderTests: XCTestCase {
    func testDroppingALaterItemOntoTheFirstMovesItToTheFront() {
        let move = DeviceReorder.move(draggingUID: "d", ontoUID: "a", in: ["a", "b", "c", "d"])
        XCTAssertEqual(move?.from, IndexSet(integer: 3))
        XCTAssertEqual(move?.to, 0)
    }

    func testDroppingTheFirstItemOntoTheThirdPlacesItThird() {
        let move = DeviceReorder.move(draggingUID: "a", ontoUID: "c", in: ["a", "b", "c", "d"])
        XCTAssertEqual(move?.from, IndexSet(integer: 0))
        XCTAssertEqual(move?.to, 3)
    }

    func testDroppingAnItemOntoItselfDoesNothing() {
        XCTAssertNil(DeviceReorder.move(draggingUID: "b", ontoUID: "b", in: ["a", "b", "c"]))
    }

    func testUnknownUIDDoesNotMove() {
        XCTAssertNil(DeviceReorder.move(draggingUID: "missing", ontoUID: "a", in: ["a", "b"]))
    }
}

extension DeviceReorderTests {
    func testMovingUpAndDownOneStep() {
        var uids = ["a", "b", "c"]

        let down = DeviceReorder.moveDown(index: 0, count: uids.count)
        XCTAssertNotNil(down)
        uids.move(fromOffsets: down!.from, toOffset: down!.to)
        XCTAssertEqual(uids, ["b", "a", "c"])

        let up = DeviceReorder.moveUp(index: 2, count: uids.count)
        XCTAssertNotNil(up)
        uids.move(fromOffsets: up!.from, toOffset: up!.to)
        XCTAssertEqual(uids, ["b", "c", "a"])
    }

    func testTheEndsOfTheListHaveNowhereToGo() {
        XCTAssertNil(DeviceReorder.moveUp(index: 0, count: 3))
        XCTAssertNil(DeviceReorder.moveDown(index: 2, count: 3))
        XCTAssertNil(DeviceReorder.moveDown(index: 0, count: 1))
    }
}
