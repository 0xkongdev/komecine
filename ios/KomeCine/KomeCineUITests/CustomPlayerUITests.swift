import XCTest

final class CustomPlayerUITests: XCTestCase {
    @MainActor private func openPlayer() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["KOMECINE_PLAYER_PREVIEW"] = "1"
        app.launch()
        return app
    }
    @MainActor func testSpeedPanelLockAndMinimize() {
        let app = openPlayer()
        XCTAssertTrue(app.buttons["player.fullscreen"].waitForExistence(timeout:8))
        app.buttons["player.fullscreen"].tap()
        let speed = app.buttons["player.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout:5))
        speed.tap()
        let choice = app.buttons["speed.1.5"]
        XCTAssertTrue(choice.waitForExistence(timeout:5))
        choice.tap()
        XCTAssertTrue(app.buttons["player.speed"].label.contains("1.5"))
        app.buttons["player.lock"].tap()
        XCTAssertFalse(app.buttons["player.speed"].exists)
        app.buttons["player.lock"].tap()
        app.buttons["player.more"].tap()
        app.buttons["player.minimize"].tap()
        XCTAssertTrue(app.buttons["mini.expand"].waitForExistence(timeout:5))
        app.buttons["mini.expand"].tap()
        XCTAssertTrue(app.buttons["player.fullscreen"].waitForExistence(timeout:5))
    }
    @MainActor func testFullscreenReturnsToPortraitAndVideoStaysMounted() {
        let app = openPlayer()
        let fullscreen = app.buttons["player.fullscreen"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout:8))
        fullscreen.tap()
        let window = app.windows.firstMatch
        let landscape = XCTNSPredicateExpectation(predicate:NSPredicate { _, _ in window.frame.width > window.frame.height }, object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[landscape], timeout:8), .completed)
        app.buttons["player.fullscreen"].tap()
        let portrait = XCTNSPredicateExpectation(predicate:NSPredicate { _, _ in window.frame.height > window.frame.width }, object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[portrait], timeout:8), .completed)
        XCTAssertTrue(app.otherElements["Video"].exists)
        let attachment = XCTAttachment(screenshot:app.screenshot())
        attachment.name = "Custom player portrait"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
