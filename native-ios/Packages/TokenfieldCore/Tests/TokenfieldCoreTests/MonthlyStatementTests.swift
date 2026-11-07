import XCTest
@testable import TokenfieldCore

final class MonthlyStatementTests: XCTestCase {
    private func statement(_ month: String = "2026-10", name: String = "Saved", cost: Double = 20) -> MonthlyStatement {
        MonthlyStatement(month: month, capturedAt: "2026-11-01T02:00:00Z",
            accounts: [Account(id: 1, name: name, monthlyCost: cost)], settings: AppSettings(usdRate: 7, handle: "saved"))
    }
    func testSnapshotSurvivesAccountChangesDeletionAndBackupRoundTrip() throws {
        let snapshot = statement()
        var value = Backup(accounts: snapshot.accounts, settings: snapshot.settings, statements: [snapshot])
        value.accounts[0].monthlyCost = 100
        value.settings.usdRate = 10
        value.deleteAccount(id: 1)
        let restored = try Backup.decode(value.encoded())
        XCTAssertEqual(restored.statements[0].reportBackup.accounts[0].monthlyCost, 20)
        XCTAssertEqual(Finance.monthlySpend(accounts: restored.statements[0].reportBackup.accounts,
            settings: restored.statements[0].settings).first?.cny, 140)
        XCTAssertEqual(restored.statements[0].settings.handle, "saved")
    }
    func testOldBackupWithoutStatementFieldLoadsAndInvalidSnapshotsReject() throws {
        let data = try Backup().encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "statements")
        XCTAssertTrue(try Backup.decode(JSONSerialization.data(withJSONObject: object)).statements.isEmpty)
        for month in ["2026-13", "2026-00", "2026-1", "0000-01", "not-a-month"] {
            XCTAssertThrowsError(try Backup(statements: [statement(month)]).validated())
        }
        XCTAssertThrowsError(try Backup(statements: [statement(cost: -1)]).validated())
        XCTAssertThrowsError(try Backup(statements: [statement(), statement()]).validated())
    }
    func testLedgerMergeDeleteAndRecreateConverge() throws {
        var a = try SyncDocument(backup: Backup(), deviceID: "A")
        var b = try SyncDocument(backup: Backup(), deviceID: "B")
        let original = statement()
        let before = try a.materialized()
        var after = before; after.statements = [original]
        try a.recordChange(from: before, to: after)
        try b.merge(a.operations)
        let saved = try b.materialized()
        var changed = saved; changed.statements[0].accounts[0].monthlyCost = 30
        try b.recordChange(from: saved, to: changed)
        var removed = try a.materialized(); removed.statements = []
        try a.recordChange(from: try a.materialized(), to: removed)
        try a.merge(b.operations); try b.merge(a.operations)
        XCTAssertTrue(try a.materialized().statements.isEmpty)
        XCTAssertEqual(try a.materialized(), try b.materialized())
        let empty = try a.materialized()
        var recreated = empty; recreated.statements = [statement(name: "Recreated")]
        try a.recordChange(from: empty, to: recreated)
        try b.merge(a.operations)
        XCTAssertEqual(try b.materialized().statements.first?.accounts.first?.name, "Recreated")
    }
    func testConcurrentSameMonthSnapshotsSelectOneAndMonthDatesStayInMonth() throws {
        let first = statement(name: "A")
        let second = statement(name: "B")
        var a = try SyncDocument(backup: Backup(statements: [first]), deviceID: "A")
        var b = try SyncDocument(backup: Backup(statements: [second]), deviceID: "B")
        try a.merge(b.operations); try b.merge(a.operations.reversed())
        XCTAssertEqual(try a.materialized().statements.count, 1)
        XCTAssertEqual(try a.materialized(), try b.materialized())
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
            XCTAssertEqual(StatementMonth.key(for: try XCTUnwrap(StatementMonth.date("2026-12")), calendar: calendar), "2026-12")
        }
    }

    func testDeletingMonthDoesNotRevealAnotherKnownConcurrentSnapshot() throws {
        var a = try SyncDocument(backup: Backup(statements: [statement(name: "A")]), deviceID: "A")
        let b = try SyncDocument(backup: Backup(statements: [statement(name: "B")]), deviceID: "B")
        try a.merge(b.operations)
        let before = try a.materialized()
        var after = before; after.statements = []
        try a.recordChange(from: before, to: after)
        XCTAssertTrue(try a.materialized().statements.isEmpty)
    }
}
