import Foundation
import Observation
import CloudKit
import CryptoKit
import Security
import TokenfieldCore

@MainActor @Observable
final class CloudSyncService {
    static let containerIdentifier = "iCloud.space.lysandra.quotakeeper"
    private(set) var headline = "正在检查 iCloud"
    private(set) var detail = "数据会先保存在本机。"
    private(set) var isSyncing = false
    private(set) var lastSynced: Date?
    private(set) var requiresAccountSwitch = false
    private(set) var canRetry = false
    private(set) var archivedBackupURL: URL?
    @ObservationIgnored private weak var store: AppStore?
    @ObservationIgnored private var container: CKContainer?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    @ObservationIgnored private var activeOperation: CKOperation?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var requested = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingAccountID: String?
    private func zoneID(owner: String) -> CKRecordZone.ID {
        // Account-specific zone names add a server-side barrier to account-change
        // races: an old account's pending upload cannot target the new account's zone.
        CKRecordZone.ID(zoneName: "TokenfieldSync-v1-" + owner, ownerName: CKCurrentUserDefaultName)
    }

    func start(store: AppStore) async {
        self.store = store
        guard !started else { return }
        started = true
        guard CloudSigning.isConfigured(container: Self.containerIdentifier) else {
            headline = "iCloud 尚未启用"
            detail = "此安装版本尚未启用 iCloud。你的数据保存在本机，其他功能可正常使用。"
            return
        }
        // CKContainer can raise an Objective-C exception without signed iCloud
        // entitlements. Never create one until the installation passes the gate.
        container = CKContainer(identifier: Self.containerIdentifier)
        canRetry = true
        accountTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { return }
                self.generation += 1
                self.activeOperation?.cancel()
                self.lastSynced = nil
                if let store = self.store { await self.syncNow(store: store) }
            }
        }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, let store = self.store else { return }
                await self.syncNow(store: store)
            }
        }
        await syncNow(store: store)
    }

    func localDataChanged(store: AppStore) async {
        guard started, container != nil else { return }
        await syncNow(store: store)
    }

    func syncNow(store: AppStore) async {
        self.store = store
        guard let container else { return }
        if isSyncing { requested = true; return }
        isSyncing = true
        defer { isSyncing = false; activeOperation = nil }
        repeat {
            requested = false
            let epoch = generation
            do {
                guard store.canSynchronize else { throw CloudIssue.localDataUnreadable }
                let status = try await container.accountStatus()
                guard epoch == generation else { continue }
                guard status == .available else {
                    headline = status == .noAccount ? "请登录 iCloud" : "iCloud 暂不可用"
                    detail = status == .noAccount ? "在系统设置登录 Apple 账号后，会自动继续同步。本机数据已保留。" : "请检查系统的 iCloud 设置，稍后会自动重试。本机数据已保留。"
                    lastSynced = nil
                    break
                }
                let owner = try await accountIdentifier(container)
                guard epoch == generation else { continue }
                if let bound = store.cloudAccountID, bound != owner {
                    pendingAccountID = owner; requiresAccountSwitch = true
                    headline = "iCloud 账号已更换"
                    detail = "自动同步已暂停，避免把原账号的数据传到新账号。你可以保留备份后切换。"
                    lastSynced = nil
                    break
                }
                requiresAccountSwitch = false; pendingAccountID = nil
                try store.bindCloudAccount(owner)
                headline = "正在同步"; detail = "本机保存完成，正在合并其他设备的更改。"
                let database = container.privateCloudDatabase
                let zoneID = zoneID(owner: owner)
                let tokenKey = "tokenfield-cloud-token-" + owner + "-" + store.syncJournalID
                do { _ = try await database.recordZone(for: zoneID) }
                catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                    _ = try await database.save(CKRecordZone(zoneID: zoneID))
                    UserDefaults.standard.removeObject(forKey: tokenKey)
                    UserDefaults.standard.removeObject(forKey: ackKey(owner, store))
                }
                try await assertAccount(container, owner: owner, epoch: epoch)
                let fetched = try await CloudSyncErrors.fetchResettingExpiredToken(token: readToken(tokenKey), reset: {
                    UserDefaults.standard.removeObject(forKey: tokenKey)
                    UserDefaults.standard.removeObject(forKey: ackKey(owner, store))
                }) { token in
                    try await self.fetchChanges(database, zoneID: zoneID, token: token)
                }
                try await assertAccount(container, owner: owner, epoch: epoch)
                let incoming = try fetched.records.map { record -> SyncOperation in
                    guard record.recordType == "TokenfieldOperation", (record["schemaVersion"] as? NSNumber)?.intValue == 1 else { throw CloudIssue.invalidRecord }
                    let data: Data
                    if let inline = record["payload"] as? Data { data = inline }
                    else if let asset = record["payloadAsset"] as? CKAsset, let url = asset.fileURL {
                        data = try Data(contentsOf: url)
                    } else { throw CloudIssue.invalidRecord }
                    let event = try SyncOperation.decode(data)
                    guard record.recordID.recordName == event.id else { throw CloudIssue.invalidRecord }
                    return event
                }
                // Merge into the CURRENT store, never the snapshot from before await.
                try store.mergeCloudOperations(incoming)
                // Persist the cursor only AFTER durable merging. A crash before here
                // simply downloads the same immutable events again.
                if let next = fetched.token { try writeToken(next, key: tokenKey) }
                var acknowledged = Set(UserDefaults.standard.stringArray(forKey: ackKey(owner, store)) ?? [])
                acknowledged.formUnion(incoming.map(\.id))
                UserDefaults.standard.set(Array(acknowledged), forKey: ackKey(owner, store))
                let pending = store.syncOperations.filter { !acknowledged.contains($0.id) }
                for batch in try CloudUploadBatching.batches(pending) {
                    try await assertAccount(container, owner: owner, epoch: epoch)
                    try await CloudUploadBatching.send(batch, didSave: { saved in
                        try await self.assertAccount(container, owner: owner, epoch: epoch)
                        acknowledged.formUnion(saved.map(\.event.id))
                        UserDefaults.standard.set(Array(acknowledged), forKey: self.ackKey(owner, store))
                    }) { items, forceAsset in
                        try await self.assertAccount(container, owner: owner, epoch: epoch)
                        try await self.upload(items, to: database, zoneID: zoneID, forceAsset: forceAsset)
                    }
                }
                // Local mutations during upload are still in the journal; ensure
                // another pass before claiming this device has finished sending.
                if store.syncOperations.contains(where: { !acknowledged.contains($0.id) }) { requested = true }
                if !requested {
                    lastSynced = Date(); headline = "已与 iCloud 同步"
                    detail = "账号、到期事项、使用记录和计算设置会在你的设备间自动同步。"
                }
            } catch {
                lastSynced = nil
                if epoch != generation { requested = true; continue }
                headline = "等待同步"
                if let cloudError = error as? CKError, cloudError.code == .quotaExceeded {
                    detail = "iCloud 空间不足。本机数据已保存，释放空间后可重试。"
                } else {
                    detail = "本机数据已保存。同步暂未完成，联网后会自动重试。"
                    if let issue = error as? CloudIssue { detail = issue.localizedDescription }
                    else if error is SyncError { detail = error.localizedDescription }
                }
                // No tight retry loop on a failed request; the timer, activation,
                // user retry or next local edit resumes without discarding events.
                requested = false
            }
        } while requested && !Task.isCancelled
    }

    func switchToCurrentAccount(store: AppStore) async {
        guard let owner = pendingAccountID, let container, !isSyncing else { return }
        do {
            guard try await accountIdentifier(container) == owner else { throw CloudIssue.accountChanged }
            archivedBackupURL = try store.switchCloudAccount(to: owner)
            requiresAccountSwitch = false; pendingAccountID = nil
            // Start from the beginning for this new local journal.
            UserDefaults.standard.removeObject(forKey: "tokenfield-cloud-token-" + owner + "-" + store.syncJournalID)
            UserDefaults.standard.removeObject(forKey: ackKey(owner, store))
            await syncNow(store: store)
        } catch { headline = "暂时无法切换"; detail = error.localizedDescription }
    }

    private func accountIdentifier(_ container: CKContainer) async throws -> String {
        let id = try await container.userRecordID()
        return SHA256.hash(data: Data(id.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func assertAccount(_ container: CKContainer, owner: String, epoch: Int) async throws {
        guard epoch == generation, try await accountIdentifier(container) == owner else { throw CloudIssue.accountChanged }
    }
    private func ackKey(_ owner: String, _ store: AppStore) -> String {
        "tokenfield-cloud-ack-" + owner + "-" + store.syncJournalID
    }
    private func readToken(_ key: String) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
    private func writeToken(_ token: CKServerChangeToken, key: String) throws {
        UserDefaults.standard.set(try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true), forKey: key)
    }

    private func fetchChanges(_ database: CKDatabase, zoneID: CKRecordZone.ID, token: CKServerChangeToken?) async throws -> CloudChanges {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = token
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: configuration])
        operation.fetchAllChanges = true
        operation.qualityOfService = .utility
        activeOperation = operation
        return try await withCheckedThrowingContinuation { continuation in
            let changes = ChangesBox()
            operation.recordWasChangedBlock = { _, result in changes.add(result) }
            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success(let value): changes.setToken(value.serverChangeToken)
                case .failure(let error): changes.fail(error)
                }
            }
            operation.recordWithIDWasDeletedBlock = { _, _ in
                // This schema uses tombstones, not physical deletion. An unknown
                // physical deletion means the zone changed outside this protocol.
                changes.fail(CloudIssue.remoteDeletion)
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    if let error = changes.error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: CloudChanges(records: changes.records, token: changes.token)) }
                case .failure(let error): continuation.resume(throwing: CloudSyncErrors.fetchFailure(operation: error, zone: changes.error))
                }
            }
            database.add(operation)
        }
    }

    private func upload(_ items: [CloudUploadItem], to database: CKDatabase, zoneID: CKRecordZone.ID, forceAsset: Bool) async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-upload-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let records = try items.map { try $0.record(zoneID: zoneID, temporaryDirectory: temporaryDirectory, forceAsset: forceAsset) }
        // Immutable record IDs make retries idempotent. A response may have been
        // lost after the server committed a previous save of the same event.
        let results = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
        for record in records {
            guard let result = results.saveResults[record.recordID] else { throw CloudIssue.invalidRecord }
            switch result {
            case .success: break
            case .failure(let error):
                if let ck = error as? CKError, ck.code == .serverRecordChanged, let server = ck.serverRecord {
                    if try await Self.matchesImmutableRecord(server: server, local: record, fetch: { try await database.record(for: $0) }) { continue }
                }
                throw error
            }
        }
    }

    static func matchesImmutableRecord(server: CKRecord, local: CKRecord, fetch: (CKRecord.ID) async throws -> CKRecord) async throws -> Bool {
        // Conflict errors carry asset metadata without downloaded file URLs.
        // Fetch the record before comparing; missing asset data is never proof
        // that an immutable event has already been stored successfully.
        let downloaded = server["payloadAsset"] is CKAsset ? try await fetch(local.recordID) : server
        return try payload(of: downloaded) == payload(of: local)
    }

    private static func payload(of record: CKRecord) throws -> SyncOperation {
        if let data = record["payload"] as? Data { return try SyncOperation.decode(data) }
        if let asset = record["payloadAsset"] as? CKAsset, let file = asset.fileURL {
            return try SyncOperation.decode(Data(contentsOf: file))
        }
        throw CloudIssue.invalidRecord
    }
}

