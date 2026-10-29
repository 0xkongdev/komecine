import XCTest

final class KomeCineUITests: XCTestCase {
    @MainActor func testRankingsOpenMatchedMovie() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let title = app.staticTexts["Top phim bộ hôm nay"]
        XCTAssertTrue(title.waitForExistence(timeout: 40))
        let first = app.buttons["ranking-series-1"]
        if !first.isHittable { app.swipeUp() }
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        let watch = app.buttons["Xem ngay"].exists ? app.buttons["Xem ngay"] : app.buttons["Tiếp tục xem"]
        XCTAssertTrue(watch.waitForExistence(timeout: 30), "A matched ranking should open a playable movie")
    }
    @MainActor func testHomeContentFitsScreen() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let featured = app.staticTexts["NỔI BẬT HÔM NAY"]
        XCTAssertTrue(featured.waitForExistence(timeout: 30))
        let bounds = app.windows.firstMatch.frame
        let shelf = app.staticTexts["Mới cập nhật"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(shelf.frame.minX, bounds.minX, "Shelf heading must remain visible")
        XCTAssertLessThanOrEqual(shelf.frame.maxX, bounds.maxX, "Shelf heading must fit on screen")
    }

    @MainActor func testHomePlayStartsVideo() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let play = app.buttons["Xem ngay"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        XCTAssertTrue(app.buttons["Khóa player"].waitForExistence(timeout: 20), "Watch now should open the player")
    }

    @MainActor func testLandscapePlayerUsesScreenWidth() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let movie = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Xóm Nhỏ")).firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 30))
        movie.tap()
        let play = app.buttons["Xem ngay"].exists ? app.buttons["Xem ngay"] : app.buttons["Tiếp tục xem"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        play.tap()
        let video = app.descendants(matching: .any).matching(identifier: "Video").firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 30))
        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && window.frame.width < window.frame.height {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(window.frame.width, window.frame.height, "Simulator should rotate to landscape")
        XCTAssertGreaterThan(video.frame.width, window.frame.width * 0.8, "Video should use most of the landscape screen")
        XCTAssertTrue(app.buttons["Khóa player"].exists)
    }

    @MainActor func testNavigationAndCatalog() throws {
        let app=XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Trang chủ"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["Mới cập nhật"].waitForExistence(timeout:30),"Home should load KKPhim catalog")
        app.tabBars.buttons["Khám phá"].tap()
        XCTAssertTrue(app.staticTexts["Tìm câu chuyện\nbạn yêu thích."].waitForExistence(timeout:10))
        app.tabBars.buttons["Thư viện"].tap()
        XCTAssertTrue(app.staticTexts["Thư viện của bạn"].waitForExistence(timeout:10))
    }
}
