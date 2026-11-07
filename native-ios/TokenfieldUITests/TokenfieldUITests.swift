import XCTest

final class TokenfieldUITests: XCTestCase {
    @MainActor
    func testAccountCancellationSaveUsageAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-onboarding", "--reset-ui-data"]
        app.launch()
        let add = app.buttons["home.add-account"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let name = app.textFields["account.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Cancelled Account")
        app.buttons["editor.cancel"].tap()
        XCTAssertFalse(app.staticTexts["Cancelled Account"].exists)

        app.buttons["home.add-account"].tap()
        let field = app.textFields["account.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.2)
        if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        else if app.menuItems["全选"].exists { app.menuItems["全选"].tap() }
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "Native Test")
        let next = app.buttons["account.next"].exists ? app.buttons["account.next"] : app.buttons["account.keyboard-next"]
        XCTAssertTrue(next.exists)
        next.tap()
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["Native Test"].waitForExistence(timeout: 5))
        let log = app.buttons["home.log.chat"]
        XCTAssertTrue(log.exists)
        log.tap()
        XCTAssertTrue(app.staticTexts["今天 1 次"].waitForExistence(timeout: 3))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-onboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Native Test"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["今天 1 次"].exists)
        let undo = app.buttons["home.undo-usage"]
        XCTAssertTrue(undo.exists)
        undo.tap()
        XCTAssertTrue(app.staticTexts["今天 0 次"].waitForExistence(timeout: 3))
        XCTAssertFalse(undo.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Native Test"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["今天 0 次"].exists)
        XCTAssertFalse(app.buttons["home.undo-usage"].exists)
    }

    @MainActor
    func testNativeTabsAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-onboarding", "--reset-ui-data"]
        app.launch()
        XCTAssertTrue(app.buttons["比价"].waitForExistence(timeout: 10))
        app.buttons["比价"].tap()
        XCTAssertTrue(app.staticTexts["会员还是按量？"].waitForExistence(timeout: 5))
        app.buttons["月报"].tap()
        XCTAssertTrue(app.buttons["report.share"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["report.share"].isEnabled)
        app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "iCloud 尚未启用")).firstMatch.waitForExistence(timeout: 5))
        let export = app.buttons["settings.export"]
        for _ in 0..<6 {
            if export.exists && export.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(export.isHittable)
        XCTAssertTrue(app.buttons["settings.import"].exists)
    }

    @MainActor
    func testExpiryCompletionCanBeReopened() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-onboarding", "--reset-ui-data"]
        app.launch()
        let add = app.buttons["home.add-expiry"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.textFields["expiry.title"].waitForExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.event.expiry-")).firstMatch.exists)

        add.tap()
        app.buttons["editor.save"].tap()
        let event = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.event.expiry-")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.tap()
        let done = app.switches["expiry.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let nativeDone = done.switches.firstMatch
        (nativeDone.exists ? nativeDone : done).tap()
        XCTAssertEqual(done.value as? String, "1")
        app.buttons["editor.save"].tap()
        XCTAssertFalse(event.exists)
        app.swipeUp()
        let completed = app.buttons["已完成到期项（1）"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        completed.tap()
        app.buttons["完全重置券"].tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.value as? String, "1")
        (nativeDone.exists ? nativeDone : done).tap()
        XCTAssertEqual(done.value as? String, "0")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-onboarding"]
        app.launch()
        XCTAssertTrue(event.waitForExistence(timeout: 10))
    }
}
