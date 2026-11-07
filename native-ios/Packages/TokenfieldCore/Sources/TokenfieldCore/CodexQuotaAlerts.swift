import Foundation

public enum CodexQuotaAlertLevel: Int, Codable, Equatable, Sendable {
    case critical = 10
    case early = 20
}

public struct CodexQuotaAlertWindow: Codable, Equatable, Sendable {
    public let durationMinutes: Int
    public let remainingPercent: Double
    public let resetsAt: Date
    public let level: CodexQuotaAlertLevel
}

/// A receipt acknowledges a queue attempt, not proof that the user saw a banner.
public struct CodexQuotaAlertPlan: Codable, Equatable, Sendable {
    public let windows: [CodexQuotaAlertWindow]
    public let receipts: [String: Date]
    public var identity: String { receipts.keys.sorted().joined(separator: "\n") }
}

public enum CodexQuotaAlertPolicy {
    public static func plan(quota: CodexQuotaSnapshot?, now: Date, scopeID: String,
                            includeEarlyWarning: Bool, reportAfter: Date?,
                            acknowledged: [String: Date]) -> CodexQuotaAlertPlan? {
        guard !scopeID.isEmpty, let quota, quota.limitID == nil || quota.limitID == "codex",
              !quota.isStale(at: now), quota.reportedAt <= now,
              reportAfter == nil || quota.reportedAt > reportAfter! else { return nil }
        var unique: [String: CodexQuotaWindow] = [:]
        for window in [quota.primary, quota.secondary].compactMap({ $0 }) {
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
                  window.durationMinutes > 0, window.durationMinutes <= 525_600,
                  window.resetsAt.timeIntervalSince1970.isFinite, now < window.resetsAt else { continue }
            let cycle = "\(window.durationMinutes)|\(window.resetsAt.timeIntervalSince1970)"
            if unique[cycle] == nil || window.usedPercent > unique[cycle]!.usedPercent { unique[cycle] = window }
        }
        var windows: [CodexQuotaAlertWindow] = []
        var receipts: [String: Date] = [:]
        for (cycle, window) in unique {
            let prefix = scopeID + "|" + cycle + "|"
            let criticalKey = prefix + "10", earlyKey = prefix + "20"
            let acknowledgedCritical = (acknowledged[criticalKey] ?? .distantPast) > now
            guard !acknowledgedCritical, let remaining = window.remainingPercent(at: now) else { continue }
            let level: CodexQuotaAlertLevel
            if remaining <= 10 { level = .critical }
            else if remaining <= 20, includeEarlyWarning, (acknowledged[earlyKey] ?? .distantPast) <= now { level = .early }
            else { continue }
            windows.append(.init(durationMinutes: window.durationMinutes, remainingPercent: remaining,
                                 resetsAt: window.resetsAt, level: level))
            let expiry = window.resetsAt.addingTimeInterval(86_400)
            receipts[earlyKey] = expiry
            if level == .critical { receipts[criticalKey] = expiry }
        }
        guard !windows.isEmpty else { return nil }
        windows.sort {
            $0.durationMinutes == $1.durationMinutes ? $0.resetsAt < $1.resetsAt : $0.durationMinutes < $1.durationMinutes
        }
        return CodexQuotaAlertPlan(windows: windows, receipts: receipts)
    }
}
