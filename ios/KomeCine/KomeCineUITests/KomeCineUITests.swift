import XCTest

final class KomeCineUITests: XCTestCase {
    @MainActor func testFullscreenButtonRotatesWithoutTurningDevice() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Khám phá"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Xóm Nhỏ")
        let movie = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Xóm Nhỏ")).firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 30))
        movie.tap()
        let play = app.buttons.matching(NSPredicate(format: "label IN %@", ["Xem ngay", "Tiếp tục xem"])).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        XCTAssertTrue(app.buttons["Khóa player"].waitForExistence(timeout: 30))
        let video = app.descendants(matching: .any).matching(identifier: "Video").firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        let fullscreen = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'full' OR label CONTAINS[c] 'toàn màn hình'"
        )).firstMatch
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 20), app.debugDescription)
        fullscreen.tap()
        let window = app.windows.firstMatch
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.frame.width > window.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed,
                       "Fullscreen must rotate to landscape while the device stays portrait")
        let exit = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'full' OR label CONTAINS[c] 'toàn màn hình' OR label IN %@", ["Done", "Close", "Xong", "Đóng"]
        )).firstMatch
        if !exit.isHittable {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
        XCTAssertTrue(exit.waitForExistence(timeout: 5), app.debugDescription)
        exit.tap()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.frame.height > window.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 10), .completed,
                       "Leaving fullscreen must restore the original portrait orientation")
    }

    @MainActor func testPlayerControlsHideRevealAndLock() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        app.tabBars.buttons["Khám phá"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Xóm Nhỏ")
        let movie = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Xóm Nhỏ")).firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 30))
        movie.tap()
        let play = app.buttons.matching(NSPredicate(format: "label IN %@", ["Xem ngay", "Tiếp tục xem"])).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        let lock = app.buttons["Khóa player"]
        XCTAssertTrue(lock.waitForExistence(timeout: 30))
        let portrait = XCTAttachment(screenshot: app.screenshot())
        portrait.name = "Player portrait controls"
        portrait.lifetime = .keepAlways
        add(portrait)

        let hidden = NSPredicate { _, _ in !lock.exists }
        let hidesControls = XCTNSPredicateExpectation(predicate: hidden, object: nil)
        guard XCTWaiter.wait(for: [hidesControls], timeout: 7) == .completed else {
            XCTFail("Player controls should disappear without interaction")
            return
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        let video = app.descendants(matching: .any).matching(identifier: "Video").firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
        lock.tap()
        let unlock = app.buttons["Mở khóa player"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Đóng"].exists)
        XCTAssertFalse(app.buttons["Chọn tập"].exists)
        expectation(for: NSPredicate { _, _ in !unlock.exists }, evaluatedWith: nil)
        waitForExpectations(timeout: 7)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        unlock.tap()
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Đóng"].exists)
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Player landscape controls"
        landscape.lifetime = .keepAlways
        add(landscape)

        app.buttons["Chọn tập"].tap()
        let done = app.buttons["Xong"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        let pickerDisappears = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !done.exists }, object: nil)
        pickerDisappears.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [pickerDisappears], timeout: 4), .completed)
        done.tap()
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
    }

    @MainActor func testMovieDetailContentFitsScreen() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let details = app.buttons["Chi tiết"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 40))
        details.tap()
        let play = app.buttons.matching(NSPredicate(format: "label IN %@", ["Xem ngay", "Tiếp tục xem"])).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30))

        // Keep checking while the asynchronous backdrop loads and updates the layout.
        let bounds = app.windows.firstMatch.frame
        let overflow = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            play.frame.minX < bounds.minX + 16 || play.frame.maxX > bounds.maxX - 16
        }, object: nil)
        overflow.isInverted = true
        wait(for: [overflow], timeout: 10)
        let content = app.scrollViews.firstMatch
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Movie detail layout"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThanOrEqual(play.frame.minX, bounds.minX + 16, "Watch button must keep its leading inset")
        XCTAssertLessThanOrEqual(play.frame.maxX, bounds.maxX - 16, "Watch button must fit on screen")
        let texts = content.staticTexts.allElementsBoundByIndex
        XCTAssertFalse(texts.isEmpty)
        for text in texts where !text.frame.isEmpty {
            XCTAssertGreaterThanOrEqual(text.frame.minX, bounds.minX + 16, "Detail text must keep its leading inset: \(text.label.prefix(50))")
            XCTAssertLessThanOrEqual(text.frame.maxX, bounds.maxX - 16, "Detail text must fit on screen: \(text.label.prefix(50))")
        }
    }

    @MainActor func testFeaturedCarouselAdvancesAutomatically() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let first = app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@", "Phim nổi bật 1 trên ")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 40), "Featured movies should load")
        let second = app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@", "Phim nổi bật 2 trên ")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 8), "Featured movies should advance without a swipe")
    }

    @MainActor func testFeaturedCarouselAndPlayback() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let first = app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@", "Phim nổi bật 1 trên ")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 40), "RoPhim featured movies should load")
        app.swipeLeft()
        let second = app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@", "Phim nổi bật 2 trên ")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 10), "Swiping should show another featured movie")
        app.swipeRight()
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        app.buttons["Xem ngay"].tap()
        XCTAssertTrue(app.buttons["Khóa player"].waitForExistence(timeout: 30), "Featured playback should open the native player")
    }
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
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.buttons["Khóa player"].exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.buttons["Khóa player"].waitForExistence(timeout: 3))
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
