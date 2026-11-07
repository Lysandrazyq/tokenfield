#if os(macOS)
import Foundation
import Observation
import CryptoKit
import TokenfieldCore

struct CodexQuotaAlertScope: Codable {
    let id: String
    let sourceID: String
    let reportAfter: Date?
}
struct CodexQuotaAlertIntent: Codable {
    let identifier: String
    let receipts: [String: Date]
}
struct CodexQuotaAlertSavedState: Codable {
    var enabled = false
    var includeEarlyWarning = true
    var scope: CodexQuotaAlertScope?
    var acknowledged: [String: Date] = [:]
    var intent: CodexQuotaAlertIntent?
    var lastQueuedAt: Date?
    var interrupted = false
}

@MainActor @Observable
final class CodexQuotaAlertStore {
    static let preferenceKey = "codex.quota-alerts.v1"
    private(set) var permission = CodexQuotaNotificationPermission.notDetermined
    private(set) var lastIssue: String?
    private(set) var isRequestingPermission = false
    private var saved = CodexQuotaAlertSavedState()
    private var quota: CodexQuotaSnapshot?
    private var currentSourceID: String?
    private var healthy = false
    @ObservationIgnored private var greatestReportAt: Date?
    @ObservationIgnored private let persistence: any CodexQuotaAlertPersistence
    @ObservationIgnored private let transport: any CodexQuotaAlertTransport
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var workFinished = true
    @ObservationIgnored private var permissionRequestID: UUID?

    var isEnabled: Bool { saved.enabled }
    var includeEarlyWarning: Bool { saved.includeEarlyWarning }
    var isConnected: Bool { healthy && currentSourceID != nil }
    var needsSourceConfirmation: Bool { saved.enabled && currentSourceID != saved.scope?.sourceID }
    var lastQueuedAt: Date? { saved.lastQueuedAt }
    var interruptionNotice: String? {
        saved.interrupted ? "上次提醒处理中断，可能未显示。为避免重复，本级不自动重发；下一等级或新周期仍可提醒。" : nil
    }

    init(defaults: UserDefaults? = nil, persistence: (any CodexQuotaAlertPersistence)? = nil,
         transport: any CodexQuotaAlertTransport, now: @escaping () -> Date = { Date() }) {
        self.persistence = persistence ?? defaults.map { CodexQuotaPreferencePersistence(defaults: $0) } ?? CodexQuotaFilePersistence()
        self.transport = transport; self.now = now
        do {
            if let data = try self.persistence.load() { saved = try JSONDecoder().decode(CodexQuotaAlertSavedState.self, from: data) }
        } catch { lastIssue = "提醒设置无法读取，已暂停。请重新确认来源后开启。" }
        if let intent = saved.intent {
            // A crash may occur after acceptance but before receipt persistence. Never blindly resend.
            saved.acknowledged.merge(intent.receipts) { max($0, $1) }
            saved.intent = nil; saved.interrupted = true
            persist()
        }
    }

    static func sourceID(for directory: URL) -> String {
        let directory = directory.standardizedFileURL
        let root = directory.lastPathComponent == "sessions" ? directory.deletingLastPathComponent() : directory
        return hash(root.path)
    }
    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func updateContext(quota candidate: CodexQuotaSnapshot?, directory: URL?, healthy: Bool) {
        let source = directory.flatMap { $0.isFileURL ? Self.sourceID(for: $0) : nil }
        let healthy = healthy && source != nil
        let eligible = healthy && candidate.map { $0.reportedAt <= now() && !$0.isStale(at: now()) } == true
        var next = eligible ? candidate : nil
        if source != currentSourceID { greatestReportAt = nil }
        if eligible, let candidate, let greatestReportAt, candidate.reportedAt < greatestReportAt {
            next = quota // Ignore an out-of-order report without resurrecting data cleared by a failure.
        } else if eligible, let candidate { greatestReportAt = candidate.reportedAt }
        guard source != currentSourceID || next != quota || healthy != self.healthy else { return }
        currentSourceID = source; quota = next; self.healthy = healthy
        schedule()
    }

    func enableConfirmedSource() async {
        guard isConnected, let source = currentSourceID, !isRequestingPermission else { return }
        if saved.scope?.sourceID != source {
            saved.scope = .init(id: UUID().uuidString, sourceID: source, reportAfter: saved.scope == nil ? nil : now())
            saved.lastQueuedAt = nil; saved.interrupted = false
        }
        saved.enabled = true; lastIssue = nil
        generation &+= 1; work?.cancel()
        persist()
        let scopeID = saved.scope?.id
        let requestID = UUID()
        permissionRequestID = requestID; isRequestingPermission = true
        do {
            let current = await transport.authorization()
            let result = current == .notDetermined ? try await transport.requestAuthorization() : current
            guard permissionRequestID == requestID else { return }
            isRequestingPermission = false
            guard saved.enabled, saved.scope?.id == scopeID, currentSourceID == source else { return }
            permission = result
            await refresh()
        } catch {
            guard permissionRequestID == requestID else { return }
            isRequestingPermission = false
            if saved.enabled, saved.scope?.id == scopeID { lastIssue = "通知权限请求失败，可重试：\(error.localizedDescription)" }
        }
    }

    func reconfirmSource() async {
        guard saved.enabled, isConnected, let source = currentSourceID, !isRequestingPermission else { return }
        saved.scope = .init(id: UUID().uuidString, sourceID: source, reportAfter: now())
        saved.lastQueuedAt = nil; saved.interrupted = false; lastIssue = nil
        persist()
        await schedule().value
    }

    func disable() async {
        saved.enabled = false
        permissionRequestID = nil; isRequestingPermission = false
        persist()
        await schedule().value
    }

