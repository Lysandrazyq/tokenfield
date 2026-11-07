import Foundation
import CryptoKit

/// Immutable events are the synchronization unit. Retransmission and arbitrary
/// download ordering are safe; a failed upload never removes an event locally.
public struct SyncOperation: Codable, Equatable, Sendable, Identifiable {
    public enum Payload: Codable, Equatable, Sendable {
        case account(Account)
        case deleteAccount
        case expiry(Expiry, accountKey: String?)
        case deleteExpiry
        case usage(Usage, accountKey: String)
        case undoUsage(operationID: String)
        case statement(MonthlyStatement)
        case deleteStatement
        case settings(AppSettings)
    }
    public let id: String
    public let entityKey: String
    public let counter: UInt64
    public let actor: String
    public let payload: Payload

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    func validate() throws {
        guard !id.isEmpty, id.count <= 200, !entityKey.isEmpty, entityKey.count <= 200,
              !actor.isEmpty, actor.count <= 200, counter < UInt64.max else { throw SyncError.invalid }
        var backup = Backup(exportedAt: SyncDocument.epoch)
        switch payload {
        case .account(var account):
            guard entityKey.hasPrefix("account-") else { throw SyncError.invalid }
            account.id = 1; backup.accounts = [account]
        case .expiry(var expiry, let parent):
            guard entityKey.hasPrefix("expiry-"), parent.map({ $0.hasPrefix("account-") }) ?? true else { throw SyncError.invalid }
            expiry.id = 1; expiry.accountId = nil; backup.expiries = [expiry]
        case .usage(var entry, let accountKey):
            guard entityKey.hasPrefix("usage-"), accountKey.hasPrefix("account-") else { throw SyncError.invalid }
            entry.id = 1; entry.accountId = 1
            backup.accounts = [Account(id: 1, createdAt: SyncDocument.epoch)]; backup.usage = [entry]
        case .settings(let settings):
            guard entityKey == "settings" else { throw SyncError.invalid }; backup.settings = settings
        case .undoUsage(let operationID):
            guard UUID(uuidString: operationID) != nil, entityKey == "undo-" + operationID else { throw SyncError.invalid }
        case .statement(let statement):
            guard entityKey == "statement-" + statement.id else { throw SyncError.invalid }
            _ = try statement.validated()
        case .deleteStatement:
            guard entityKey.hasPrefix("statement-"), UUID(uuidString: String(entityKey.dropFirst(10))) != nil else { throw SyncError.invalid }
        case .deleteAccount: guard entityKey.hasPrefix("account-") else { throw SyncError.invalid }
        case .deleteExpiry: guard entityKey.hasPrefix("expiry-") else { throw SyncError.invalid }
        }
        _ = try backup.validated()
    }
}

public enum SyncError: Error, LocalizedError {
    case invalid, conflictingOperation, identifierCollision, clockExhausted
    public var errorDescription: String? {
        switch self {
        case .invalid: return "同步记录格式无效，现有数据已保留。"
        case .conflictingOperation: return "同步记录编号冲突，现有数据已保留。"
        case .identifierCollision: return "同步记录标识冲突，现有数据已保留。"
        case .clockExhausted: return "同步版本超出范围，现有数据已保留。"
        }
    }
}

public struct SyncDocument: Codable, Equatable, Sendable {
    static let epoch = "1970-01-01T00:00:00.000Z"
    public private(set) var deviceID: String
    public private(set) var journalID: String
    public private(set) var cloudAccountID: String?
    private var events: [String: SyncOperation] = [:]
    public var operations: [SyncOperation] { events.values.sorted { $0.id < $1.id } }
    public var operationIDs: Set<String> { Set(events.keys) }

    private var cancelledUsageIDs: Set<String> {
        Set(events.values.compactMap { cancellation in
            guard case .undoUsage(let targetID) = cancellation.payload,
                  let target = events[targetID], target.actor == cancellation.actor,
                  target.entityKey.hasPrefix("usage-tap-"), target.actor != "seed", case .usage(let entry, _) = target.payload,
                  entry.count == 1 else { return nil }
            return targetID
        })
    }

