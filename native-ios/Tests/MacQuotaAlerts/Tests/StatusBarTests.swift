import AppKit
import XCTest
@testable import TokenfieldCore
@testable import MacQuotaAlertsHarness

@MainActor
final class StatusBarTests: XCTestCase {
    func testDisconnectedMenuIsHonestAndActionsRemainAvailable() {
        let controller = CodexStatusBarController(navigation: CodexNotificationNavigation())
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        controller.menuWillOpen(menu)
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains("本机 Codex 尚未连接"))
        XCTAssertFalse(titles.contains { $0.contains("%") })
        XCTAssertTrue(menu.items.first { $0.title == "打开 Codex 看板" }?.isEnabled == true)
        XCTAssertTrue(menu.items.first { $0.title == "额度提醒…" }?.isEnabled == true)
        controller.menuDidClose(menu)
    }

    func testMenuDoesNotExposeSessionTitleOrProjectAndCanRouteAlerts() {
        let now = Date()
        var accumulator = CodexTelemetryAccumulator(fileID: "fixture")
        let stamp = now.ISO8601Format()
        let lines = [
            "{\"type\":\"session_meta\",\"timestamp\":\"\(stamp)\",\"payload\":{\"id\":\"private-id\",\"cwd\":\"/private/project\"}}",
            "{\"type\":\"event_msg\",\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"task_started\"}}"
        ]
        for line in lines { accumulator.consume(line: Data(line.utf8)) }
        let navigation = CodexNotificationNavigation()
        let controller = CodexStatusBarController(navigation: navigation)
        controller.update(snapshot: .init(sessions: [accumulator.snapshot()], quota: nil,
            scannedAt: now, warnings: 0, bytesRead: 0), connected: true)
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        controller.menuWillOpen(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "任务活动中" })
        XCTAssertFalse(menu.items.contains { $0.title.contains("private") || $0.title.contains("/") })
        let action = menu.items.first { $0.title == "额度提醒…" }!
        let target = action.target as! NSObject
        _ = target.perform(action.action)
        XCTAssertEqual(navigation.destination, .alerts)
        XCTAssertTrue(navigation.hasPendingRequest)
        controller.menuDidClose(menu)
    }

    func testUnknownRingIsTemplateAtNativeMenuBarSize() {
        let summary = CodexStatusSummary.make(snapshot: nil, connected: false, now: Date())
        let image = CodexStatusBarController.image(summary: summary, animate: false, highContrast: false)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 22, height: 22))
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testRingVisualBoundsMatchCompactMenuBarSymbols() throws {
        let summary = CodexStatusSummary.make(snapshot: nil, connected: false, now: Date())
        let image = CodexStatusBarController.image(summary: summary, animate: false, highContrast: true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        var occupiedX: [Int] = [], occupiedY: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                occupiedX.append(x); occupiedY.append(y)
            }
        }
        XCTAssertFalse(occupiedX.isEmpty)
        let width = try XCTUnwrap(occupiedX.max()) - XCTUnwrap(occupiedX.min()) + 1
        let height = try XCTUnwrap(occupiedY.max()) - XCTUnwrap(occupiedY.min()) + 1
        XCTAssertLessThanOrEqual(width, 32, "Visible glyph must fit within 16 pt at 2x")
        XCTAssertLessThanOrEqual(height, 32)
    }
}
