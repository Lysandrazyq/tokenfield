import Foundation

/// A small, transcript-free projection for the menu bar. Activity is indeterminate,
/// because Codex telemetry does not provide a reliable task completion percentage.
public struct CodexStatusSummary: Equatable, Sendable {
    public let remainingPercent: Double?
    public let windowMinutes: Int?
    public let phase: CodexTaskPhase
    public let activeTasks: Int

    public static func make(snapshot: CodexMonitorSnapshot?, connected: Bool, now: Date) -> Self {
        guard connected, let snapshot else {
            return .init(remainingPercent: nil, windowMinutes: nil, phase: .unknown, activeTasks: 0)
        }
        let sessions = snapshot.sessions.filter { ($0.lastActivityAt ?? .distantPast) <= now }
        let running = sessions.filter { $0.phase(at: now) == .running }
        let latest = sessions.max { ($0.lastActivityAt ?? .distantPast) < ($1.lastActivityAt ?? .distantPast) }
        let phase: CodexTaskPhase = running.isEmpty ? (latest?.phase(at: now) ?? .unknown) : .running
        var limiting: CodexQuotaWindow?
        if let quota = snapshot.quota, quota.limitID == nil || quota.limitID == "codex",
           quota.reportedAt <= now, !quota.isStale(at: now) {
            limiting = [quota.primary, quota.secondary].compactMap { $0 }.filter {
                $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
                    && (1...525_600).contains($0.durationMinutes)
                    && $0.resetsAt.timeIntervalSince1970.isFinite && $0.resetsAt > now
            }.max {
                $0.usedPercent == $1.usedPercent ? $0.durationMinutes > $1.durationMinutes : $0.usedPercent < $1.usedPercent
            }
        }
        return .init(remainingPercent: limiting?.remainingPercent(at: now), windowMinutes: limiting?.durationMinutes,
                     phase: phase, activeTasks: running.count)
    }
}
