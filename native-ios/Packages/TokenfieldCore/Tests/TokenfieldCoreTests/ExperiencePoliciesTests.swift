import XCTest
@testable import TokenfieldCore

final class ExperiencePoliciesTests: XCTestCase {
    func testWelcomeDoesNotTreatHistoryExpiryOrPersonalizedSettingsAsNewUser() {
        let history = MonthlyStatement(month: "2026-10", accounts: [], settings: AppSettings())
        let backups = [
            Backup(accounts: [Account(id: 1, name: "Existing")]),
            Backup(expiries: [Expiry(id: 1, title: "Trial")]),
            Backup(statements: [history]),
            Backup(settings: AppSettings(handle: "Existing owner"))
        ]
        for backup in backups {
            XCTAssertFalse(WelcomePolicy.shouldPresent(backup: backup, completed: false))
        }
        XCTAssertTrue(WelcomePolicy.shouldPresent(backup: Backup(), completed: false))
    }
    func testWelcomeDoesNotCompeteWithLoadFailureOrRepeatAfterCompletion() {
        XCTAssertFalse(WelcomePolicy.shouldPresent(backup: Backup(), completed: false, hasLoadError: true))
        XCTAssertFalse(WelcomePolicy.shouldPresent(backup: Backup(), completed: true))
    }
    func testExplicitImportReplacesDirtyFormAndClearsDirtyState() {
        var editing = SettingsEditSession()
        editing.receive(AppSettings(usdRate: 7.1))
        editing.draft.usdRate = 9
        editing.draft.handle = "Unsaved"
        let imported = AppSettings(usdRate: 6.8, remindHours: 12, handle: "Imported")
        editing.acceptReplacement(imported)
        XCTAssertEqual(editing.draft, imported)
        XCTAssertFalse(editing.hasChanges)
        // Further ordinary refreshes must follow the new imported baseline.
        let next = AppSettings(usdRate: 6.9, handle: "Later")
        editing.receive(next)
        XCTAssertEqual(editing.draft, next)
    }
    func testBackgroundRefreshKeepsDirtyDraftButUpdatesCleanForm() {
        var editing = SettingsEditSession()
        editing.receive(AppSettings(usdRate: 7.1))
        editing.receive(AppSettings(usdRate: 7.2))
        XCTAssertEqual(editing.draft.usdRate, 7.2)
        editing.draft.usdRate = 8
        editing.receive(AppSettings(usdRate: 6.5))
        XCTAssertEqual(editing.draft.usdRate, 8)
        XCTAssertTrue(editing.hasChanges)
    }
}
