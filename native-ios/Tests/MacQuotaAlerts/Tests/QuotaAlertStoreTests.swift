import XCTest
@testable import MacQuotaAlertsHarness
@testable import TokenfieldCore

@MainActor
final class QuotaAlertStoreTests: XCTestCase {
    func testFailedDurableIntentCommitNeverEnqueues() async throws {
        let f = Fixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = CodexQuotaFilePersistence(url: root.appendingPathComponent("state.json"))
        let store = CodexQuotaAlertStore(persistence: persistence, transport: f.transport, now: { f.clock.date })
        store.updateContext(quota: f.quota(8), directory: f.directory, healthy: true)
        await store.enableConfirmedSource()
        XCTAssertTrue(f.transport.sent.isEmpty)
        XCTAssertNotNil(store.lastIssue)
        XCTAssertNil(store.lastQueuedAt)
    }

    func testDurableIntentExistsBeforeEnqueueAndFreshStoreDoesNotRepeatCombinedAlert() async throws {
        let f = Fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("state.json")
        let first = CodexQuotaAlertStore(persistence: CodexQuotaFilePersistence(url: url), transport: f.transport, now: { f.clock.date })
        f.transport.pause = true
        first.updateContext(quota: f.quota(8, second: 18), directory: f.directory, healthy: true)
        let work = Task { await first.enableConfirmedSource() }
        await f.transport.waitForEnqueue()
        let onDisk = try JSONDecoder().decode(CodexQuotaAlertSavedState.self, from: Data(contentsOf: url))
        XCTAssertNotNil(onDisk.intent)
        let other = FakeTransport()
        let restored = CodexQuotaAlertStore(persistence: CodexQuotaFilePersistence(url: url), transport: other, now: { f.clock.date })
        restored.updateContext(quota: f.quota(8, second: 18), directory: f.directory, healthy: true)
        await restored.refresh()
        XCTAssertTrue(other.sent.isEmpty)
        XCTAssertNotNil(restored.interruptionNotice)
        XCTAssertNil(restored.lastQueuedAt)
        f.transport.resume(); await work.value
    }
    func testAlertsPresentationIsConsumedOnlyOnceAndQuotaCancelsOldDestination() {
        let navigation = CodexNotificationNavigation()
        navigation.openAlerts(); navigation.markHandled(prepareAlerts: true)
        XCTAssertTrue(navigation.takeAlertsPresentation())
        XCTAssertFalse(navigation.takeAlertsPresentation(), "Recreating the dashboard must not replay an old sheet")
        navigation.openAlerts(); navigation.markHandled(prepareAlerts: true)
        navigation.openQuota(); navigation.markHandled()
        XCTAssertFalse(navigation.takeAlertsPresentation())
    }
    func testRenewalReconciliationDoesNotOwnQuotaRequests() {
        let id = CodexQuotaNotificationRequest.prefix + "fixture"
        let plan = ReminderReconciliation(backup: Backup(), now: Date(), history: [:], pendingIDs: [id, "tokenfield.old-renewal"], deliveredIDs: [])
        XCTAssertFalse(plan.obsolete.contains(id))
        XCTAssertTrue(plan.obsolete.contains("tokenfield.old-renewal"))
    }
    func testOrdinaryRefreshDuringEnqueueDoesNotSwallowAlert() async {
        let f = Fixture()
        f.transport.pause = true
        f.observe(8)
        let enabling = Task { await f.store.enableConfirmedSource() }
        await f.transport.waitForEnqueue()
        let release = Task { f.transport.resume() }
        await f.store.refresh()
        await release.value; await enabling.value
        XCTAssertEqual(f.transport.sent.count, 1)
        XCTAssertEqual(f.transport.pending.count, 1)
        XCTAssertNotNil(f.store.lastQueuedAt)
    }
    func testUnhealthyAndFutureReportsCannotPoisonConfirmedSource() async {
        let f = Fixture()
        f.observe(50); await f.store.enableConfirmedSource()
        f.store.updateContext(quota: f.quota(8, reportedAt: f.clock.date.addingTimeInterval(30)), directory: f.directory, healthy: false)
        f.store.updateContext(quota: f.quota(8, reportedAt: f.clock.date.addingTimeInterval(60)), directory: f.directory, healthy: true)
        f.clock.date.addTimeInterval(1)
        f.observe(50); await f.store.refresh()
        XCTAssertTrue(f.transport.sent.isEmpty)
        f.clock.date.addTimeInterval(1)
        f.observe(8); await f.store.refresh()
        XCTAssertEqual(f.transport.sent.count, 1)
    }
    func testDefaultOffDoesNotPromptOrEnqueue() async {
        let f = Fixture()
        f.observe(8)
        await f.store.refresh()
        XCTAssertFalse(f.store.isEnabled)
        XCTAssertEqual(f.transport.promptCount, 0)
        XCTAssertTrue(f.transport.sent.isEmpty)
    }
    func testEnableMergesWindowsAndKeepsPrivateMetadataOutOfNotification() async {
        let f = Fixture()
        f.transport.permission = .notDetermined
        f.observe(18, second: 8)
        await f.store.enableConfirmedSource()
        XCTAssertEqual(f.transport.promptCount, 1)
        XCTAssertEqual(f.transport.sent.count, 1)
        let message = f.transport.sent.first
        XCTAssertTrue(message?.body.contains("5 小时") == true)
        XCTAssertTrue(message?.body.contains("7 天") == true)
        XCTAssertFalse(message?.identifier.contains("fixture") == true)
        XCTAssertFalse(message?.body.contains("/") == true)
        XCTAssertNotNil(f.store.lastQueuedAt)
    }
    func testRepeatedAndRelaunchedStoreDoesNotRepeat() async {
        let f = Fixture()
        f.observe(18)
        await f.store.enableConfirmedSource()
        await f.store.refresh()
        XCTAssertEqual(f.transport.sent.count, 1)
        let other = FakeTransport()
        let restored = CodexQuotaAlertStore(defaults: f.defaults, transport: other, now: { f.clock.date })
        restored.updateContext(quota: f.quota(18), directory: f.directory, healthy: true)
        await restored.refresh()
        XCTAssertTrue(restored.isEnabled)
        XCTAssertTrue(other.sent.isEmpty)
        XCTAssertEqual(other.promptCount, 0)
    }
    func testEscalationAndReboundDoNotRepeatLowerTier() async {
        let f = Fixture()
        f.observe(20); await f.store.enableConfirmedSource()
        f.clock.date.addTimeInterval(1)
        f.observe(8); await f.store.refresh()
        f.clock.date.addTimeInterval(1)
        f.observe(18); await f.store.refresh()
        XCTAssertEqual(f.transport.sent.count, 2)
    }
    func testDeniedPermissionDoesNotPretendToQueueAndCanRecover() async {
        let f = Fixture()
        f.transport.permission = .denied
        f.observe(8); await f.store.enableConfirmedSource()
        XCTAssertEqual(f.store.permission, .denied)
        XCTAssertNil(f.store.lastQueuedAt)
        XCTAssertEqual(f.transport.promptCount, 0)
        XCTAssertTrue(f.transport.sent.isEmpty)
        f.transport.permission = .allowed
        await f.store.refresh()
        XCTAssertEqual(f.transport.sent.count, 1)
    }
    func testFailureCanRetryWithSameStableIdentifier() async {
        let f = Fixture()
        f.transport.fail = true
        f.observe(18); await f.store.enableConfirmedSource()
        XCTAssertNotNil(f.store.lastIssue)
        XCTAssertNil(f.store.lastQueuedAt)
        let firstID = f.transport.attempts.first?.identifier
        f.transport.fail = false
        await f.store.refresh()
        XCTAssertEqual(f.transport.sent.count, 1)
        XCTAssertEqual(f.transport.sent.first?.identifier, firstID)
    }
    func testPermissionRequestFailureCanBeRetriedExplicitly() async {
        let f = Fixture()
        f.transport.permission = .notDetermined
        f.transport.failPermission = true
        f.observe(8); await f.store.enableConfirmedSource()
        XCTAssertNotNil(f.store.lastIssue)
        XCTAssertTrue(f.transport.sent.isEmpty)
        f.transport.failPermission = false
        await f.store.retry()
        XCTAssertEqual(f.transport.promptCount, 2)
        XCTAssertEqual(f.transport.sent.count, 1)
    }
    func testReconfirmWaitsForNewReportAndUsesNewScope() async {
        let f = Fixture()
        f.observe(8); await f.store.enableConfirmedSource()
        let oldID = f.transport.sent.first?.identifier
        f.clock.date.addTimeInterval(1)
        await f.store.reconfirmSource()
        XCTAssertEqual(f.transport.sent.count, 1)
        f.clock.date.addTimeInterval(1)
        f.observe(8); await f.store.refresh()
        XCTAssertEqual(f.transport.sent.count, 2)
        XCTAssertNotEqual(f.transport.sent.last?.identifier, oldID)
    }
    func testChangedDirectoryPausesUntilReconfirmedAndNewReport() async {
        let f = Fixture()
        f.observe(18); await f.store.enableConfirmedSource()
        f.directory = URL(fileURLWithPath: "/tmp/another-fixture")
        f.clock.date.addTimeInterval(1)
        f.observe(8); await f.store.refresh()
        XCTAssertTrue(f.store.needsSourceConfirmation)
        XCTAssertEqual(f.transport.sent.count, 1)
        await f.store.reconfirmSource()
        XCTAssertEqual(f.transport.sent.count, 1)
        f.clock.date.addTimeInterval(1)
        f.observe(8); await f.store.refresh()
        XCTAssertEqual(f.transport.sent.count, 2)
    }
    func testDisablePreservesOtherRemindersAndCycleAcknowledgement() async {
        let f = Fixture()
        f.transport.pending.insert("tokenfield.other-reminder")
        f.observe(18); await f.store.enableConfirmedSource()
        await f.store.disable()
        XCTAssertEqual(f.transport.pending, ["tokenfield.other-reminder"])
        await f.store.enableConfirmedSource()
        XCTAssertEqual(f.transport.sent.count, 1)
    }
    func testDisconnectStopsAndCleansOnlyQuotaPending() async {
        let f = Fixture()
        f.transport.pending.insert("other-reminder")
        f.observe(18); await f.store.enableConfirmedSource()
        f.store.updateContext(quota: nil, directory: nil, healthy: false)
        await f.store.refresh()
        XCTAssertEqual(f.transport.pending, ["other-reminder"])
    }
    func testOlderSnapshotCannotTriggerAfterNewerHealthyReport() async {
        let f = Fixture()
        f.observe(50); await f.store.enableConfirmedSource()
        f.store.updateContext(quota: f.quota(8, reportedAt: f.clock.date.addingTimeInterval(-1)), directory: f.directory, healthy: true)
        await f.store.refresh()
        XCTAssertTrue(f.transport.sent.isEmpty)
    }
    func testLateEnqueueAfterDisableIsRemovedAndCannotReenable() async {
        let f = Fixture()
        f.transport.pause = true
        f.observe(8)
        let enabling = Task { await f.store.enableConfirmedSource() }
        await f.transport.waitForEnqueue()
        let cancelled = f.transport.cancelCount
        let disabling = Task { await f.store.disable() }
        await f.transport.waitForCancellation(after: cancelled)
        XCTAssertFalse(f.store.isEnabled)
        f.transport.resume()
        await enabling.value; await disabling.value
        XCTAssertTrue(f.transport.pending.isEmpty)
        XCTAssertFalse(f.store.isEnabled)
    }
    func testInterruptedIntentDoesNotAutomaticallyRepeatOrClaimSuccess() async throws {
        let f = Fixture()
        let scope = CodexQuotaAlertScope(id: "confirmed-scope", sourceID: CodexQuotaAlertStore.sourceID(for: f.directory), reportAfter: nil)
        let plan = try XCTUnwrap(CodexQuotaAlertPolicy.plan(quota: f.quota(8), now: f.clock.date, scopeID: scope.id,
            includeEarlyWarning: true, reportAfter: nil, acknowledged: [:]))
        var state = CodexQuotaAlertSavedState()
        state.enabled = true; state.scope = scope
        state.intent = .init(identifier: "tokenfield.codex-quota.interrupted", receipts: plan.receipts)
        f.defaults.set(try JSONEncoder().encode(state), forKey: CodexQuotaAlertStore.preferenceKey)
        let restored = CodexQuotaAlertStore(defaults: f.defaults, transport: f.transport, now: { f.clock.date })
        restored.updateContext(quota: f.quota(8), directory: f.directory, healthy: true)
        await restored.refresh()
        XCTAssertTrue(f.transport.sent.isEmpty)
        XCTAssertNil(restored.lastQueuedAt)
        XCTAssertNotNil(restored.interruptionNotice)
    }
    func testNavigationPreservesDestinationWhileWaitingForSheet() {
        let navigation = CodexNotificationNavigation()
        navigation.openAlerts()
        XCTAssertEqual(navigation.destination, .alerts)
        XCTAssertTrue(navigation.hasPendingRequest)
        navigation.resumeAfterSheet()
        XCTAssertEqual(navigation.revision, 2)
        XCTAssertEqual(navigation.destination, .alerts)
        navigation.markHandled()
        navigation.resumeAfterSheet()
        XCTAssertEqual(navigation.revision, 2)
        navigation.openQuota()
        XCTAssertEqual(navigation.destination, .quota)
    }