    public func latestUndoableUsage(accountID: Int) -> SyncOperation? {
        guard let parent = key(for: accountID, prefix: "account-"),
              !events.values.contains(where: { $0.entityKey == parent && $0.payload == .deleteAccount }) else { return nil }
        let cancelled = cancelledUsageIDs
        return events.values.filter { event in
            guard event.actor == deviceID, event.actor != "seed", event.entityKey.hasPrefix("usage-tap-"), !cancelled.contains(event.id),
                  case .usage(let entry, let accountKey) = event.payload else { return false }
            return accountKey == parent && entry.count == 1
        }.max { $0.counter == $1.counter ? $0.id < $1.id : $0.counter < $1.counter }
    }

    public mutating func undoUsage(operationID: String) throws {
        guard let target = events[operationID], target.actor == deviceID, target.actor != "seed", target.entityKey.hasPrefix("usage-tap-"),
              case .usage(let entry, let parent) = target.payload, entry.count == 1,
              !events.values.contains(where: { $0.entityKey == parent && $0.payload == .deleteAccount }) else { throw SyncError.invalid }
        if cancelledUsageIDs.contains(operationID) { return }
        try append(key: "undo-" + operationID, payload: .undoUsage(operationID: operationID))
    }

    public init(backup: Backup, deviceID: String) throws {
        _ = try backup.validated()
        self.deviceID = deviceID
        journalID = UUID().uuidString.lowercased()
        guard !deviceID.isEmpty, deviceID.count <= 200 else { throw SyncError.invalid }
        try seed(backup, deterministic: true)
    }

    /// Keep this installation's writer identity after copying cloud operations.
    public mutating func setDeviceID(_ value: String) { deviceID = value }
    mutating func restoreJournalID(_ value: String) throws {
        guard UUID(uuidString: value) != nil else { throw SyncError.invalid }
        journalID = value
    }

    /// Ownership persists beside the journal so signing into another Apple
    /// account cannot implicitly publish the previous account's private data.
    public mutating func bindCloudAccount(_ accountID: String) throws {
        guard !accountID.isEmpty, cloudAccountID == nil || cloudAccountID == accountID else { throw SyncError.invalid }
        cloudAccountID = accountID
    }

    public mutating func merge(_ incoming: [SyncOperation]) throws {
        var next = self
        for event in incoming {
            try event.validate()
            if let existing = next.events[event.id], existing != event { throw SyncError.conflictingOperation }
            next.events[event.id] = event
        }
        _ = try next.materialized()
        self = next
    }

    private mutating func append(key: String, payload: SyncOperation.Payload, seedID: String? = nil) throws {
        let clock = events.values.map(\.counter).max() ?? 0
        guard seedID != nil || clock < UInt64.max - 1 else { throw SyncError.clockExhausted }
        let event = SyncOperation(id: seedID ?? UUID().uuidString.lowercased(), entityKey: key,
                                  counter: seedID == nil ? clock + 1 : 0,
                                  actor: seedID == nil ? deviceID : "seed", payload: payload)
        try event.validate()
        events[event.id] = event
    }

