import XCTest
@testable import TokenfieldCore

final class ScheduleTests: XCTestCase {
    func calendar(_ zone: String = "UTC") -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!; return c }
    func date(_ value: String) -> Date { DateCodec.date(value)! }
    func testMonthEndRenewalsClampAndAlwaysAdvanceAtBoundary() {
        var account = Account(renewAt: "2026-01-31T12:00:00Z")
        XCTAssertEqual(Schedule.nextRenewal(account, now: date("2026-02-28T12:00:00Z"), calendar: calendar()), date("2026-03-28T12:00:00Z"))
        XCTAssertEqual(Schedule.nextRenewal(account, now: date("2026-01-01T00:00:00Z"), calendar: calendar()), date("2026-01-31T12:00:00Z"))
        account.billing = .payg
        XCTAssertNil(Schedule.nextRenewal(account, now: date("2026-01-01T00:00:00Z"), calendar: calendar()))
    }
    func testResetPeriodsAndInvalidAnchors() {
        let now = date("2026-10-10T12:00:00Z")
        var account = Account(resetKind: .hours, resetHours: 5, resetAnchor: "2026-10-10T07:00:00Z")
        XCTAssertEqual(Schedule.nextReset(account, now: now, calendar: calendar()), date("2026-10-10T17:00:00Z"))
        account.resetHours = nil
        XCTAssertEqual(Schedule.nextReset(account, now: now, calendar: calendar()), date("2026-10-10T17:00:00Z"))
        account.resetHours = .nan
        XCTAssertNil(Schedule.nextReset(account, now: now, calendar: calendar()))
        account.resetHours = 0
        XCTAssertNil(Schedule.nextReset(account, now: now, calendar: calendar()))
        account.resetKind = .monthly
        account.resetAnchor = "2026-01-31T12:00:00Z"
        XCTAssertEqual(Schedule.nextReset(account, now: date("2026-02-28T12:00:00Z"), calendar: calendar()), date("2026-03-28T12:00:00Z"))
        account.resetAnchor = "broken"
        XCTAssertNil(Schedule.nextReset(account, now: now, calendar: calendar()))
    }
    // Calendar-week advancement must retain local wall-clock time across DST.
    func testFractionalHourResetAdvancesAtExactFloatingPointBoundary() {
        let account = Account(resetKind: .hours, resetHours: 1.1, resetAnchor: "2026-10-10T07:00:00Z")
        XCTAssertEqual(Schedule.nextReset(account, now: date("2026-10-10T08:06:00Z"), calendar: calendar()), date("2026-10-10T09:12:00Z"))
    }
    func testWeeklyResetAndDayRespectExplicitTimeZone() {
        let c = calendar("America/Los_Angeles")
        let account = Account(resetKind: .weekly, resetAnchor: "2026-03-01T17:00:00Z")
        XCTAssertEqual(Schedule.nextReset(account, now: date("2026-03-01T17:00:00Z"), calendar: c), date("2026-03-08T16:00:00Z"))
        XCTAssertEqual(DateCodec.day(date("2026-10-10T01:00:00Z"), calendar: c), "2026-10-09")
        XCTAssertEqual(DateCodec.day(date("2026-10-10T01:00:00Z"), calendar: calendar("Asia/Shanghai")), "2026-10-10")
        XCTAssertNil(DateCodec.date("2026-02-30T00:00:00Z"))
        XCTAssertNil(DateCodec.date("2026-10-10T25:00:00Z"))
    }
    func testDayUsesGregorianYearAndSuppliedTimeZoneWithBuddhistCalendar() {
        var displayCalendar = Calendar(identifier: .buddhist)
        displayCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(DateCodec.day(date("2026-10-14T16:00:00Z"), calendar: displayCalendar), "2026-10-15")
    }
    func testIslamicDisplayCalendarKeepsGregorianMonthEndRenewalAndReset() {
        var displayCalendar = Calendar(identifier: .islamicUmmAlQura)
        displayCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let account = Account(renewAt: "2026-01-31T04:00:00Z", resetKind: .monthly, resetAnchor: "2026-01-31T04:00:00Z")
        let now = date("2026-02-28T04:00:00Z")
        XCTAssertEqual(Schedule.nextRenewal(account, now: now, calendar: displayCalendar), date("2026-03-28T04:00:00Z"))
        XCTAssertEqual(Schedule.nextReset(account, now: now, calendar: displayCalendar), date("2026-03-28T04:00:00Z"))
    }

    func testTimelineIncludesOverdueItemsExcludesCompletedAndSorts() throws {
        let now = date("2026-10-10T00:00:00Z")
        let account = Account(id: 3, name: "Claude", renewAt: "2026-10-12T00:00:00Z", resetKind: .hours, resetHours: 5, resetAnchor: "2026-10-10T00:00:00Z", notifyReset: false)
        let expiries = [Expiry(id: 1, title: "过期", accountId: 3, expiresAt: "2026-10-09T00:00:00Z"), Expiry(id: 2, expiresAt: "2026-10-11T00:00:00Z", done: true)]
        let timeline = Schedule.timeline(accounts: [account], expiries: expiries, now: now, calendar: calendar())
        XCTAssertEqual(timeline.map(\.kind), [.expiry, .reset, .renew])
        let overdue = try XCTUnwrap(timeline.first { $0.kind == .expiry })
        let reset = try XCTUnwrap(timeline.first { $0.kind == .reset })
        XCTAssertEqual(overdue.title, "Claude · 过期")
        XCTAssertEqual(overdue.expiryID, 1)
        XCTAssertFalse(reset.notify)
        XCTAssertEqual(Schedule.countdown(now.addingTimeInterval(90061), now: now), "1 天 1 时")
        XCTAssertEqual(Schedule.countdown(now.addingTimeInterval(3660), now: now), "1 时 1 分")
        XCTAssertEqual(Schedule.countdown(now.addingTimeInterval(59), now: now), "0 分钟")
        XCTAssertEqual(Schedule.countdown(now.addingTimeInterval(-1), now: now), "已过期")
    }
    // A cap applied before delivery-date sorting drops the genuinely earliest reminders.
    func testReminderCapUsesDeliveryOrderAndStableEventIDs() {
        let now = date("2026-10-10T00:00:00Z")
        let accounts = (1...6).map { Account(id: $0, name: "账号\($0)", resetKind: .hours, resetHours: 5, resetAnchor: "2026-10-10T00:00:00Z", notifyReset: true) }
        let expiry = Expiry(id: 1, title: "提前提醒", expiresAt: "2026-10-11T01:00:00Z")
        let backup = Backup(accounts: accounts, expiries: [expiry])
        let reminders = Schedule.reminders(backup: backup, now: now, calendar: calendar())
        XCTAssertEqual(reminders.count, 60)
        XCTAssertEqual(reminders.first?.at, date("2026-10-10T01:00:00Z"))
        XCTAssertEqual(reminders.first?.title, "⏰ 提前提醒")
        XCTAssertEqual(reminders.map(\.at), reminders.map(\.at).sorted())
        XCTAssertEqual(Set(reminders.map(\.id)).count, 60)
        let later = Schedule.reminders(backup: backup, now: now.addingTimeInterval(30), calendar: calendar())
        XCTAssertEqual(reminders.first?.id, later.first?.id)
        XCTAssertLessThanOrEqual(reminders.filter { $0.id.hasPrefix("reset-1-") }.count, 12)
    }
    func testReminderHorizonResetCapAndImmediateReminder() {
        let now = date("2026-10-10T00:00:00Z")
        let account = Account(id: 1, resetKind: .hours, resetHours: 5, resetAnchor: "2026-10-10T00:00:00Z", notifyReset: true)
        let expiries = [
            Expiry(id: 1, expiresAt: "2026-10-10T01:00:00Z"),
            Expiry(id: 2, expiresAt: "2026-11-25T00:00:00Z"),
            Expiry(id: 3, expiresAt: "2026-10-09T00:00:00Z"),
            Expiry(id: 4, expiresAt: "2026-10-11T00:00:00Z", done: true)
        ]
        let reminders = Schedule.reminders(backup: Backup(accounts: [account], expiries: expiries), now: now, calendar: calendar())
        XCTAssertEqual(reminders.count, 13)
        XCTAssertEqual(reminders.first?.at, now.addingTimeInterval(10))
        XCTAssertEqual(reminders.last?.at, date("2026-10-12T12:00:00Z"))
    }
}