private struct CloudChanges { let records: [CKRecord]; let token: CKServerChangeToken? }

/// CloudKit documents per-operation callbacks as serial. The lock additionally
/// protects this accumulator if a future SDK invokes result callbacks elsewhere.
private final class ChangesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecords: [CKRecord] = []
    private var storedToken: CKServerChangeToken?
    private var storedError: Error?
    var records: [CKRecord] { lock.withLock { storedRecords } }
    var token: CKServerChangeToken? { lock.withLock { storedToken } }
    var error: Error? { lock.withLock { storedError } }
    func add(_ result: Result<CKRecord, Error>) {
        lock.withLock {
            switch result {
            case .success(let record): storedRecords.append(record)
            case .failure(let error): storedError = error
            }
        }
    }
    func setToken(_ token: CKServerChangeToken) { lock.withLock { storedToken = token } }
    func fail(_ error: Error) { lock.withLock { storedError = error } }
}

private enum CloudIssue: Error, LocalizedError {
    case invalidRecord, remoteDeletion, localDataUnreadable, accountChanged
    var errorDescription: String? {
        switch self {
        case .invalidRecord: return "iCloud 中有无法识别的数据，已暂停同步。本机数据保持不变。"
        case .remoteDeletion: return "iCloud 同步记录发生了意外变更，已暂停同步。本机数据已保留。"
        case .localDataUnreadable: return "本机数据需要先恢复。请检查备份，恢复后再同步。"
        case .accountChanged: return "iCloud 账号发生变化，正在重新检查。本机数据已保留。"
        }
    }
}

private enum CloudSigning {
    static func isConfigured(container: String) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return false }
        #if targetEnvironment(simulator)
        return false
        #elseif os(macOS)
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let identifiers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
              identifiers.contains(container) else { return false }
        return true
        #else
        // Development installs carry a signed provisioning profile. Read its
        // entitlements through public Foundation APIs; SecTask isn't public on iOS.
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url),
           let start = data.range(of: Data("<?xml".utf8)),
           let end = data.range(of: Data("</plist>".utf8)), start.lowerBound < end.upperBound,
           let profile = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
           let entitlements = profile["Entitlements"] as? [String: Any],
           let identifiers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] {
            return identifiers.contains(container)
        }
        // App Store/TestFlight remove embedded.mobileprovision but provide an
        // Apple receipt. Local simulator/unsigned builds have neither.
        if let receipt = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: receipt.path) { return true }
        return false
        #endif
    }
}
