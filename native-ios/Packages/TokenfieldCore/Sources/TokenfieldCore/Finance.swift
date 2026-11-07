import Foundation

public struct SpendSlice: Codable, Equatable, Sendable, Identifiable {
    public var account: Account
    public var cny: Double
    public var color: String
    public var id: Int { account.id }
    public init(account: Account, cny: Double, color: String) { self.account = account; self.cny = cny; self.color = color }
}
public enum Verdict: String, Codable, Equatable, Sendable, CaseIterable { case great, ok, low, unknown }
public struct ValueReport: Codable, Equatable, Sendable {
    public var elapsed: Double
    public var uses: Int
    public var projected: Double
    public var apiEquivalent: Double
    public var fee: Double
    public var perUse: Double
    public var limitDays: Int
    public var verdict: Verdict
    public init(elapsed: Double, uses: Int, projected: Double, apiEquivalent: Double, fee: Double, perUse: Double, limitDays: Int, verdict: Verdict) {
        self.elapsed = elapsed; self.uses = uses; self.projected = projected; self.apiEquivalent = apiEquivalent; self.fee = fee; self.perUse = perUse; self.limitDays = limitDays; self.verdict = verdict
    }
}
public enum Finance {
    public static func cny(_ amount: Double, currency: Currency, rate: Double) -> Double { currency == .usd ? amount * rate : amount }
    public static func costPerUse(profile: UsageProfile, model: APIModel) -> Double {
        let input = profile.input * (1 - profile.cacheRatio) * model.input + profile.input * profile.cacheRatio * (model.cachedInput ?? model.input)
        return (input + profile.output * model.output) / 1_000_000
    }
    public static func monthlySpend(accounts: [Account], settings: AppSettings, catalog: Catalog = .bundled) -> [SpendSlice] {
        accounts.map { SpendSlice(account: $0, cny: cny($0.monthlyCost, currency: $0.currency, rate: settings.usdRate), color: catalog.provider($0.provider).color) }.sorted { $0.cny == $1.cny ? $0.id < $1.id : $0.cny > $1.cny }
    }
    public static func breakEvenUses(monthlyFeeCNY: Double, profile: UsageProfile, model: APIModel, usdRate: Double) -> Double {
        let cost = cny(costPerUse(profile: profile, model: model), currency: model.currency, rate: usdRate)
        return cost > 0 ? monthlyFeeCNY / cost : .infinity
    }
    public static func valueReport(account: Account, usage: [Usage], settings: AppSettings, model: APIModel?, now: Date = Date(), calendar: Calendar = .current) -> ValueReport {
        let calendar = DateCodec.gregorianCalendar(calendar)
        let start: Date
        let end: Date
        if let renewal = DateCodec.date(account.renewAt), let next = Schedule.rollMonthly(renewal, now: now, strictlyAfter: false, calendar: calendar), let previous = calendar.date(byAdding: .month, value: -1, to: next) {
            start = previous; end = next
        } else if let interval = calendar.dateInterval(of: .month, for: now) {
            start = interval.start; end = interval.end.addingTimeInterval(-0.001)
        } else { start = now; end = now.addingTimeInterval(1) }
        let firstDay = DateCodec.day(start, calendar: calendar)
        let lastDay = DateCodec.day(end, calendar: calendar)
        let entries = usage.filter { $0.accountId == account.id && $0.day >= firstDay && $0.day <= lastDay }
        let uses = entries.reduce(0) { result, entry in let (sum, overflow) = result.addingReportingOverflow(entry.count); return overflow ? Int.max : sum }
        let elapsed = min(1, max(0.03, now.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
        let projected = Double(uses) / elapsed
        let fee = cny(account.monthlyCost, currency: account.currency, rate: settings.usdRate)
        let api: Double = model.map { model in entries.reduce(0) { $0 + cny(costPerUse(profile: UsageProfile.profile(for: $1.intensity), model: model), currency: model.currency, rate: settings.usdRate) * Double($1.count) } } ?? 0
        let apiEquivalent = api / elapsed
        let verdict: Verdict = model == nil || uses == 0 ? .unknown : apiEquivalent >= fee ? .great : apiEquivalent >= fee * 0.5 ? .ok : .low
        return ValueReport(elapsed: elapsed, uses: uses, projected: projected, apiEquivalent: apiEquivalent, fee: fee, perUse: projected > 0 ? fee / projected : 0, limitDays: Set(entries.filter { $0.hitLimit == true }.map(\.day)).count, verdict: verdict)
    }
}
