import XCTest
import TokenfieldCore
@testable import MacQuotaAlertsHarness

@MainActor final class ExchangeRateStoreTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
    func quote() throws -> USDExchangeRateQuote {
        try .decode(Data(#"{"date":"2026-11-06","base":"USD","quote":"CNY","rate":6.6713}"#.utf8), now: now)
    }
    func testAutoRefreshAppliesPrecisionAndCachesAcrossStoreRecreation() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = RateClient(quote: try quote())
        let store = ExchangeRateStore(defaults: defaults, client: client, now: { self.now })
        var rates: [Double] = []
        await store.refreshIfNeeded { rates.append($0); return true }
        XCTAssertEqual(rates, [6.6713])
        XCTAssertEqual(store.quote?.date, "2026-11-06")
        let restored = ExchangeRateStore(defaults: defaults, client: client, now: { self.now })
        await restored.refreshIfNeeded { rates.append($0); return true }
        XCTAssertEqual(client.calls, 1)
        XCTAssertEqual(rates, [6.6713, 6.6713])
    }
    func testManualModePreventsLateNetworkResultFromOverwritingInput() async throws {
        let client = RateClient(quote: try quote()); client.paused = true
        let store = ExchangeRateStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, client: client, now: { self.now })
        var applied = false
        let work = Task { await store.refreshIfNeeded { _ in applied = true; return true } }
        await client.started()
        store.setAutomatic(false)
        client.finish(); await work.value
        XCTAssertFalse(applied)
        XCTAssertFalse(store.isAutomatic)
    }
    func testOfflineFailureKeepsPreviousRateAndAllowsExplicitRetry() async throws {
        let client = RateClient(quote: try quote()); client.fails = true
        let store = ExchangeRateStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, client: client, now: { self.now })
        var rate = 7.1
        await store.refreshIfNeeded { rate = $0; return true }
        XCTAssertEqual(rate, 7.1)
        XCTAssertNotNil(store.lastIssue)
        await store.refreshIfNeeded { rate = $0; return true }
        XCTAssertEqual(client.calls, 1, "Failure must not retry on every focus change")
        client.fails = false
        await store.refreshIfNeeded(force: true) { rate = $0; return true }
        XCTAssertEqual(rate, 6.6713)
        XCTAssertNil(store.lastIssue)
    }
    func testFailedBusinessSaveDoesNotClaimAppliedQuote() async throws {
        let store = ExchangeRateStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, client: RateClient(quote: try quote()), now: { self.now })
        await store.refreshIfNeeded { _ in false }
        XCTAssertNil(store.quote)
        XCTAssertNotNil(store.lastIssue)
    }
}

@MainActor private final class RateClient: ExchangeRateClient {
    let quote: USDExchangeRateQuote
    var calls = 0, paused = false, fails = false
    var continuation: CheckedContinuation<Void, Never>?
    var waiters: [CheckedContinuation<Void, Never>] = []
    init(quote: USDExchangeRateQuote) { self.quote = quote }
    func fetch(now: Date) async throws -> USDExchangeRateQuote {
        calls += 1
        if paused { await withCheckedContinuation { continuation = $0; waiters.forEach { $0.resume() }; waiters = [] } }
        if fails { throw URLError(.notConnectedToInternet) }
        return quote
    }
    func started() async { if continuation == nil { await withCheckedContinuation { waiters.append($0) } } }
    func finish() { continuation?.resume(); continuation = nil }
}
