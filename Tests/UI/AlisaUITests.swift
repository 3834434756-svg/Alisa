import XCTest

final class AlisaUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testOnboardingFlow() throws {
        XCTAssertTrue(app.staticTexts["Alisa"].waitForExistence(timeout: 5))
    }

    func testMainTabs() throws {
        XCTAssertTrue(app.tabBars.buttons["项目"].exists)
        XCTAssertTrue(app.tabBars.buttons["编辑器"].exists)
        XCTAssertTrue(app.tabBars.buttons["对话"].exists)
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)
    }
}