    func testNavigationRetainsColdOpenRequestUntilRootHandlesIt() {
        let navigation = CodexNotificationNavigation()
        navigation.openQuota()
        XCTAssertTrue(navigation.hasPendingRequest)
        XCTAssertEqual(navigation.revision, 1)
        navigation.markHandled()
        XCTAssertFalse(navigation.hasPendingRequest)
        var opens = 0
        navigation.openMainWindow = { opens += 1 }
        navigation.openQuota()
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(navigation.revision, 2)
    }
}

@MainActor private final class Clock { var date = Date(timeIntervalSince1970: 1_800_000_000) }
@MainActor private final class Fixture {
    let defaults = UserDefaults(suiteName: "quota-alert-tests-" + UUID().uuidString)!
    let transport = FakeTransport()
    let clock = Clock()
    var directory = URL(fileURLWithPath: "/tmp/fixture-codex")
    lazy var store = CodexQuotaAlertStore(defaults: defaults, transport: transport, now: { [clock] in clock.date })
    func quota(_ remaining: Double, second: Double? = nil, reportedAt: Date? = nil) -> CodexQuotaSnapshot {
        .init(reportedAt: reportedAt ?? clock.date, limitID: "codex", plan: "plus",
            primary: .init(usedPercent: 100 - remaining, durationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)),
            secondary: second.map { .init(usedPercent: 100 - $0, durationMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 1_800_604_800)) })
    }
    func observe(_ remaining: Double, second: Double? = nil) { store.updateContext(quota: quota(remaining, second: second), directory: directory, healthy: true) }
}

