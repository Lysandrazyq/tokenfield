import XCTest
@testable import MacMonitorHarness

@MainActor final class QuotaContextTests: XCTestCase {
    func testSourceAndQuotaAlwaysBelongToTheSameConnection() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let roots = [parent.appendingPathComponent("A"), parent.appendingPathComponent("B")]
        let now = Date()
        for (index, root) in roots.enumerated() {
            let folder = root.appendingPathComponent("sessions/2026/11/07")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = now.addingTimeInterval(Double(index - 2)).ISO8601Format()
            let json = "{\"type\":\"event_msg\",\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":\(index == 0 ? 20 : 95),\"window_minutes\":300,\"resets_at\":\(Int(now.timeIntervalSince1970 + 3600))}}}}\n"
            try Data(json.utf8).write(to: folder.appendingPathComponent("rollout-fixture.jsonl"))
        }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = CodexMonitorStore(defaults: defaults, bookmarkCreator: { _ in Data([1]) })
        defer { store.disconnect(); try? FileManager.default.removeItem(at: parent) }
        var observations = 0
        store.onQuotaContextChange = { quota, directory, _ in
            guard let quota, let directory else { return }
            observations += 1
            XCTAssertEqual(quota.primary?.usedPercent, directory == roots[0] ? 20 : 95)
        }
        await store.connectSelectedDirectory(roots[0])
        await store.connectSelectedDirectory(roots[1])
        await store.connectSelectedDirectory(roots[0])
        XCTAssertGreaterThan(observations, 0)
    }
    func testPublishesConnectionAndDisconnectWithoutAView() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "quota-context-" + UUID().uuidString)!
        let store = CodexMonitorStore(defaults: defaults, discovery: { root })
        var connected: [Bool] = []
        var directories: [URL?] = []
        store.onQuotaContextChange = { _, directory, healthy in connected.append(healthy); directories.append(directory) }
        await store.connectAutomatically()
        XCTAssertEqual(connected.last, true)
        XCTAssertEqual(directories.last!, root)
        store.disconnect()
        XCTAssertEqual(connected.last, false)
        XCTAssertNil(directories.last!)
    }
}
