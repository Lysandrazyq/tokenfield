import XCTest
@testable import MacMonitorHarness

private actor DiscoveryGate {
    private var continuation: CheckedContinuation<URL?, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func discover() async throws -> URL? {
        try await withCheckedThrowingContinuation {
            continuation = $0
            waiters.forEach { $0.resume() }; waiters.removeAll()
        }
    }
    func started() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finish(_ result: Result<URL?, Error>) { continuation?.resume(with: result); continuation = nil }
}

final class AutomaticConnectionTests: XCTestCase {
    private func fixture(_ id: String = "automatic-fixture") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TokenfieldAuto-" + UUID().uuidString)
        let folder = root.appendingPathComponent("sessions/2026/11/05")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let content = """
        {"timestamp":"2026-11-05T00:00:00Z","type":"session_meta","payload":{"id":"\(id)","cwd":"/tmp/自动连接示例"}}
        {"timestamp":"2026-11-05T00:00:01Z","type":"event_msg","payload":{"type":"task_started"}}

        """
        try Data(content.utf8).write(to: folder.appendingPathComponent("rollout-auto.jsonl"))
        return root
    }

    @MainActor func testFreshLaunchConnectsDiscoveredLogsWithoutBookmark() async throws {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let root = try fixture()
        let store = CodexMonitorStore(defaults: defaults, discovery: { root })
        defer { store.disconnect(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        await store.restore()
        XCTAssertEqual(store.directory, root)
        XCTAssertEqual(store.snapshot?.sessions.first?.id, "automatic-fixture")
        XCTAssertTrue(store.automaticallyConnected)
        XCTAssertNil(defaults.data(forKey: "codex.monitor.readonly-folder.v1"), "Known read-only paths do not require a user bookmark.")
        XCTAssertFalse(store.isConnecting)
        XCTAssertNil(store.issue)
    }

    @MainActor func testSavedSelectionTakesPriorityOverAutomaticDiscovery() async throws {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let root = try fixture("saved-selection")
        let saved = Data([1,2,3])
        defaults.set(saved, forKey: "codex.monitor.readonly-folder.v1")
        let store = CodexMonitorStore(defaults: defaults, resolver: { _ in root }, discovery: { XCTFail("Saved selection must win."); return nil })
        defer { store.disconnect(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        await store.restore()
        XCTAssertEqual(store.snapshot?.sessions.first?.id, "saved-selection")
        XCTAssertEqual(defaults.data(forKey: "codex.monitor.readonly-folder.v1"), saved)
    }

    @MainActor func testDisconnectPersistsAndExplicitRetryReenablesAutomaticConnection() async throws {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let root = try fixture()
        let first = CodexMonitorStore(defaults: defaults, discovery: { root })
        defer { first.disconnect(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        await first.restore(); first.disconnect()
        let next = CodexMonitorStore(defaults: defaults, discovery: { root })
        await next.restore()
        XCTAssertNil(next.directory, "An explicit disconnect must survive restart.")
        await next.connectAutomatically()
        XCTAssertEqual(next.directory, root)
        XCTAssertTrue(next.automaticallyConnected)
        next.disconnect()
    }

    @MainActor func testMissingLogsLeaveActionableDisconnectedState() async {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let store = CodexMonitorStore(defaults: defaults, discovery: { nil })
        defer { store.disconnect(); defaults.removePersistentDomain(forName: name) }
        await store.restore()
        XCTAssertNil(store.directory)
        XCTAssertNil(store.snapshot)
        XCTAssertNotNil(store.issue)
        XCTAssertFalse(store.isConnecting)
    }

    @MainActor func testDelayedDiscoverySuccessCannotReconnectAfterDisconnect() async throws {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let root = try fixture()
        let gate = DiscoveryGate()
        let store = CodexMonitorStore(defaults: defaults, discovery: { try await gate.discover() })
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let work = Task { await store.restore() }
        await gate.started(); store.disconnect()
        await gate.finish(.success(root)); await work.value
        XCTAssertNil(store.directory); XCTAssertNil(store.snapshot); XCTAssertNil(store.issue)
        XCTAssertFalse(store.isConnecting)
    }

    @MainActor func testDelayedDiscoveryFailureCannotOverwriteDisconnect() async {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let gate = DiscoveryGate()
        let store = CodexMonitorStore(defaults: defaults, discovery: { try await gate.discover() })
        defer { defaults.removePersistentDomain(forName: name) }
        let work = Task { await store.restore() }
        await gate.started(); store.disconnect()
        await gate.finish(.failure(CocoaError(.fileReadNoPermission))); await work.value
        XCTAssertNil(store.issue); XCTAssertNil(store.directory); XCTAssertFalse(store.isConnecting)
    }

    @MainActor func testCancelledDiscoveryDoesNotPublishConnection() async throws {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let root = try fixture()
        let gate = DiscoveryGate()
        let store = CodexMonitorStore(defaults: defaults, discovery: { try await gate.discover() })
        defer { store.disconnect(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let work = Task { await store.restore() }
        await gate.started(); work.cancel()
        await gate.finish(.success(root)); await work.value
        XCTAssertNil(store.directory); XCTAssertNil(store.snapshot); XCTAssertFalse(store.isConnecting)
    }

    @MainActor func testFailedSelectionKeepsOriginalConnectionAndBookmarkAcrossRestart() async throws {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let original = try fixture("original-selection")
        let fallback = try fixture("unwanted-default")
        let invalid = original.appendingPathComponent("not-a-codex-directory")
        let saved = Data([9,8,7])
        defaults.set(saved, forKey: "codex.monitor.readonly-folder.v1")
        let first = CodexMonitorStore(defaults: defaults, resolver: { _ in original }, discovery: { fallback })
        defer { first.disconnect(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: original); try? FileManager.default.removeItem(at: fallback) }
        await first.restore()
        await first.connectSelectedDirectory(invalid)
        XCTAssertEqual(first.directory, original)
        XCTAssertEqual(first.snapshot?.sessions.first?.id, "original-selection")
        XCTAssertEqual(defaults.data(forKey: "codex.monitor.readonly-folder.v1"), saved)
        let restarted = CodexMonitorStore(defaults: defaults, resolver: { _ in original }, discovery: { fallback })
        await restarted.restore()
        XCTAssertEqual(restarted.directory, original, "Failed replacement must not silently choose the default location on restart.")
        restarted.disconnect()
    }

    @MainActor func testFailedBookmarkCreationKeepsOriginalConnectionAcrossRestart() async throws {
        let name = "TokenfieldAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let original = try fixture("original-selection")
        let replacement = try fixture("replacement")
        let saved = Data([9,8,7])
        defaults.set(saved, forKey: "codex.monitor.readonly-folder.v1")
        let first = CodexMonitorStore(defaults: defaults, resolver: { _ in original }, discovery: { replacement },
            bookmarkCreator: { _ in throw CocoaError(.fileWriteNoPermission) })
        defer { first.disconnect(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: original); try? FileManager.default.removeItem(at: replacement) }
        await first.restore()
        await first.connectSelectedDirectory(replacement)
        XCTAssertEqual(first.directory, original)
        XCTAssertEqual(first.snapshot?.sessions.first?.id, "original-selection")
        XCTAssertEqual(defaults.data(forKey: "codex.monitor.readonly-folder.v1"), saved)
        XCTAssertNotNil(first.issue)
        let restarted = CodexMonitorStore(defaults: defaults, resolver: { _ in original }, discovery: { replacement })
        await restarted.restore()
        XCTAssertEqual(restarted.directory, original)
        restarted.disconnect()
    }
}