    func setEarlyWarning(_ enabled: Bool) async {
        saved.includeEarlyWarning = enabled; persist()
        await schedule().value
    }

    func dismissInterruptionNotice() { saved.interrupted = false; persist() }

    func refresh() async { await schedule(invalidate: false).value }

    func retry() async {
        if saved.enabled, isConnected, !needsSourceConfirmation, permission == .notDetermined {
            await enableConfirmedSource()
        } else { await refresh() }
    }

    private var requiresCleanup: Bool {
        !saved.enabled || !isConnected || needsSourceConfirmation ||
            (saved.scope?.reportAfter.map { (quota?.reportedAt ?? .distantPast) <= $0 } ?? false)
    }

    @discardableResult private func schedule(invalidate: Bool = true) -> Task<Void, Never> {
        // Foreground/permission refreshes must not cancel a still-valid pending add.
        if !invalidate, !workFinished, let work, !work.isCancelled { return work }
        let previous = work
        previous?.cancel()
        generation &+= 1
        let ticket = generation
        workFinished = false
        // Cleanup is part of the barrier, so re-enabling cannot race a still-running cancellation.
        let cleanup: Task<Void, Never>? = requiresCleanup ? Task { @MainActor [transport] in
            await transport.cancelPending(prefix: CodexQuotaNotificationRequest.prefix)
        } : nil
        let next = Task { @MainActor [weak self] in
            defer { if self?.generation == ticket { self?.workFinished = true } }
            await cleanup?.value
            await previous?.value
            guard let self, self.accepts(ticket) else { return }
            await self.evaluate(ticket)
        }
        work = next
        return next
    }

    private func accepts(_ ticket: Int) -> Bool { ticket == generation && !Task.isCancelled }

    private func evaluate(_ ticket: Int) async {
        guard saved.enabled, isConnected, !needsSourceConfirmation, !isRequestingPermission,
              let scope = saved.scope else { return }
        let authorization = await transport.authorization()
        guard accepts(ticket) else { return }
        permission = authorization
        guard authorization == .allowed else { return }
        let current = now()
        saved.acknowledged = saved.acknowledged.filter { $0.value > current }
        if saved.acknowledged.count > 2048 {
            let keep = saved.acknowledged.sorted { $0.value > $1.value }.prefix(2048)
            saved.acknowledged = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        guard let plan = CodexQuotaAlertPolicy.plan(quota: quota, now: current, scopeID: scope.id,
            includeEarlyWarning: saved.includeEarlyWarning, reportAfter: scope.reportAfter, acknowledged: saved.acknowledged),
              let quota else { lastIssue = nil; return }
        let request = Self.notification(plan: plan, reportedAt: quota.reportedAt)
        saved.intent = .init(identifier: request.identifier, receipts: plan.receipts)
        // Do not enter the notification center until the intent is committed successfully.
        guard persist() else { saved.intent = nil; return }
        do {
            try await transport.enqueue(request)
            saved.acknowledged.merge(plan.receipts) { max($0, $1) }
            saved.intent = nil
            if accepts(ticket), saved.enabled {
                saved.lastQueuedAt = now(); saved.interrupted = false; lastIssue = nil
            }
            persist()
            if !accepts(ticket) || !saved.enabled { await transport.cancelPending(identifier: request.identifier) }
        } catch {
            if saved.intent?.identifier == request.identifier { saved.intent = nil; persist() }
            guard accepts(ticket) else { return }
            lastIssue = "提醒未能排队，可重试：\(error.localizedDescription)"
        }
    }

    private static func notification(plan: CodexQuotaAlertPlan, reportedAt: Date) -> CodexQuotaNotificationRequest {
        let parts = plan.windows.map { window in
            let minutes = window.durationMinutes
            let duration = minutes % 1440 == 0 ? "\(minutes / 1440) 天" : minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
            let remaining = window.remainingPercent.formatted(.number.precision(.fractionLength(0...1)))
            return "\(duration)窗口剩余 \(remaining)%，重置 \(window.resetsAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return .init(identifier: CodexQuotaNotificationRequest.prefix + hash(plan.identity), title: "Codex 额度较低",
            body: "所选日志最近上报：\(parts.joined(separator: "；"))。上报于 \(reportedAt.formatted(date: .omitted, time: .shortened))。")
    }

    func status(at date: Date) -> String {
        guard saved.enabled else { return "未开启" }
        if !isConnected { return "连接 Codex 后继续提醒" }
        if needsSourceConfirmation { return "日志来源已改变，请重新确认" }
        if isRequestingPermission { return "等待系统通知许可" }
        if permission == .denied { return "通知未获允许，请到系统设置开启" }
        if permission != .allowed { return "尚未允许系统通知" }
        guard let quota, !quota.isStale(at: date), quota.reportedAt <= date,
              [quota.primary, quota.secondary].compactMap({ $0 }).contains(where: { $0.remainingPercent(at: date) != nil }) else {
            return "等待有效额度上报"
        }
        if let after = saved.scope?.reportAfter, quota.reportedAt <= after { return "等待重新确认后的新上报" }
        if lastIssue != nil { return "提醒需要重试" }
        return saved.includeEarlyWarning ? "已开启 · 20% / 10% 两级提醒" : "已开启 · 10% 提醒"
    }

    @discardableResult private func persist() -> Bool {
        do {
            try persistence.save(JSONEncoder().encode(saved))
            return true
        } catch {
            lastIssue = "提醒记录无法保存，已停止本次排队，可重试：\(error.localizedDescription)"
            return false
        }
    }

    deinit { work?.cancel() }
}
#endif
