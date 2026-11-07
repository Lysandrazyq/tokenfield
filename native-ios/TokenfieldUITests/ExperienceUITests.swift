import XCTest

final class ExperienceUITests: XCTestCase {
    @MainActor
    func testSwipeDismissingWelcomeIsRememberedAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-data", "--reset-onboarding"]
        app.launch()
        let skip = app.buttons["welcome.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        let start = skip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: end)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: skip)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        guard !skip.exists else { return }
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["home.add-account"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["welcome.skip"].exists, "An intentional swipe dismissal must be remembered too.")
    }

    @MainActor
    func testWelcomeCanBeSkippedAndGuideReopenedWithoutRepeatingOnRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-data", "--reset-onboarding"]
        app.launch()
        let skip = app.buttons["welcome.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 12), "First launch should explain the app and allow skipping.")
        guard skip.exists else { return }
        skip.tap()
        XCTAssertTrue(app.buttons["home.add-account"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["home.add-account"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["welcome.skip"].exists)
        app.buttons["设置"].tap()
        let guide = app.buttons["settings.guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.tap()
        XCTAssertTrue(app.descendants(matching: .any)["guide.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "手动记录")).firstMatch.exists)
    }

    @MainActor
    func testNewServiceHasProgressiveSetupAndDraftSurvivesRotationAndBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-data", "--skip-onboarding"]
        app.launch()
        app.buttons["home.add-account"].tap()
        let field = app.textFields["account.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -1, dy: 0)).tap()
        let existing = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Duo Draft")
        XCTAssertEqual(field.value as? String, "Duo Draft")
        let next = app.buttons["account.next"].exists ? app.buttons["account.next"] : app.buttons["account.keyboard-next"]
        XCTAssertTrue(next.exists, "New accounts should use a short, progressive setup.")
        guard next.exists else { return }
        next.tap()
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 5))
        app.buttons["account.back"].tap()
        XCTAssertEqual(app.textFields["account.name"].value as? String, "Duo Draft")
        app.buttons["editor.cancel"].tap()
        XCTAssertFalse(app.staticTexts["Duo Draft"].exists)
        XCUIDevice.shared.orientation = .portrait
    }
}
