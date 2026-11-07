import XCTest
@testable import TokenfieldCore

final class CodexStatusSummaryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func snapshot(remaining: Double = 70, secondary: Double? = 20, age: Double = 0, expired: Bool = false,
                  sessions: [CodexSessionSnapshot] = []) -> CodexMonitorSnapshot {
        let reset = now.addingTimeInterval(expired ? -1 : 3600)
        let quota = CodexQuotaSnapshot(reportedAt: now.addingTimeInterval(-age), limitID: "codex", plan: nil,
            primary: .init(usedPercent: 100 - remaining, durationMinutes: 300, resetsAt: reset),
            secondary: secondary.map { .init(usedPercent: 100 - $0, durationMinutes: 10080, resetsAt: reset) })
        return .init(sessions: sessions, quota: quota, scannedAt: now, warnings: 0, bytesRead: 0)
    }
    func session(_ event: String, secondsAgo: Double = 0) -> CodexSessionSnapshot {
        var accumulator = CodexTelemetryAccumulator(fileID: UUID().uuidString)
        let stamp = now.addingTimeInterval(-secondsAgo).ISO8601Format()
        let line = "{\"type\":\"event_msg\",\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"\(event)\"}}"
        accumulator.consume(line: Data(line.utf8))
        return accumulator.snapshot()
    }
    func testUsesLowerValidQuotaWindow() {
        let value = CodexStatusSummary.make(snapshot: snapshot(), connected: true, now: now)
        XCTAssertEqual(value.remainingPercent, 20)
        XCTAssertEqual(value.windowMinutes, 10080)
    }
    func testStaleExpiredFutureAndDisconnectedNeverShowFakePercentage() {
        XCTAssertNil(CodexStatusSummary.make(snapshot: snapshot(age: 301), connected: true, now: now).remainingPercent)
        XCTAssertNil(CodexStatusSummary.make(snapshot: snapshot(expired: true), connected: true, now: now).remainingPercent)
        XCTAssertNil(CodexStatusSummary.make(snapshot: snapshot(age: -1), connected: true, now: now).remainingPercent)
        XCTAssertNil(CodexStatusSummary.make(snapshot: snapshot(), connected: false, now: now).remainingPercent)
    }
    func testRunningTaskShowsActivityEvenWithoutQuota() {
        let data = CodexMonitorSnapshot(sessions: [session("task_started")], quota: nil, scannedAt: now, warnings: 0, bytesRead: 0)
        let value = CodexStatusSummary.make(snapshot: data, connected: true, now: now)
        XCTAssertNil(value.remainingPercent)
        XCTAssertEqual(value.phase, .running)
        XCTAssertEqual(value.activeTasks, 1)
    }
    func testQuietIsNotCompleteAndExplicitCompleteIsComplete() {
        let quiet = CodexStatusSummary.make(snapshot: snapshot(sessions: [session("task_started", secondsAgo: 91)]), connected: true, now: now)
        XCTAssertEqual(quiet.phase, .quiet)
        let completed = CodexStatusSummary.make(snapshot: snapshot(sessions: [session("task_complete")]), connected: true, now: now)
        XCTAssertEqual(completed.phase, .completed)
    }
    func testActiveTaskWinsOverAnotherRecentCompletedTask() {
        let value = CodexStatusSummary.make(snapshot: snapshot(sessions: [session("task_complete"), session("task_started", secondsAgo: 10)]), connected: true, now: now)
        XCTAssertEqual(value.phase, .running)
        XCTAssertEqual(value.activeTasks, 1)
    }
}
