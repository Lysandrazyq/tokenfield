import XCTest
@testable import TokenfieldCore

final class ExchangeRateTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
    func data(rate: String = "6.6713", date: String = "2026-11-06", base: String = "USD", quote: String = "CNY") -> Data {
        Data("{\"date\":\"\(date)\",\"base\":\"\(base)\",\"quote\":\"\(quote)\",\"rate\":\(rate)}".utf8)
    }
    func testDailyReferenceKeepsFullPrecisionAndSourceDate() throws {
        let value = try USDExchangeRateQuote.decode(data(), now: now)
        XCTAssertEqual(value.rate, 6.6713)
        XCTAssertEqual(value.date, "2026-11-06")
    }
    func testWrongPairAndInvalidRatesAreRejected() {
        for value in [data(base: "CNY", quote: "USD"), data(rate: "0"), data(rate: "-1"), data(rate: "null")] {
            XCTAssertThrowsError(try USDExchangeRateQuote.decode(value, now: now))
        }
    }
    func testFutureStaleAndImpossibleDatesCannotBeAdopted() {
        for date in ["2026-11-08", "2026-10-01", "2026-02-30", "invalid"] {
            XCTAssertThrowsError(try USDExchangeRateQuote.decode(data(date: date), now: now))
        }
    }
    func testWeekendAndHolidayReferenceIsAcceptedWithoutPretendingItIsToday() throws {
        XCTAssertEqual(try USDExchangeRateQuote.decode(data(date: "2026-11-02"), now: now).date, "2026-11-02")
    }
}