@MainActor private final class FakeTransport: CodexQuotaAlertTransport {
    var permission = CodexQuotaNotificationPermission.allowed
    var promptCount = 0
    var sent: [CodexQuotaNotificationRequest] = []
    var attempts: [CodexQuotaNotificationRequest] = []
    var pending: Set<String> = []
    var fail = false, pause = false, failPermission = false
    var cancelCount = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var enqueueWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func authorization() async -> CodexQuotaNotificationPermission { permission }
    func requestAuthorization() async throws -> CodexQuotaNotificationPermission {
        promptCount += 1
        if failPermission { throw NSError(domain: "permission-test", code: 1) }
        permission = .allowed; return permission
    }
    func enqueue(_ request: CodexQuotaNotificationRequest) async throws {
        attempts.append(request)
        if pause {
            try await withCheckedThrowingContinuation { continuation = $0; enqueueWaiters.forEach { $0.resume() }; enqueueWaiters = [] }
        } else { enqueueWaiters.forEach { $0.resume() }; enqueueWaiters = [] }
        if fail { throw NSError(domain: "test", code: 1) }
        pending.insert(request.identifier); sent.append(request)
    }
    func cancelPending(prefix: String) async {
        pending = pending.filter { !$0.hasPrefix(prefix) }; cancelCount += 1
        let ready = cancelWaiters.filter { cancelCount > $0.0 }
        cancelWaiters.removeAll { cancelCount > $0.0 }
        ready.forEach { $0.1.resume() }
    }
    func cancelPending(identifier: String) async { pending.remove(identifier) }
    func waitForEnqueue() async { if continuation != nil { return }; await withCheckedContinuation { enqueueWaiters.append($0) } }
    func waitForCancellation(after count: Int) async { if cancelCount > count { return }; await withCheckedContinuation { cancelWaiters.append((count, $0)) } }
    func resume() { continuation?.resume(); continuation = nil; pause = false }
}
