import Foundation

public struct USDExchangeRateQuote: Codable, Equatable, Sendable {
    public let date: String
    public let rate: Double
    public static let source = "ECB · Frankfurter"

    public static func decode(_ data: Data, now: Date) throws -> Self {
        struct Response: Decodable { let date: String; let base: String; let quote: String; let rate: Double }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let value = Self(date: response.date, rate: response.rate)
        guard response.base == "USD", response.quote == "CNY", value.isValid(at: now) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return value
    }

    public func isValid(at now: Date) -> Bool {
        guard rate.isFinite, rate > 0 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let day = formatter.date(from: date), formatter.string(from: day) == date else { return false }
        return day <= now && now.timeIntervalSince(day) <= 14 * 86400
    }
}
