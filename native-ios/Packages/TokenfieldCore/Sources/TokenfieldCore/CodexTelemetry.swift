import Foundation

public enum CodexTaskPhase: String, Codable, Sendable {
    case running, completed, stopped, quiet, unknown
}

public struct CodexActivity: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case started, command, fileChange, tool, message, thinking, compaction, completed, stopped
    }
    public let timestamp: Date
    public let kind: Kind
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(kind.rawValue)" }
}

public struct CodexTokens: Codable, Equatable, Sendable {
    public let input: Int64?
    public let cachedInput: Int64?
    public let output: Int64?
    public let reasoningOutput: Int64?
    public let total: Int64?
}

public struct CodexQuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let durationMinutes: Int
    public let resetsAt: Date

    public func remainingPercent(at now: Date) -> Double? {
        now < resetsAt ? max(0, 100 - usedPercent) : nil
    }
}

public struct CodexQuotaSnapshot: Codable, Equatable, Sendable {
    public let reportedAt: Date
    public let limitID: String?
    public let plan: String?
    public let primary: CodexQuotaWindow?
    public let secondary: CodexQuotaWindow?
    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(reportedAt) > 300 || reportedAt.timeIntervalSince(now) > 30
    }
}

public struct CodexSessionSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let project: String?
    public let model: String?
    public let lastActivityAt: Date?
    public let tokens: CodexTokens?
    public let quota: CodexQuotaSnapshot?
    public let activities: [CodexActivity]
    private let recordedPhase: CodexTaskPhase

    public func phase(at now: Date) -> CodexTaskPhase {
        if recordedPhase == .running, let lastActivityAt, now.timeIntervalSince(lastActivityAt) > 90 { return .quiet }
        return recordedPhase
    }

    fileprivate init(id: String, title: String, project: String?, model: String?, lastActivityAt: Date?,
                     tokens: CodexTokens?, quota: CodexQuotaSnapshot?, activities: [CodexActivity], phase: CodexTaskPhase) {
        self.id = id; self.title = title; self.project = project; self.model = model
        self.lastActivityAt = lastActivityAt; self.tokens = tokens; self.quota = quota
        self.activities = activities; recordedPhase = phase
    }
}

/// Stores only telemetry. Prompt, reasoning, commands and tool results never enter a snapshot.
public struct CodexTelemetryAccumulator: Sendable {
    private var id: String
    private var project: String?
    private var model: String?
    private var lastActivity: Date?
    private var state = CodexTaskPhase.unknown
    private var lifecycleAt = Date.distantPast
    private var turnID: String?
    private var tokens: CodexTokens?
    private var quota: CodexQuotaSnapshot?
    private var activities: [CodexActivity] = []
    public private(set) var malformedLineCount = 0

    public init(fileID: String) { id = String(fileID.prefix(160)) }

    public mutating func consume(line: Data) {
        guard !line.isEmpty else { return }
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = record["type"] as? String, let payload = record["payload"] as? [String: Any] else {
            malformedLineCount += 1; return
        }
        if type == "session_meta" {
            if let value = payload["id"] as? String, !value.isEmpty { id = String(value.prefix(160)) }
            if let cwd = payload["cwd"] as? String { project = String(cwd.prefix(2048)) }
            return
        }
        guard let timestamp = record["timestamp"] as? String,
              let stamp = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp))
                ?? (try? Date.ISO8601FormatStyle().parse(timestamp)) else { return }
        if type == "turn_context" {
            if let value = payload["model"] as? String { model = String(value.prefix(120)) }
            return
        }
        if type == "event_msg", let event = payload["type"] as? String {
            switch event {
            case "task_started":
                guard stamp >= lifecycleAt else { return }
                lifecycleAt = stamp; turnID = payload["turn_id"] as? String; state = .running
                activity(.started, at: stamp)
            case "task_complete", "turn_aborted", "task_aborted":
                let completedID = payload["turn_id"] as? String
                guard stamp >= lifecycleAt, turnID == nil || completedID == nil || completedID == turnID else { return }
                lifecycleAt = stamp; state = event == "task_complete" ? .completed : .stopped
                activity(event == "task_complete" ? .completed : .stopped, at: stamp)
            case "token_count":
                if let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any] {
                    let value = CodexTokens(input: Self.count(usage["input_tokens"]), cachedInput: Self.count(usage["cached_input_tokens"]),
                        output: Self.count(usage["output_tokens"]), reasoningOutput: Self.count(usage["reasoning_output_tokens"]), total: Self.count(usage["total_tokens"]))
                    if value.input != nil || value.output != nil || value.total != nil { tokens = value }
                }
                if let limits = payload["rate_limits"] as? [String: Any],
                   limits["limit_id"] as? String == nil || limits["limit_id"] as? String == "codex" {
                    let primary = Self.window(limits["primary"]), secondary = Self.window(limits["secondary"])
                    if primary != nil || secondary != nil, quota == nil || stamp >= quota!.reportedAt {
                        quota = CodexQuotaSnapshot(reportedAt: stamp, limitID: limits["limit_id"] as? String,
                            plan: limits["plan_type"] as? String, primary: primary, secondary: secondary)
                    }
                }
                touch(stamp)
            case "item_completed":
                if let item = payload["item"] as? [String: Any], let kind = Self.kind(item["type"] as? String) {
                    activity(kind, at: stamp)
                    if stamp > lifecycleAt { state = .running }
                }
            default: break
            }
        } else if type == "response_item", let kind = Self.kind(payload["type"] as? String) {
            activity(kind, at: stamp)
            if stamp > lifecycleAt { state = .running }
        }
    }

    public func snapshot(title: String? = nil) -> CodexSessionSnapshot {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = project.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Codex 会话"
        return CodexSessionSnapshot(id: id, title: String((name?.isEmpty == false ? name! : fallback).prefix(160)),
            project: project, model: model, lastActivityAt: lastActivity, tokens: tokens, quota: quota, activities: activities, phase: state)
    }

    private mutating func touch(_ date: Date) {
        if lastActivity == nil || date > lastActivity! { lastActivity = date }
    }
    private mutating func activity(_ kind: CodexActivity.Kind, at date: Date) {
        touch(date)
        let item = CodexActivity(timestamp: date, kind: kind)
        if !activities.contains(item) { activities.append(item) }
        activities.sort { $0.timestamp < $1.timestamp }
        if activities.count > 8 { activities.removeFirst(activities.count - 8) }
    }
    private static func kind(_ type: String?) -> CodexActivity.Kind? {
        switch type {
        case "CommandExecution": return .command
        case "FileChange": return .fileChange
        case "McpToolCall", "function_call", "custom_tool_call": return .tool
        case "AgentMessage": return .message
        case "Reasoning", "reasoning": return .thinking
        case "ContextCompaction": return .compaction
        default: return nil
        }
    }
    private static func count(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue < Double(Int64.max),
              number.doubleValue.rounded(.down) == number.doubleValue else { return nil }
        return number.int64Value
    }
    private static func window(_ value: Any?) -> CodexQuotaWindow? {
        guard let data = value as? [String: Any], let percent = data["used_percent"] as? NSNumber,
              CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite,
              (0...100).contains(percent.doubleValue), let minutes = count(data["window_minutes"]), minutes > 0, minutes <= 525_600,
              let reset = data["resets_at"] as? NSNumber, reset.doubleValue.isFinite, reset.doubleValue > 0 else { return nil }
        return CodexQuotaWindow(usedPercent: percent.doubleValue, durationMinutes: Int(minutes), resetsAt: Date(timeIntervalSince1970: reset.doubleValue))
    }
}
