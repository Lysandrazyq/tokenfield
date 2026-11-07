import XCTest
@testable import TokenfieldCore

final class FinanceTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func testBundledCatalogSupportsPricingAndBlankAccount() throws {
        let catalog = Catalog.bundled
        XCTAssertNotNil(DateCodec.date(catalog.latestCheck))
        XCTAssertFalse(catalog.provider("deepseek").hasSubscription)
        XCTAssertTrue(catalog.plans(for: "deepseek").isEmpty)
        XCTAssertEqual(catalog.provider("missing").key, "custom")
        XCTAssertFalse(catalog.models(for: "claude").isEmpty)
        let blank = Account.blank(now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(blank.planId, "chatgpt-plus")
        XCTAssertEqual(blank.monthlyCost, 20)
        XCTAssertEqual(blank.createdAt, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(try JSONDecoder().decode(Catalog.self, from: JSONEncoder().encode(catalog)), catalog)
    }
    func testBlankAccountSetsRenewalAndBalancedModelForReports() throws {
        let originalZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        defer { NSTimeZone.default = originalZone }
        let now = try XCTUnwrap(DateCodec.date("2026-10-15T13:45:00Z"))
        let blank = Account.blank(now: now)
        XCTAssertEqual(blank.renewAt, "2026-11-15T00:00:00.000Z")
        XCTAssertEqual(blank.modelId, "gpt-6.1-sol")
        XCTAssertEqual(Schedule.timeline(accounts: [blank], expiries: [], now: now, calendar: calendar).map(\.kind), [.renew])
    }

    func testBlankAccountUsesCurrentCatalogInsteadOfMissingDefaultPrice() throws {
        let catalog = Catalog(providers: [Provider(key: "sample", name: "示例", color: "#123456",
            hasSubscription: true, defaultBilling: .subscription, currency: .cny)],
            plans: [Plan(id: "sample-plan", provider: "sample", name: "Standard", price: 42, currency: .cny,
                limits: "Test", resetKind: .weekly, source: "https://example.com/pricing", checked: "2026-10-31")],
            models: [APIModel(id: "sample-model", provider: "sample", name: "Example", input: 1, output: 2,
                currency: .cny, tier: "balanced", source: "https://example.com/pricing", checked: "2026-10-31")])
        let blank = Account.blank(catalog: catalog)
        XCTAssertEqual(blank.name, "示例 Standard")
        XCTAssertEqual(blank.provider, "sample")
        XCTAssertEqual(blank.planId, "sample-plan")
        XCTAssertEqual(blank.modelId, "sample-model")
        XCTAssertEqual(blank.monthlyCost, 42)
        XCTAssertEqual(blank.currency, .cny)
        XCTAssertEqual(blank.resetKind, .weekly)
        let noPrices = Account.blank(catalog: Catalog())
        XCTAssertEqual(noPrices.monthlyCost, 0)
        XCTAssertNil(noPrices.planId)
    }
    // Literal JS parity figures detect currency, cache ratio, and million-token mistakes.
    func testPriceFixturesAndSpendSorting() throws {
        let catalog = Catalog.bundled
        let opus = try XCTUnwrap(catalog.models.first { $0.id == "claude-opus-5.5" })
        let agent = UsageProfile.profile(for: .agent)
        XCTAssertEqual(Finance.costPerUse(profile: agent, model: opus), 1.408, accuracy: 0.000001)
        XCTAssertEqual((Finance.cny(Finance.costPerUse(profile: agent, model: opus), currency: .usd, rate: 7.1) * 180).rounded(), 1799)
        let max5 = try XCTUnwrap(catalog.plans.first { $0.id == "claude-max5" })
        let glm = try XCTUnwrap(catalog.plans.first { $0.id == "glm-lite" })
        XCTAssertEqual(Finance.cny(max5.price, currency: max5.currency, rate: 7.1), 710)
        XCTAssertEqual(glm.price, 118)
        XCTAssertEqual(Finance.breakEvenUses(monthlyFeeCNY: 710, profile: agent, model: opus, usdRate: 7.1), 71.02272727, accuracy: 0.000001)
        let slices = Finance.monthlySpend(accounts: [Account(id: 1, monthlyCost: 118, currency: .cny), Account(id: 2, provider: "claude", monthlyCost: 100)], settings: AppSettings())
        XCTAssertEqual(slices.map(\.id), [2, 1])
        XCTAssertEqual(slices.map(\.cny), [710, 118])
        XCTAssertEqual(try XCTUnwrap(slices.first).color, "#d97757")
    }
    // Detects account/day filtering, omitted intensity rows and renewal-period mistakes.
    func testValueReportUsesOnlyCurrentAccountAndCycle() throws {
        let account = Account(id: 1, monthlyCost: 100, renewAt: "2026-10-31T00:00:00Z")
        let now = try XCTUnwrap(DateCodec.date("2026-10-15T00:00:00Z"))
        let entries = [
            Usage(id: 1, accountId: 1, day: "2026-10-01", count: 10, intensity: .agent, hitLimit: true),
            Usage(id: 2, accountId: 1, day: "2026-10-01", count: 2, intensity: .chat, hitLimit: true),
            Usage(id: 3, accountId: 2, day: "2026-10-01", count: 999, intensity: .agent),
            Usage(id: 4, accountId: 1, day: "2026-09-29", count: 999, intensity: .agent)
        ]
        let model = try XCTUnwrap(Catalog.bundled.models.first { $0.id == "claude-opus-5.5" })
        let report = Finance.valueReport(account: account, usage: entries, settings: AppSettings(), model: model, now: now, calendar: calendar)
        XCTAssertEqual(report.elapsed, 15.0 / 31.0, accuracy: 0.000001)
        XCTAssertEqual(report.uses, 12)
        XCTAssertEqual(report.projected, 24.8, accuracy: 0.000001)
        XCTAssertEqual(report.fee, 710)
        XCTAssertEqual(report.limitDays, 1)
        XCTAssertEqual(report.apiEquivalent, 207.0198972, accuracy: 0.000001)
        XCTAssertEqual(report.perUse, 28.6290322581, accuracy: 0.000001)
        XCTAssertEqual(report.verdict, .low)
        let empty = Finance.valueReport(account: account, usage: [], settings: AppSettings(), model: nil, now: now, calendar: calendar)
        XCTAssertEqual(empty.verdict, .unknown)
        XCTAssertEqual(empty.perUse, 0)
    }
    func testReportKeepsGregorianMonthForNonGregorianDisplayCalendars() throws {
        let now = try XCTUnwrap(DateCodec.date("2026-10-15T12:00:00Z"))
        let usage = [
            Usage(id: 1, accountId: 1, day: "2026-10-01", count: 2, intensity: .chat),
            Usage(id: 2, accountId: 1, day: "2026-10-15", count: 3, intensity: .chat),
            Usage(id: 3, accountId: 1, day: "2026-09-30", count: 99, intensity: .chat)
        ]
        for identifier in [Calendar.Identifier.buddhist, .islamicUmmAlQura] {
            var displayCalendar = Calendar(identifier: identifier)
            displayCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let report = Finance.valueReport(account: Account(id: 1), usage: usage, settings: AppSettings(), model: nil, now: now, calendar: displayCalendar)
            XCTAssertEqual(report.uses, 5, "\(identifier)")
            XCTAssertEqual(report.elapsed, 14.5 / 31.0, accuracy: 0.000001, "\(identifier)")
        }
    }

    func testCalendarMonthAndVerdictBoundaries() throws {
        let now = try XCTUnwrap(DateCodec.date("2026-10-01T00:00:00Z"))
        let usage = [Usage(id: 1, accountId: 1, day: "2026-10-01", count: 1, intensity: .agent)]
        let model = try XCTUnwrap(Catalog.bundled.models.first { $0.id == "claude-opus-5.5" })
        var account = Account(id: 1, monthlyCost: 20)
        var report = Finance.valueReport(account: account, usage: usage, settings: AppSettings(), model: model, now: now, calendar: calendar)
        XCTAssertEqual(report.elapsed, 0.03)
        XCTAssertEqual(report.verdict, .great)
        account.monthlyCost = 60
        report = Finance.valueReport(account: account, usage: usage, settings: AppSettings(), model: model, now: now, calendar: calendar)
        XCTAssertEqual(report.verdict, .ok)
    }
}
