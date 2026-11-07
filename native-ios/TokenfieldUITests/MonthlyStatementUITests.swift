import XCTest

final class MonthlyStatementUITests: XCTestCase {
    @MainActor
    func testManualStatementWithoutLiveAccountsValidatesAndConfirmsChanges() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-onboarding", "--reset-ui-data"]
        app.launch()
        XCTAssertTrue(app.buttons["月报"].waitForExistence(timeout: 15))
        app.buttons["月报"].tap()
        let add = app.buttons["report.add-history"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.buttons["statement.add-row"].waitForExistence(timeout: 5))
        app.buttons["statement.add-row"].tap()
        let name = app.textFields["statement.row-name"].firstMatch
        let cost = app.textFields["statement.row-cost"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Historical AI")
        replace(cost, with: "-1")
        app.buttons["statement.save"].tap()
        XCTAssertTrue(app.staticTexts["statement.validation"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["statement.save"].exists)
        replace(cost, with: "18.5")
        app.buttons["statement.save"].tap()
        let edit = app.buttons["report.edit-history"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["report.share"].isEnabled)
        XCTAssertTrue(app.staticTexts["Historical AI"].exists)

        edit.tap()
        XCTAssertTrue(app.staticTexts["statement.locked-month"].waitForExistence(timeout: 5))
        replace(app.textFields["statement.row-cost"].firstMatch, with: "27")
        app.buttons["statement.save"].tap()
        let overwrite = app.buttons["覆盖保存"]
        XCTAssertTrue(overwrite.waitForExistence(timeout: 3))
        cancelConfirmation(in: app)
        XCTAssertTrue(app.buttons["statement.save"].exists)
        app.buttons["statement.save"].tap()
        XCTAssertTrue(overwrite.waitForExistence(timeout: 3))
        overwrite.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["月报"].waitForExistence(timeout: 15))
        app.buttons["月报"].tap()
        app.buttons["report.month-picker"].tap()
        let savedMonth = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "report.month.")).firstMatch
        XCTAssertTrue(savedMonth.waitForExistence(timeout: 3))
        savedMonth.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Historical AI"].exists)
        app.buttons["report.delete-history"].tap()
        XCTAssertTrue(app.buttons["删除月报"].waitForExistence(timeout: 3))
        cancelConfirmation(in: app)
        XCTAssertTrue(edit.exists)
        app.buttons["report.delete-history"].tap()
        app.buttons["删除月报"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(edit.exists)
        XCTAssertFalse(app.buttons["report.share"].isEnabled)
        app.buttons["概览"].tap()
        XCTAssertFalse(app.staticTexts["Historical AI"].exists)
    }

    @MainActor
    private func cancelConfirmation(in app: XCUIApplication) {
        let buttons = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"]))
        if buttons.firstMatch.waitForExistence(timeout: 3) {
            buttons.element(boundBy: buttons.count - 1).tap()
            return
        }
        // iOS popovers expose cancellation as their outside dismissal region.
        let outside = app.otherElements["PopoverDismissRegion"]
        if outside.exists {
            outside.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.7)).tap()
            return
        }
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("系统取消按钮或弹出窗口关闭区域未出现。")
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -1, dy: 0)).tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
        XCTAssertEqual(field.value as? String, text)
    }
}
