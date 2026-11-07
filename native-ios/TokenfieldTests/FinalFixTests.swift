import XCTest
import SwiftUI
import TokenfieldCore
@testable import Tokenfield

final class FinalFixTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCanceledFutureReminderCanBeRestoredAfterOriginalDeliveryTime() throws {
        var backup = Backup()
        backup.expiries = [Expiry(id: 1, expiresAt: DateCodec.iso(now.addingTimeInterval(2 * 86400)))]
        let reminder = try XCTUnwrap(Schedule.reminders(backup: backup, now: now).first)
        let id = "tokenfield." + reminder.id
        backup.expiries[0].done = true
        let canceled = ReminderReconciliation(backup: backup, now: now,
            history: [id: reminder.at.timeIntervalSince1970], pendingIDs: [id, "unrelated"], deliveredIDs: [])
        XCTAssertEqual(canceled.obsolete, [id])
        XCTAssertNil(canceled.history[id], "A canceled future reminder has never been delivered")
        backup.expiries[0].done = false
        let restored = ReminderReconciliation(backup: backup, now: now.addingTimeInterval(86401),
            history: canceled.history, pendingIDs: [], deliveredIDs: [])
        XCTAssertEqual(restored.reminders.map(\.id), [reminder.id])
    }

    func testDueAndDeliveredReminderHistoryStaysDeduplicated() throws {
        var backup = Backup()
        backup.expiries = [Expiry(id: 1, expiresAt: DateCodec.iso(now.addingTimeInterval(2 * 86400)))]
        let id = "tokenfield." + (try XCTUnwrap(Schedule.reminders(backup: backup, now: now).first)).id
        let due = ReminderReconciliation(backup: backup, now: now, history: [id: now.timeIntervalSince1970],
            pendingIDs: [id], deliveredIDs: [])
        XCTAssertNotNil(due.history[id])
        XCTAssertTrue(due.reminders.isEmpty)
        let delivered = ReminderReconciliation(backup: backup, now: now,
            history: [id: now.addingTimeInterval(60).timeIntervalSince1970], pendingIDs: [id], deliveredIDs: [id])
        XCTAssertNotNil(delivered.history[id])
        XCTAssertTrue(delivered.reminders.isEmpty)
    }

    func testOverflowingConversionStillHasFiniteCompleteChartShare() throws {
        let summary = SpendPresentation(backup: fixture(costs: [1e308], currency: .usd))
        XCTAssertEqual(summary.fraction(for: try XCTUnwrap(summary.slices.first)), 1)
        XCTAssertNil(summary.total)
        XCTAssertEqual(summary.totalMoney, "¥7.1e308")
        XCTAssertEqual(summary.serial, "TKF-7.1e308")
    }

    func testOverflowingSumStillHasEqualFiniteChartShares() {
        let summary = SpendPresentation(backup: fixture(costs: [1e308, 1e308]))
        XCTAssertEqual(summary.slices.count, 2)
        for slice in summary.slices { XCTAssertEqual(summary.fraction(for: slice), 0.5, accuracy: 1e-12) }
        XCTAssertEqual(summary.totalMoney, "¥2e308")
    }

    func testOrdinaryAmountsAndPercentagesRemainExact() throws {
        let summary = SpendPresentation(backup: fixture(costs: [25, 75]))
        XCTAssertEqual(summary.total, 100)
        XCTAssertEqual(summary.slices.map { summary.fraction(for: $0) }, [0.75, 0.25])
        XCTAssertEqual(summary.serial, "TKF-100")
    }

    func testIndeterminateValueProgressIsOmittedInsteadOfPassingNaNToSwiftUI() {
        XCTAssertNil(NativeFormat.progressValue(numerator: .infinity, denominator: .infinity))
        XCTAssertEqual(NativeFormat.progressValue(numerator: 25, denominator: 100), 0.25)
        XCTAssertEqual(NativeFormat.progressValue(numerator: .infinity, denominator: 100), 1)
        XCTAssertEqual(NativeFormat.progressValue(numerator: 100, denominator: .infinity), 0)
    }

    func testReportDateUsesGregorianMonthAndDaysInCallerTimezone() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-02-29T16:30:00Z"))
        for identifier in [Calendar.Identifier.islamic, .buddhist] {
            var caller = Calendar(identifier: identifier)
            caller.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
            let context = ReportDateContext(date: instant, calendar: caller)
            XCTAssertEqual(context.month, "2024-03")
            XCTAssertEqual(context.days, 31)
            XCTAssertEqual(context.calendar.timeZone, caller.timeZone)
        }
    }

    @MainActor func testAcceptedLargeAmountsRenderReportAndHomeWithoutLosingBackup() throws {
        var valueOverflow = fixture(costs: [20], currency: .usd)
        valueOverflow.settings.usdRate = 1e308
        let model = try XCTUnwrap(Catalog.bundled.models.first { $0.currency == .usd && $0.input > 0 })
        valueOverflow.accounts[0].modelId = model.id
        valueOverflow.usage = [Usage(id: 1, accountId: 1, day: DateCodec.day(Date()), count: Int.max, intensity: .code)]
        let valueReport = Finance.valueReport(account: valueOverflow.accounts[0], usage: valueOverflow.usage,
            settings: valueOverflow.settings, model: model)
        XCTAssertTrue(valueReport.fee.isInfinite)
        XCTAssertTrue(valueReport.apiEquivalent.isInfinite)
        XCTAssertNil(NativeFormat.progressValue(numerator: valueReport.apiEquivalent, denominator: valueReport.fee))
        for backup in [fixture(costs: [1e20]), fixture(costs: [1e308], currency: .usd), fixture(costs: [1e308, 1e308]), valueOverflow] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("data.json")
            let store = AppStore(fileURL: file)
            XCTAssertTrue(store.importData(try backup.encoded()))
            // Native sync migrates website integers to stable global identities;
            // every value and relationship must still survive without truncation.
            let migrated = store.backup
            var expected = backup
            expected.exportedAt = migrated.exportedAt
            var accountIDs: [Int: Int] = [:]
            for index in expected.accounts.indices {
                let originalID = expected.accounts[index].id
                let migratedAccount = try XCTUnwrap(migrated.accounts.first { $0.name == expected.accounts[index].name })
                expected.accounts[index].id = migratedAccount.id
                accountIDs[originalID] = migratedAccount.id
            }
            for index in expected.usage.indices {
                let entry = expected.usage[index]
                let accountID = try XCTUnwrap(accountIDs[entry.accountId])
                let migratedUsage = try XCTUnwrap(migrated.usage.first { $0.accountId == accountID && $0.day == entry.day && $0.intensity == entry.intensity })
                expected.usage[index].id = migratedUsage.id
                expected.usage[index].accountId = accountID
            }
            expected.accounts.sort { $0.id < $1.id }
            expected.usage.sort { $0.id < $1.id }
            XCTAssertEqual(migrated, expected)
            XCTAssertEqual(AppStore(fileURL: file).backup, migrated)
            let report = ImageRenderer(content: ReportCard(backup: store.backup, catalog: store.catalog).frame(width: 360))
            XCTAssertNotNil(report.uiImage?.pngData())
            let home = ImageRenderer(content: HomeView().environment(store).frame(width: 390, height: 1000))
            XCTAssertNotNil(home.uiImage?.pngData())
            var exported = try Backup.decode(store.exportData())
            exported.exportedAt = migrated.exportedAt // Export intentionally records a fresh timestamp.
            XCTAssertEqual(exported, migrated)
            let before = try Data(contentsOf: file)
            var invalid = backup
            invalid.accounts[0].monthlyCost = -1
            XCTAssertFalse(store.importData(try JSONEncoder().encode(invalid)))
            XCTAssertEqual(try Data(contentsOf: file), before)
        }
    }

    private func fixture(costs: [Double], currency: Currency = .cny) -> Backup {
        var backup = Backup()
        backup.accounts = costs.enumerated().map { Account(id: $0.offset + 1, name: "AI \($0.offset)", monthlyCost: $0.element, currency: currency, createdAt: DateCodec.iso(now)) }
        return backup
    }
}
