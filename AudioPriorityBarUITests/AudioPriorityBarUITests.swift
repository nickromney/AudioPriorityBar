import XCTest

final class AudioPriorityBarUITests: XCTestCase {
    func testFakeDeviceCanBeReorderedInMenuBarPanel() {
        let app = XCUIApplication()
        app.launchArguments = ["--verify-ui"]
        app.launch()

        // The status item must be installed; the panel itself is driven through the
        // --verify-ui window so the journey does not depend on free menu-bar space.
        XCTAssertTrue(app.statusItems["AudioPriorityBar.statusItem"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows["Audio Priority Bar Verify"].waitForExistence(timeout: 10))

        let speakerA = app.buttons["Verify Speaker A"]
        let speakerB = app.buttons["Verify Speaker B"]
        XCTAssertTrue(speakerA.waitForExistence(timeout: 5))
        XCTAssertTrue(speakerB.exists)
        // Priority order is shown top to bottom: A (built-in default) starts above B.
        XCTAssertLessThan(speakerA.frame.minY, speakerB.frame.minY)

        let moveUp = app.buttons["move-up-verify-speaker-b"]
        XCTAssertTrue(moveUp.waitForExistence(timeout: 5))
        moveUp.click()

        let reordered = NSPredicate { _, _ in speakerB.frame.minY < speakerA.frame.minY }
        let expectation = XCTNSPredicateExpectation(predicate: reordered, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Verify Speaker B should move above Verify Speaker A")
    }
}
