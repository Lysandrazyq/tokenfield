import XCTest
@testable import MacMonitorHarness

private actor ResolutionGate {
    var continuation: CheckedContinuation<URL, Error>?
    var waiters: [CheckedContinuation<Void, Never>] = []
    func resolve() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation = $0; waiters.forEach { $0.resume() }; waiters = [] }
    }
    func started() async { if continuation != nil { return }; await withCheckedContinuation { waiters.append($0) } }
    func finish(_ result: Result<URL, Error>) { continuation?.resume(with: result); continuation = nil }
}
final class RestoreTests: XCTestCase {
    @MainActor func testDelayedSuccessfulResolutionCannotReconnectAfterDisconnect() async {
        let name = "TokenfieldRestoreTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data([1]), forKey: "codex.monitor.readonly-folder.v1")
        let gate = ResolutionGate()
        let store = CodexMonitorStore(defaults: defaults, resolver: { _ in try await gate.resolve() })
        let work = Task { await store.restore() }
        await gate.started(); store.disconnect()
        await gate.finish(.success(URL(fileURLWithPath: "/tmp/does-not-exist-" + UUID().uuidString)))
        await work.value
        XCTAssertNil(store.issue, "A stale restore must never attempt to reconnect after disconnect.")
        XCTAssertNil(store.directory)
        XCTAssertFalse(store.isConnecting)
    }
    @MainActor func testDelayedFailedResolutionCannotPublishAfterDisconnect() async {
        let name = "TokenfieldRestoreTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data([1]), forKey: "codex.monitor.readonly-folder.v1")
        let gate = ResolutionGate()
        let store = CodexMonitorStore(defaults: defaults, resolver: { _ in try await gate.resolve() })
        let work = Task { await store.restore() }
        await gate.started(); store.disconnect()
        await gate.finish(.failure(CocoaError(.fileReadNoPermission)))
        await work.value
        XCTAssertNil(store.issue, "A stale failure must not overwrite the current disconnected state.")
    }
}
