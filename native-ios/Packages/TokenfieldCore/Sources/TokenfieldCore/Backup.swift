import Foundation

public struct Backup: Codable, Equatable, Sendable {
    public var app: String
    public var version: Int
    public var exportedAt: String
    public var accounts: [Account]
    public var expiries: [Expiry]
    public var usage: [Usage]
    public var settings: AppSettings
    public var statements: [MonthlyStatement]
    public init(app: String = "ai-quota-keeper", version: Int = 2, exportedAt: String = DateCodec.iso(Date()), accounts: [Account] = [], expiries: [Expiry] = [], usage: [Usage] = [], settings: AppSettings = AppSettings(), statements: [MonthlyStatement] = []) {
        self.app = app; self.version = version; self.exportedAt = exportedAt; self.accounts = accounts; self.expiries = expiries; self.usage = usage; self.settings = settings
        self.statements = statements
    }
    private enum CodingKeys: String, CodingKey { case app, version, exportedAt, accounts, expiries, usage, settings, statements }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decode(String.self, forKey: .app)
        version = try c.decode(Int.self, forKey: .version)
        exportedAt = try c.decode(String.self, forKey: .exportedAt)
        accounts = try c.decode([Account].self, forKey: .accounts)
        expiries = try c.decode([Expiry].self, forKey: .expiries)
        if version == 1 && !c.contains(.usage) {
            usage = []
        } else {
            usage = try c.decode([Usage].self, forKey: .usage)
        }
        settings = try c.decode(AppSettings.self, forKey: .settings)
        statements = try c.decodeIfPresent([MonthlyStatement].self, forKey: .statements) ?? []
    }
    public static func decode(_ data: Data) throws -> Backup { try JSONDecoder().decode(Backup.self, from: data).validated() }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(validated())
    }
    public func validated() throws -> Backup {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw BackupError.invalid(message) } }
        func number(_ value: Double, positive: Bool = false) -> Bool { value.isFinite && (positive ? value > 0 : value >= 0) }
        func ids(_ values: [Int]) -> Bool { values.allSatisfy { $0 > 0 } && Set(values).count == values.count }
        try require(app == "ai-quota-keeper", "不是额度终端的备份文件")
        try require(version == 1 || version == 2, "不支持的备份版本")
        try require(DateCodec.date(exportedAt) != nil, "导出时间无效")
        try require(settings.id == "main" && number(settings.usdRate, positive: true) && number(settings.remindHours), "设置金额或提醒时间无效")
        try require(ids(accounts.map(\.id)) && ids(expiries.map(\.id)) && ids(usage.map(\.id)), "记录编号重复或无效")
        try require(Set(statements.map(\.id)).count == statements.count && Set(statements.map(\.month)).count == statements.count,
                    "账本编号或月份重复")
        for statement in statements { _ = try statement.validated() }
        let accountIDs = Set(accounts.map(\.id))
        for account in accounts {
            try require(number(account.monthlyCost) && (account.balance.map { number($0) } ?? true), "账号金额无效")
            try require(account.resetHours.map { number($0, positive: true) } ?? true, "重置间隔无效")
            try require(DateCodec.date(account.createdAt) != nil, "创建时间无效")
            for value in [account.renewAt, account.resetAnchor].compactMap({ $0 }) { try require(DateCodec.date(value) != nil, "账号日期无效") }
        }
        for expiry in expiries {
            try require(DateCodec.date(expiry.expiresAt) != nil, "到期时间无效")
            try require(expiry.accountId.map { accountIDs.contains($0) } ?? true, "到期事项关联账号不存在")
        }
        for entry in usage {
            try require(accountIDs.contains(entry.accountId), "使用记录关联账号不存在")
            try require(entry.count >= 0 && entry.day.count == 10 && DateCodec.date(entry.day) != nil, "使用次数或日期无效")
        }
        return self
    }
    public mutating func saveAccount(_ account: Account) {
        var value = account
        if value.id == 0 { value.id = Self.nextID(accounts.map(\.id)) }
        if let index = accounts.firstIndex(where: { $0.id == value.id }) { accounts[index] = value } else { accounts.append(value) }
    }
    public mutating func deleteAccount(id: Int) {
        accounts.removeAll { $0.id == id }; expiries.removeAll { $0.accountId == id }; usage.removeAll { $0.accountId == id }
    }
    public mutating func saveExpiry(_ expiry: Expiry) {
        var value = expiry
        if value.id == 0 { value.id = Self.nextID(expiries.map(\.id)) }
        if let index = expiries.firstIndex(where: { $0.id == value.id }) { expiries[index] = value } else { expiries.append(value) }
    }
    public mutating func deleteExpiry(id: Int) { expiries.removeAll { $0.id == id } }
    public mutating func logUsage(accountID: Int, intensity: Intensity, now: Date = Date()) {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        let day = DateCodec.day(now)
        if let index = usage.firstIndex(where: { $0.accountId == accountID && $0.day == day && $0.intensity == intensity }) {
            if usage[index].count < Int.max { usage[index].count += 1 }
        } else { usage.append(Usage(id: Self.nextID(usage.map(\.id)), accountId: accountID, day: day, count: 1, intensity: intensity)) }
    }
    private static func nextID(_ ids: [Int]) -> Int {
        let maximum = ids.max() ?? 0
        if maximum < Int.max { return max(1, maximum + 1) }
        let used = Set(ids)
        var candidate = 1
        while used.contains(candidate) { candidate += 1 }
        return candidate
    }
}
public enum BackupError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}
public struct DataRepository: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> Backup {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Backup() }
        return try Backup.decode(Data(contentsOf: fileURL))
    }
    public func save(_ backup: Backup) throws {
        let data = try backup.encoded()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
    public func importData(_ data: Data) throws -> Backup {
        let backup = try Backup.decode(data)
        try save(backup)
        return backup
    }
}
