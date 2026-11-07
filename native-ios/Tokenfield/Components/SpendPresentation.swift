import Foundation
import TokenfieldCore

struct SpendPresentation {
    let slices: [SpendSlice]
    let total: Double?
    private let logarithms: [Int: Double]
    private let largestLog: Double
    private let scaledTotal: Double
    init(backup: Backup, catalog: Catalog = .bundled) {
        let raw = Finance.monthlySpend(accounts: backup.accounts, settings: backup.settings, catalog: catalog)
        let logs = Dictionary(uniqueKeysWithValues: raw.map { slice in
            (slice.id, slice.account.monthlyCost > 0
             ? log(slice.account.monthlyCost) + (slice.account.currency == .usd ? log(backup.settings.usdRate) : 0)
             : -Double.infinity)
        })
        logarithms = logs
        slices = raw.sorted {
            if $0.cny.isFinite && $1.cny.isFinite { return $0.cny == $1.cny ? $0.id < $1.id : $0.cny > $1.cny }
            let a = logs[$0.id]!, b = logs[$1.id]!
            return a == b ? $0.id < $1.id : a > b
        }
        let sum = raw.reduce(0) { $0 + $1.cny }
        total = sum.isFinite ? sum : nil
        let largest = logs.values.max() ?? -Double.infinity
        largestLog = largest
        scaledTotal = largest.isFinite ? logs.values.reduce(0) { $0 + exp($1 - largest) } : 0
    }
    var hasSpend: Bool { scaledTotal > 0 }
    func fraction(for slice: SpendSlice) -> Double {
        if let total { return total > 0 ? slice.cny / total : 0 }
        // Normalize before dividing; neither conversion nor aggregation needs to fit in Double.
        return scaledTotal > 0 ? exp(logarithms[slice.id]! - largestLog) / scaledTotal : 0
    }
    func percentage(for slice: SpendSlice) -> Int { Int((fraction(for: slice) * 100).rounded()) }
    func money(for slice: SpendSlice) -> String {
        slice.cny.isFinite ? NativeFormat.money(slice.cny) : "¥" + scientific(logarithms[slice.id]!)
    }
    var totalMoney: String { dailyMoney(days: 1) }
    func dailyMoney(days: Int) -> String {
        let divisor = Double(max(1, days))
        if let total { return NativeFormat.money(total / divisor) }
        return "¥" + scientific(largestLog + log(scaledTotal) - log(divisor))
    }
    var serial: String {
        if let total {
            if total >= 1e15 { return "TKF-" + scientific(log(total)) }
            return "TKF-" + total.rounded().formatted(.number.grouping(.never).precision(.fractionLength(0)).locale(Locale(identifier: "en_US_POSIX")))
        }
        return "TKF-" + scientific(largestLog + log(scaledTotal))
    }
    private func scientific(_ logarithm: Double) -> String {
        let power = logarithm / log(10)
        let exponent = floor(power)
        let mantissa = pow(10, power - exponent)
        return mantissa.formatted(.number.precision(.significantDigits(1...6)).locale(Locale(identifier: "en_US_POSIX")))
            + "e" + exponent.formatted(.number.grouping(.never).precision(.fractionLength(0)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

struct ReportDateContext {
    let date: Date
    let calendar: Calendar
    init(date: Date = Date(), calendar: Calendar = .current) {
        self.date = date
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
    }
    var days: Int { calendar.range(of: .day, in: .month, for: date)?.count ?? 30 }
    var month: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
