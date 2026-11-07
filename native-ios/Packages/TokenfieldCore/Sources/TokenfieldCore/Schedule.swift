import Foundation

public enum EventKind: String, Codable, Equatable, Sendable, CaseIterable {
    case renew, reset, expiry
    public var label: String { switch self { case .renew: return "续费"; case .reset: return "重置"; case .expiry: return "到期" } }
}
public struct TimelineEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: EventKind
    public var date: Date
    public var title: String
    public var accountID: Int?
    public var expiryID: Int?
    public var notify: Bool
    public init(id: String, kind: EventKind, date: Date, title: String, accountID: Int? = nil, expiryID: Int? = nil, notify: Bool) { self.id = id; self.kind = kind; self.date = date; self.title = title; self.accountID = accountID; self.expiryID = expiryID; self.notify = notify }
}
public struct Reminder: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var at: Date
    public var title: String
    public var body: String
    public init(id: String, at: Date, title: String, body: String) { self.id = id; self.at = at; self.title = title; self.body = body }
}
public enum Schedule {
    // Repeated month additions preserve the website's month-end clamping semantics.
    static func rollMonthly(_ start: Date, now: Date, strictlyAfter: Bool, calendar: Calendar) -> Date? {
        roll(start, component: .month, now: now, strictlyAfter: strictlyAfter, calendar: calendar)
    }
    private static func roll(_ start: Date, component: Calendar.Component, now: Date, strictlyAfter: Bool = true, calendar: Calendar) -> Date? {
        let calendar = DateCodec.gregorianCalendar(calendar)
        guard start.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite else { return nil }
        var result = start
        for _ in 0..<100_000 {
            if strictlyAfter ? result > now : result >= now { return result }
            guard let next = calendar.date(byAdding: component, value: 1, to: result), next > result else { return nil }
            result = next
        }
        return nil
    }
    public static func nextRenewal(_ account: Account, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard account.billing == .subscription, let start = DateCodec.date(account.renewAt) else { return nil }
        return rollMonthly(start, now: now, strictlyAfter: true, calendar: calendar)
    }
    public static func nextReset(_ account: Account, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard account.resetKind != .none, let anchor = DateCodec.date(account.resetAnchor), now.timeIntervalSince1970.isFinite else { return nil }
        switch account.resetKind {
        case .none: return nil
        case .hours:
            let hours = account.resetHours ?? 5
            let period = hours * 3600
            guard period.isFinite, period > 0 else { return nil }
            if anchor > now { return anchor }
            let steps = floor(now.timeIntervalSince(anchor) / period) + 1
            var result = anchor.addingTimeInterval(steps * period)
            // A fractional hour can round the quotient below an exact boundary.
            if result <= now { result = anchor.addingTimeInterval((steps + 1) * period) }
            return result.timeIntervalSince1970.isFinite && result > now ? result : nil
        case .weekly: return roll(anchor, component: .weekOfYear, now: now, calendar: calendar)
        case .monthly: return rollMonthly(anchor, now: now, strictlyAfter: true, calendar: calendar)
        }
    }
    public static func timeline(accounts: [Account], expiries: [Expiry], now: Date = Date(), calendar: Calendar = .current) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        for account in accounts {
            if let renewal = nextRenewal(account, now: now, calendar: calendar) {
                events.append(TimelineEvent(id: "renew-\(account.id)", kind: .renew, date: renewal, title: "\(account.name) 续费", accountID: account.id, notify: true))
            }
            if let reset = nextReset(account, now: now, calendar: calendar) {
                events.append(TimelineEvent(id: "reset-\(account.id)", kind: .reset, date: reset, title: "\(account.name) 额度重置", accountID: account.id, notify: account.notifyReset))
            }
        }
        for expiry in expiries where !expiry.done {
            guard let date = DateCodec.date(expiry.expiresAt) else { continue }
            let owner = accounts.first { $0.id == expiry.accountId }?.name
            let title = owner.flatMap { $0.isEmpty ? nil : "\($0) · \(expiry.title)" } ?? expiry.title
            events.append(TimelineEvent(id: "expiry-\(expiry.id)", kind: .expiry, date: date, title: title, accountID: expiry.accountId, expiryID: expiry.id, notify: true))
        }
        return events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    public static func countdown(_ target: Date, now: Date = Date()) -> String {
        let seconds = target.timeIntervalSince(now)
        guard seconds.isFinite, seconds >= 0 else { return "已过期" }
        let minutes = floor(seconds / 60)
        guard minutes < Double(Int.max) else { return "时间过远" }
        let mins = Int(minutes)
        if mins < 60 { return "\(mins) 分钟" }
        let hours = mins / 60
        if hours < 24 { return "\(hours) 时 \(mins % 60) 分" }
        return "\(hours / 24) 天 \(hours % 24) 时"
    }
    public static func reminders(backup: Backup, now: Date = Date(), calendar: Calendar = .current) -> [Reminder] {
        let calendar = DateCodec.gregorianCalendar(calendar)
        guard now.timeIntervalSince1970.isFinite, backup.settings.remindHours.isFinite, backup.settings.remindHours >= 0,
              let horizon = calendar.date(byAdding: .day, value: 45, to: now) else { return [] }
        var result: [Reminder] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        func identifier(_ event: TimelineEvent, _ date: Date) -> String {
            "\(event.id)-\(Int64((date.timeIntervalSince1970 * 1000).rounded()))"
        }
        for event in timeline(accounts: backup.accounts, expiries: backup.expiries, now: now, calendar: calendar) {
            guard event.notify, event.date > now, event.date <= horizon else { continue }
            if event.kind == .reset {
                guard let account = backup.accounts.first(where: { $0.id == event.accountID }) else { continue }
                var reset: Date? = event.date
                for _ in 0..<12 {
                    guard let date = reset, date <= horizon else { break }
                    result.append(Reminder(id: identifier(event, date), at: date, title: event.title, body: "额度已经重置，可以继续用了"))
                    reset = nextReset(account, now: date, calendar: calendar)
                }
            } else {
                var delivery = event.date.addingTimeInterval(-backup.settings.remindHours * 3600)
                if delivery <= now { delivery = now.addingTimeInterval(10) }
                guard delivery <= horizon else { continue }
                let when = formatter.string(from: event.date)
                let body = event.kind == .renew ? "将于 \(when) 自动续费，不想续记得取消" : "将于 \(when) 到期，别浪费了"
                result.append(Reminder(id: identifier(event, event.date), at: delivery, title: "⏰ \(event.title)", body: body))
            }
        }
        return Array(result.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }.prefix(60))
    }
}