    private static func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
    private static func number(_ key: String) -> Int {
        // 48 bits remain exactly representable in the website's JavaScript JSON.
        let hash = SHA256.hash(data: Data(key.utf8))
        return Int(hash.prefix(6).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }) + 1
    }
    private func key(for id: Int, prefix: String) -> String? {
        events.values.map(\.entityKey).first { $0.hasPrefix(prefix) && Self.number($0) == id }
    }

    private mutating func seed(_ backup: Backup, deterministic: Bool) throws {
        var accountKeys: [Int: String] = [:]
        for account in backup.accounts {
            let key = "account-" + (deterministic ? try Self.digest(account) : UUID().uuidString.lowercased())
            accountKeys[account.id] = key
            try append(key: key, payload: .account(account), seedID: deterministic ? key : nil)
        }
        for expiry in backup.expiries {
            let key = "expiry-" + (deterministic ? try Self.digest(expiry) + "-" + String((accountKeys[expiry.accountId ?? 0] ?? "").suffix(20)) : UUID().uuidString.lowercased())
            try append(key: key, payload: .expiry(expiry, accountKey: expiry.accountId.flatMap { accountKeys[$0] }), seedID: deterministic ? key : nil)
        }
        for usage in backup.usage {
            guard let parent = accountKeys[usage.accountId] else { throw SyncError.invalid }
            let key = "usage-" + (deterministic ? try Self.digest(usage) + "-" + String(parent.suffix(20)) : UUID().uuidString.lowercased())
            try append(key: key, payload: .usage(usage, accountKey: parent), seedID: deterministic ? key : nil)
        }
        for statement in backup.statements {
            let key = "statement-" + statement.id
            let seedID = deterministic ? "statement-seed-" + (try Self.digest(statement)) : nil
            try append(key: key, payload: .statement(statement), seedID: seedID)
        }
        if backup.settings != AppSettings() || !deterministic {
            let seedID = deterministic ? "settings-" + (try Self.digest(backup.settings)) : nil
            try append(key: "settings", payload: .settings(backup.settings), seedID: seedID)
        }
    }

    public mutating func recordChange(from before: Backup, to after: Backup) throws {
        _ = try after.validated()
        var next = self
        var keys: [Int: String] = [:]
        for account in before.accounts {
            guard let key = next.key(for: account.id, prefix: "account-") else { throw SyncError.invalid }
            keys[account.id] = key
            if !after.accounts.contains(where: { $0.id == account.id }) { try next.append(key: key, payload: .deleteAccount) }
        }
        for account in after.accounts {
            let old = before.accounts.first { $0.id == account.id }
            let key = keys[account.id] ?? "account-" + UUID().uuidString.lowercased()
            keys[account.id] = key
            if old != account { try next.append(key: key, payload: .account(account)) }
        }
        for expiry in before.expiries where !after.expiries.contains(where: { $0.id == expiry.id }) {
            guard let key = next.key(for: expiry.id, prefix: "expiry-") else { throw SyncError.invalid }
            try next.append(key: key, payload: .deleteExpiry)
        }
        for expiry in after.expiries where before.expiries.first(where: { $0.id == expiry.id }) != expiry {
            let old = before.expiries.contains { $0.id == expiry.id }
            let key = (old ? next.key(for: expiry.id, prefix: "expiry-") : nil) ?? "expiry-" + UUID().uuidString.lowercased()
            try next.append(key: key, payload: .expiry(expiry, accountKey: expiry.accountId.flatMap { keys[$0] }))
        }
        for usage in after.usage {
            let old = before.usage.first { $0.id == usage.id }
            let delta = usage.count - (old?.count ?? 0)
            if delta > 0 {
                guard let parent = keys[usage.accountId] else { throw SyncError.invalid }
                var increment = usage; increment.count = delta
                let prefix = delta == 1 ? "usage-tap-" : "usage-"
                try next.append(key: prefix + UUID().uuidString.lowercased(), payload: .usage(increment, accountKey: parent))
            }
        }
        for statement in before.statements where !after.statements.contains(where: { $0.id == statement.id }) {
            let keys = Set(next.events.values.compactMap { event -> String? in
                if case .statement(let saved) = event.payload, saved.month == statement.month { return event.entityKey }
                return nil
            })
            for key in keys { try next.append(key: key, payload: .deleteStatement) }
        }
        for statement in after.statements where before.statements.first(where: { $0.id == statement.id }) != statement {
            try next.append(key: "statement-" + statement.id, payload: .statement(statement))
        }
        if before.settings != after.settings { try next.append(key: "settings", payload: .settings(after.settings)) }
        _ = try next.materialized()
        self = next
    }

    public mutating func replace(with backup: Backup) throws {
        _ = try backup.validated()
        var next = self
        let current = try materialized()
        for account in current.accounts {
            guard let key = next.key(for: account.id, prefix: "account-") else { throw SyncError.invalid }
            try next.append(key: key, payload: .deleteAccount)
        }
        for expiry in current.expiries {
            guard let key = next.key(for: expiry.id, prefix: "expiry-") else { throw SyncError.invalid }
            try next.append(key: key, payload: .deleteExpiry)
        }
        for event in next.events.values {
            if case .statement = event.payload { try next.append(key: event.entityKey, payload: .deleteStatement) }
        }
        var imported = backup
        // Imported snapshots start new entities, just like imported accounts.
        imported.statements = backup.statements.map { statement in
            var copy = statement; copy.id = UUID().uuidString.lowercased(); return copy
        }
        try next.seed(imported, deterministic: false)
        self = next
    }

    public func materialized() throws -> Backup {
        var deletedAccounts = Set<String>(), deletedExpiries = Set<String>(), deletedStatements = Set<String>()
        var latest: [String: SyncOperation] = [:]
        func less(_ a: SyncOperation, _ b: SyncOperation) -> Bool {
            if a.counter != b.counter { return a.counter < b.counter }
            if a.actor != b.actor { return a.actor < b.actor }
            return a.id < b.id
        }
        for event in events.values {
            switch event.payload {
            case .deleteAccount: deletedAccounts.insert(event.entityKey)
            case .deleteExpiry: deletedExpiries.insert(event.entityKey)
            case .deleteStatement: deletedStatements.insert(event.entityKey)
            case .usage, .undoUsage: continue
            default:
                if latest[event.entityKey].map({ less($0, event) }) ?? true { latest[event.entityKey] = event }
            }
        }
        var backup = Backup(exportedAt: Self.epoch)
        var statementsByMonth: [String: SyncOperation] = [:]
        for event in latest.values {
            if case .statement(let statement) = event.payload, !deletedStatements.contains(event.entityKey),
               statementsByMonth[statement.month].map({ less($0, event) }) ?? true {
                statementsByMonth[statement.month] = event
            }
        }
        backup.statements = statementsByMonth.values.compactMap { event in
            if case .statement(let statement) = event.payload { return statement }; return nil
        }.sorted { $0.month > $1.month }
        var accountIDs: [String: Int] = [:]
        for event in latest.values {
            if case .account(var account) = event.payload, !deletedAccounts.contains(event.entityKey) {
                account.id = Self.number(event.entityKey); accountIDs[event.entityKey] = account.id
                backup.accounts.append(account)
            }
            if case .settings(let settings) = event.payload { backup.settings = settings }
        }
        for event in latest.values {
            if case .expiry(var expiry, let parent) = event.payload, !deletedExpiries.contains(event.entityKey) {
                if let parent, accountIDs[parent] == nil { continue }
                expiry.id = Self.number(event.entityKey); expiry.accountId = parent.flatMap { accountIDs[$0] }
                backup.expiries.append(expiry)
            }
        }
        var usageGroups: [String: Usage] = [:]
        var legacyBaselines: [String: Int] = [:]
        // Migrating two snapshots of an existing website counter must not add
        // that shared history twice. Each legacy row is a max-register baseline;
        // subsequent native usage events remain independent additive increments.
        for event in events.values {
            guard event.actor == "seed", case .usage(let entry, let parent) = event.payload else { continue }
            let row = parent + "|" + entry.day + "|" + entry.intensity.rawValue + "|" + String(entry.id)
            legacyBaselines[row] = max(legacyBaselines[row] ?? 0, entry.count)
        }
        var countedBaselines = Set<String>()
        let cancelled = cancelledUsageIDs
        for event in events.values {
            guard !cancelled.contains(event.id), case .usage(let entry, let parent) = event.payload, let accountID = accountIDs[parent] else { continue }
            let group = parent + "|" + entry.day + "|" + entry.intensity.rawValue
            var total = usageGroups[group] ?? Usage(id: Self.number("total-" + group), accountId: accountID,
                                                   day: entry.day, count: 0, intensity: entry.intensity)
            var increment = entry.count
            if event.actor == "seed" {
                let row = parent + "|" + entry.day + "|" + entry.intensity.rawValue + "|" + String(entry.id)
                increment = countedBaselines.insert(row).inserted ? (legacyBaselines[row] ?? 0) : 0
            }
            let sum = total.count.addingReportingOverflow(increment)
            total.count = sum.overflow ? Int.max : sum.partialValue
            if entry.hitLimit == true { total.hitLimit = true }
            else if entry.hitLimit == false, total.hitLimit == nil { total.hitLimit = false }
            usageGroups[group] = total
        }
        backup.usage = Array(usageGroups.values)
        backup.accounts.sort { $0.id < $1.id }; backup.expiries.sort { $0.id < $1.id }; backup.usage.sort { $0.id < $1.id }
        // Cryptographic ID collisions fail safely rather than connecting the wrong account.
        guard Set(backup.accounts.map(\.id)).count == backup.accounts.count,
              Set(backup.expiries.map(\.id)).count == backup.expiries.count,
              Set(backup.usage.map(\.id)).count == backup.usage.count else { throw SyncError.identifierCollision }
        return try backup.validated()
    }
}
