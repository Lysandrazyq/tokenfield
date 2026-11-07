import XCTest
@testable import TokenfieldCore

final class CodexQuotaAlertTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func window(_ remaining: Double, minutes: Int = 300, reset: Date? = nil) -> CodexQuotaWindow {
        .init(usedPercent: 100 - remaining, durationMinutes: minutes, resetsAt: reset ?? now.addingTimeInterval(3600))
    }
    func quota(_ remaining: Double, at: Date? = nil, secondary: CodexQuotaWindow? = nil) -> CodexQuotaSnapshot {
        .init(reportedAt: at ?? now, limitID: "codex", plan: "plus", primary: window(remaining), secondary: secondary)
    }
    func plan(_ quota: CodexQuotaSnapshot?, early: Bool = true, since: Date? = nil,
              history: [String: Date] = [:], scope: String = "scope-a") -> CodexQuotaAlertPlan? {
        CodexQuotaAlertPolicy.plan(quota: quota, now: now, scopeID: scope, includeEarlyWarning: early,
                                  reportAfter: since, acknowledged: history)
    }
    func testThresholdCrossingAndRepeatedReportsDoNotRepeat() throws {
        XCTAssertNil(plan(quota(21)))
        let first = try XCTUnwrap(plan(quota(20)))
        XCTAssertEqual(first.windows.map(\.level), [.early])
        XCTAssertNil(plan(quota(19), history: first.receipts))
    }
    func testTenPercentEscalatesOnce() throws {
        let first = try XCTUnwrap(plan(quota(20)))
        let urgent = try XCTUnwrap(plan(quota(10), history: first.receipts))
        XCTAssertEqual(urgent.windows.map(\.level), [.critical])
        XCTAssertNil(plan(quota(8), history: first.receipts.merging(urgent.receipts) { _, new in new }))
    }
    func testStartingAtEightOnlySendsUrgentAndSuppressesLaterEarly() throws {
        let urgent = try XCTUnwrap(plan(quota(8)))
        XCTAssertEqual(urgent.windows.count, 1)
        XCTAssertEqual(urgent.windows.first?.level, .critical)
        XCTAssertNil(plan(quota(18), history: urgent.receipts))
    }
    func testEarlyWarningCanBeDisabledWithoutDisablingUrgent() throws {
        XCTAssertNil(plan(quota(18), early: false))
        XCTAssertEqual(try XCTUnwrap(plan(quota(10), early: false)).windows.first?.level, .critical)
    }
    func testBothWindowsAreCombinedAndAcknowledgedSeparately() throws {
        let result = try XCTUnwrap(plan(quota(8, secondary: window(18, minutes: 10080))))
        XCTAssertEqual(result.windows.count, 2)
        XCTAssertEqual(Set(result.windows.map(\.durationMinutes)), [300, 10080])
        XCTAssertNil(plan(quota(8, secondary: window(18, minutes: 10080)), history: result.receipts))
    }
    func testMissingStaleFutureAndExpiredDataNeverNotify() {
        XCTAssertNil(plan(nil))
        XCTAssertNil(plan(quota(5, at: now.addingTimeInterval(-301))))
        XCTAssertNil(plan(quota(5, at: now.addingTimeInterval(1))))
        let expired = CodexQuotaSnapshot(reportedAt: now, limitID: nil, plan: nil,
            primary: window(5, reset: now), secondary: nil)
        XCTAssertNil(plan(expired))
    }
    func testFiveMinuteBoundaryIsStillFresh() {
        XCTAssertNotNil(plan(quota(20, at: now.addingTimeInterval(-300))))
    }
    func testDifferentLimitCannotTriggerCodexAlert() {
        let other = CodexQuotaSnapshot(reportedAt: now, limitID: "other-service", plan: "plus", primary: window(8), secondary: nil)
        XCTAssertNil(plan(other))
    }
    func testReconfirmationRequiresStrictlyNewReport() {
        XCTAssertNil(plan(quota(8), since: now))
        XCTAssertNotNil(plan(quota(8), since: now.addingTimeInterval(-1)))
    }
    func testNewCycleAndNewScopeHaveIndependentReceipts() throws {
        let first = try XCTUnwrap(plan(quota(18)))
        let next = CodexQuotaSnapshot(reportedAt: now, limitID: nil, plan: nil,
            primary: window(18, reset: now.addingTimeInterval(7200)), secondary: nil)
        XCTAssertNotNil(plan(next, history: first.receipts))
        XCTAssertNotNil(plan(quota(18), history: first.receipts, scope: "scope-b"))
    }
    func testDuplicateWindowOnlyNotifiesOnceAtMostUrgentValue() throws {
        let result = try XCTUnwrap(plan(quota(18, secondary: window(8))))
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows.first?.level, .critical)
    }
    func testInvalidWindowNumbersAreIgnored() {
        for value in [Double.nan, .infinity, -1, 101] {
            let invalid = CodexQuotaSnapshot(reportedAt: now, limitID: nil, plan: nil,
                primary: .init(usedPercent: value, durationMinutes: 300, resetsAt: now.addingTimeInterval(3600)), secondary: nil)
            XCTAssertNil(plan(invalid))
        }
    }
    func testReceiptPlanSurvivesEncoding() throws {
        let value = try XCTUnwrap(plan(quota(8, secondary: window(20, minutes: 10080))))
        XCTAssertEqual(try JSONDecoder().decode(CodexQuotaAlertPlan.self, from: JSONEncoder().encode(value)), value)
    }
}
