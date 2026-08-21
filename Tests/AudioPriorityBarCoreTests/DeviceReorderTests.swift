import XCTest
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
