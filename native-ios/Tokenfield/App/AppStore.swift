import Foundation
import Observation
import TokenfieldCore

@MainActor @Observable
final class AppStore {
    private(set) var backup: Backup
    let pricing: PricingCatalogService
    var catalog: Catalog { pricing.catalog }
    var errorMessage: String?
    private(set) var revision = 0
    private let repository: SyncRepository
    private var document: SyncDocument
    private let deviceID: String
    private let fileURL: URL
    private var readFailed = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        pricing = PricingCatalogService(directory: fileURL.deletingLastPathComponent())
        let defaults = UserDefaults.standard
        let savedWriter = defaults.string(forKey: "tokenfield-sync-device")
        let writer = savedWriter.flatMap { UUID(uuidString: $0)?.uuidString.lowercased() } ?? UUID().uuidString.lowercased()
        defaults.set(writer, forKey: "tokenfield-sync-device")
        deviceID = writer
        repository = SyncRepository(fileURL: fileURL)
        // Valid built-in defaults cannot fail; fall back without changing a damaged file.
        let empty = try! SyncDocument(backup: Backup(), deviceID: writer)
        document = empty
        backup = try! empty.materialized()
        do {
            document = try repository.load(deviceID: writer)
            backup = try document.materialized()
        } catch {
            readFailed = true
            errorMessage = "无法读取本地数据，原文件已保留。请先检查备份或导入有效备份。\n\(error.localizedDescription)"
        }
    }

    var accounts: [Account] { backup.accounts }
    var expiries: [Expiry] { backup.expiries }
    var usage: [Usage] { backup.usage }
    var settings: AppSettings { backup.settings }
    var statements: [MonthlyStatement] { backup.statements }

    @discardableResult func saveAccount(_ account: Account) -> Bool {
        guard account.id == 0 || accounts.contains(where: { $0.id == account.id }) else {
            errorMessage = "这个账号已经被删除，请关闭编辑窗口后重新添加。"; return false
        }
        return transact { $0.saveAccount(account) }
    }
    @discardableResult func deleteAccount(id: Int) -> Bool { transact { $0.deleteAccount(id: id) } }
    @discardableResult func saveExpiry(_ expiry: Expiry) -> Bool {
        guard expiry.id == 0 || expiries.contains(where: { $0.id == expiry.id }) else {
            errorMessage = "这个到期事项已经被删除，请关闭编辑窗口后重新添加。"; return false
        }
        return transact { $0.saveExpiry(expiry) }
    }
    @discardableResult func deleteExpiry(id: Int) -> Bool { transact { $0.deleteExpiry(id: id) } }
    @discardableResult func logUsage(accountID: Int, intensity: Intensity) -> Bool {
        transact { $0.logUsage(accountID: accountID, intensity: intensity) }
    }
    @discardableResult func updateSettings(_ settings: AppSettings) -> Bool { transact { $0.settings = settings } }
    @discardableResult func applyExchangeRate(_ rate: Double) -> Bool {
        guard rate.isFinite, rate > 0 else { return false }
        guard settings.usdRate != rate else { return true }
        var value = settings; value.usdRate = rate
        return updateSettings(value)
    }

    func undoableUsage(accountID: Int) -> Usage? {
        guard let operation = document.latestUndoableUsage(accountID: accountID),
              case .usage(let entry, _) = operation.payload else { return nil }
        return entry
    }
    @discardableResult func undoLastUsage(accountID: Int) -> Bool {
        guard !readFailed, let operation = document.latestUndoableUsage(accountID: accountID) else { return false }
        do {
            var next = document
            try next.undoUsage(operationID: operation.id)
            try commit(next)
            return true
        } catch {
            errorMessage = "撤销失败，原记录已保留。\n\(error.localizedDescription)"
            return false
        }
    }
    @discardableResult func saveStatement(_ statement: MonthlyStatement) -> Bool {
        guard !document.operations.contains(where: { $0.entityKey == "statement-" + statement.id && $0.payload == .deleteStatement }) else {
            errorMessage = "这份账本已被删除，请关闭窗口后重新补录。"; return false
        }
        return transact { backup in
            var value = statement
            if let index = backup.statements.firstIndex(where: { $0.month == value.month }) {
                value.id = backup.statements[index].id
                backup.statements[index] = value
            } else { backup.statements.append(value) }
        }
    }
    @discardableResult func deleteStatement(id: String) -> Bool {
        transact { $0.statements.removeAll { $0.id == id } }
    }

    @discardableResult func importData(_ data: Data) -> Bool {
        do {
            let imported = try Backup.decode(data)
            var next = readFailed ? try SyncDocument(backup: Backup(), deviceID: deviceID) : document
            try next.replace(with: imported)
            try commit(next)
            readFailed = false
            return true
        } catch {
            errorMessage = "导入失败，现有数据未变更。\n\(error.localizedDescription)"
            return false
        }
    }

    var cloudAccountID: String? { document.cloudAccountID }
    var syncDeviceID: String { deviceID }
    var syncJournalID: String { document.journalID }
    var canSynchronize: Bool { !readFailed }
    var syncOperations: [SyncOperation] { document.operations }

    func bindCloudAccount(_ accountID: String) throws {
        guard !readFailed else { throw StoreIssue.unreadable }
        if document.cloudAccountID == accountID { return }
        var next = document
        try next.bindCloudAccount(accountID)
        try commit(next)
    }

    func mergeCloudOperations(_ operations: [SyncOperation]) throws {
        guard !readFailed else { throw StoreIssue.unreadable }
        var next = document
        try next.merge(operations)
        if next != document { try commit(next) }
    }

    /// The previous account gets a recoverable local backup before switching.
    func switchCloudAccount(to accountID: String) throws -> URL {
        guard !readFailed else { throw StoreIssue.unreadable }
        let archive = fileURL.deletingLastPathComponent()
            .appendingPathComponent("切换前备份-\(UUID().uuidString.prefix(8)).json")
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        try exportData().write(to: archive, options: .atomic)
        var next = try SyncDocument(backup: Backup(), deviceID: deviceID)
        try next.bindCloudAccount(accountID)
        try commit(next)
        return archive
    }

    private func commit(_ next: SyncDocument) throws {
        let value = try next.materialized()
        try repository.save(next)
        document = next
        backup = value
        revision += 1
    }

    func exportData() throws -> Data {
        guard !readFailed else { throw StoreIssue.unreadable }
        var exported = backup
        exported.exportedAt = DateCodec.iso(Date())
        return try exported.encoded()
    }

    private func transact(_ change: (inout Backup) -> Void) -> Bool {
        guard !readFailed else {
            errorMessage = "本地数据读取失败，已暂停写入以保留原文件。请导入有效备份后继续。"
            return false
        }
        var next = backup
        change(&next)
        do {
            var updated = document
            try updated.recordChange(from: backup, to: next)
            try commit(updated)
            return true
        } catch {
            errorMessage = "保存失败，请检查输入或可用存储空间。\n\(error.localizedDescription)"
            return false
        }
    }
}

private enum StoreIssue: LocalizedError {
    case unreadable
    var errorDescription: String? { "本地数据未能读取，无法生成备份。原文件已保留，请先恢复有效备份。" }
}
