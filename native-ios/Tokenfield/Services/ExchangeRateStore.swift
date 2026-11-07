import Foundation
import Observation
import TokenfieldCore

@MainActor protocol ExchangeRateClient {
    func fetch(now: Date) async throws -> USDExchangeRateQuote
}

@MainActor struct FrankfurterExchangeRateClient: ExchangeRateClient {
    func fetch(now: Date) async throws -> USDExchangeRateQuote {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let url = URL(string: "https://api.frankfurter.dev/v2/providers/ecb/rate/USD/CNY")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 16_384 else { throw URLError(.badServerResponse) }
        return try USDExchangeRateQuote.decode(data, now: now)
    }
}

@MainActor @Observable
final class ExchangeRateStore {
    private struct Cache: Codable { let quote: USDExchangeRateQuote; let fetchedAt: Date }
    private(set) var isAutomatic: Bool
    private(set) var quote: USDExchangeRateQuote?
    private(set) var fetchedAt: Date?
    private(set) var isRefreshing = false
    private(set) var lastIssue: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: any ExchangeRateClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var work: Task<USDExchangeRateQuote, Error>?
    private static let modeKey = "exchange-rate.automatic.v1"
    private static let cacheKey = "exchange-rate.ecb-usd-cny.v1"

    init(defaults: UserDefaults = .standard, client: (any ExchangeRateClient)? = nil, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults; self.client = client ?? FrankfurterExchangeRateClient(); self.now = now
        isAutomatic = defaults.object(forKey: Self.modeKey) as? Bool ?? true
        if let data = defaults.data(forKey: Self.cacheKey), data.count <= 16_384,
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           cache.quote.isValid(at: now()), cache.fetchedAt <= now() {
            quote = cache.quote; fetchedAt = cache.fetchedAt
        }
    }

    func setAutomatic(_ value: Bool) {
        guard value != isAutomatic else { return }
        isAutomatic = value; defaults.set(value, forKey: Self.modeKey)
        generation &+= 1; work?.cancel(); work = nil; isRefreshing = false
        lastIssue = nil; lastAttempt = nil
    }

    func refreshIfNeeded(force: Bool = false, apply: (Double) -> Bool) async {
        guard isAutomatic, !isRefreshing else { return }
        let current = now()
        if !force, let quote, quote.isValid(at: current), let fetchedAt, current >= fetchedAt,
           current.timeIntervalSince(fetchedAt) < 6 * 3600 {
            if !apply(quote.rate) { lastIssue = "参考汇率已获取，但设置未能保存，请重试。" }
            return
        }
        if !force, let lastAttempt, current.timeIntervalSince(lastAttempt) < 900 { return }
        generation &+= 1
        let ticket = generation
        lastAttempt = current; isRefreshing = true; lastIssue = nil
        let task = Task { @MainActor [client] in try await client.fetch(now: current) }
        work = task
        defer { if ticket == generation { isRefreshing = false; work = nil } }
        do {
            let result = try await task.value
            guard ticket == generation, isAutomatic, result.isValid(at: now()) else { return }
            guard apply(result.rate) else { lastIssue = "参考汇率已获取，但设置未能保存，请重试。"; return }
            quote = result; fetchedAt = now()
            if let data = try? JSONEncoder().encode(Cache(quote: result, fetchedAt: now())) { defaults.set(data, forKey: Self.cacheKey) }
        } catch {
            guard ticket == generation else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { lastAttempt = nil }
            else { lastIssue = "暂时无法同步，继续使用现有汇率。可点击立即更新重试。" }
        }
    }
    deinit { work?.cancel() }
}
