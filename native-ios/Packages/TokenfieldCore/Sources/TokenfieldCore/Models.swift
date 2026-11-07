import Foundation

public enum Billing: String, Codable, Equatable, Sendable, CaseIterable {
    case subscription, payg, balance
    public var label: String { switch self { case .subscription: return "会员订阅"; case .payg: return "按量付费"; case .balance: return "中转站余额" } }
    public var costLabel: String { switch self { case .subscription: return "月费"; case .payg: return "本月预计花费"; case .balance: return "本月充值" } }
}
public enum Currency: String, Codable, Equatable, Sendable, CaseIterable {
    case cny = "CNY", usd = "USD"
    public var symbol: String { self == .cny ? "¥" : "$" }
}
public enum ResetKind: String, Codable, Equatable, Sendable, CaseIterable {
    case none, hours, weekly, monthly
    public var label: String { switch self { case .none: return "不追踪"; case .hours: return "每隔几小时"; case .weekly: return "每周"; case .monthly: return "每月" } }
}
public enum Intensity: String, Codable, Equatable, Sendable, CaseIterable {
    case chat, write, code, agent
    public var label: String { switch self { case .chat: return "问答"; case .write: return "写作"; case .code: return "写代码"; case .agent: return "Agent" } }
}

public struct Account: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var provider: String
    public var billing: Billing
    public var monthlyCost: Double
    public var currency: Currency
    public var renewAt: String?
    public var balance: Double?
    public var resetKind: ResetKind
    public var resetHours: Double?
    public var resetAnchor: String?
    public var notifyReset: Bool
    public var models: String
    public var note: String
    public var createdAt: String
    public var planId: String?
    public var modelId: String?
    public init(id: Int = 0, name: String = "", provider: String = "chatgpt", billing: Billing = .subscription, monthlyCost: Double = 20, currency: Currency = .usd, renewAt: String? = nil, balance: Double? = nil, resetKind: ResetKind = .none, resetHours: Double? = 5, resetAnchor: String? = nil, notifyReset: Bool = false, models: String = "", note: String = "", createdAt: String = DateCodec.iso(Date()), planId: String? = nil, modelId: String? = nil) {
        self.id = id; self.name = name; self.provider = provider; self.billing = billing; self.monthlyCost = monthlyCost; self.currency = currency; self.renewAt = renewAt; self.balance = balance; self.resetKind = resetKind; self.resetHours = resetHours; self.resetAnchor = resetAnchor; self.notifyReset = notifyReset; self.models = models; self.note = note; self.createdAt = createdAt; self.planId = planId; self.modelId = modelId
    }
    public static func blank(catalog: Catalog = .bundled, now: Date = Date()) -> Account {
        let plan = catalog.plans.first { $0.id == "chatgpt-plus" } ?? catalog.plans.first
        let provider = plan.map { catalog.provider($0.provider) }
            ?? catalog.providers.first(where: { $0.key == "custom" })
            ?? catalog.providers.first
            ?? catalog.provider("custom")
        let calendar = DateCodec.gregorianCalendar(Calendar.current)
        let renewal = calendar.date(byAdding: .month, value: 1, to: now).map { calendar.startOfDay(for: $0) }
        let models = catalog.models(for: provider.key)
        let model = models.first { $0.tier == "balanced" } ?? models.first
        let name = plan.map { provider.name + " " + $0.name } ?? provider.name
        return Account(name: name, provider: provider.key, billing: plan == nil ? provider.defaultBilling : .subscription,
            monthlyCost: plan?.price ?? 0, currency: plan?.currency ?? provider.currency,
            renewAt: plan == nil ? nil : renewal.map(DateCodec.iso), resetKind: plan?.resetKind ?? .none,
            resetHours: plan?.resetHours ?? 5, createdAt: DateCodec.iso(now), planId: plan?.id, modelId: model?.id)
    }
}
public struct Expiry: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var accountId: Int?
    public var expiresAt: String
    public var done: Bool
    public init(id: Int = 0, title: String = "到期项", accountId: Int? = nil, expiresAt: String = DateCodec.iso(Date()), done: Bool = false) {
        self.id = id; self.title = title; self.accountId = accountId; self.expiresAt = expiresAt; self.done = done
    }
}
public struct Usage: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var accountId: Int
    public var day: String
    public var count: Int
    public var intensity: Intensity
    public var hitLimit: Bool?
    public init(id: Int = 0, accountId: Int, day: String, count: Int, intensity: Intensity, hitLimit: Bool? = nil) {
        self.id = id; self.accountId = accountId; self.day = day; self.count = count; self.intensity = intensity; self.hitLimit = hitLimit
    }
}
public struct AppSettings: Codable, Equatable, Sendable {
    public var id: String
    public var usdRate: Double
    public var remindHours: Double
    public var handle: String
    public init(id: String = "main", usdRate: Double = 7.1, remindHours: Double = 24, handle: String = "") {
        self.id = id; self.usdRate = usdRate; self.remindHours = remindHours; self.handle = handle
    }
}

public enum DateCodec {
    // Backups use website/Gregorian dates regardless of the user's display calendar.
    static func gregorianCalendar(_ calendar: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = calendar.timeZone
        result.locale = Locale(identifier: "en_US_POSIX")
        return result
    }
    public static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    public static func date(_ string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        let prefix = String(string.prefix(10))
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.isLenient = false
        guard let dayDate = dayFormatter.date(from: prefix), dayFormatter.string(from: dayDate) == prefix else { return nil }
        if string.count == 10 { return dayDate }
        guard string.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) != nil else { return nil }
        let time = string.dropFirst(11).prefix(8).split(separator: ":").compactMap { Int($0) }
        guard time.count == 3, time[0] < 24, time[1] < 60, time[2] < 60 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let calendar = gregorianCalendar(calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
