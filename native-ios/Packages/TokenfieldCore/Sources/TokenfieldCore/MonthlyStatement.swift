import Foundation

public enum StatementMonth {
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        String(DateCodec.day(date, calendar: calendar).prefix(7))
    }
    public static func date(_ month: String) -> Date? {
        guard month.range(of: #"^[0-9]{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil,
              Int(month.prefix(4)).map({ $0 > 0 }) == true else { return nil }
        // Mid-month is stable when rendered in every supported time zone.
        return DateCodec.date(month + "-15T12:00:00Z")
    }
}

public struct MonthlyStatement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var month: String
    public var capturedAt: String
    public var accounts: [Account]
    public var settings: AppSettings

    public init(id: String = UUID().uuidString.lowercased(), month: String,
                capturedAt: String = DateCodec.iso(Date()), accounts: [Account], settings: AppSettings) {
        self.id = id; self.month = month; self.capturedAt = capturedAt
        self.accounts = accounts; self.settings = settings
    }
    public var reportBackup: Backup { Backup(accounts: accounts, settings: settings) }

    public func validated() throws -> Self {
        guard UUID(uuidString: id) != nil, StatementMonth.date(month) != nil,
              DateCodec.date(capturedAt) != nil else { throw BackupError.invalid("月度账本的月份或日期无效") }
        _ = try reportBackup.validated()
        return self
    }
}
