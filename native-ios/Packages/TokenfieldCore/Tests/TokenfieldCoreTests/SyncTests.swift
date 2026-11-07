import XCTest
@testable import TokenfieldCore

final class SyncTests: XCTestCase {
    private let now = "2026-10-31T12:00:00.000Z"
    private func oldBackup(_ name: String = "Existing") -> Backup {
        Backup(accounts: [Account(id: 1, name: name, createdAt: now)],
               expiries: [Expiry(id: 1, title: "Expiry", accountId: 1, expiresAt: now)],
               usage: [Usage(id: 1, accountId: 1, day: "2026-10-31", count: 3, intensity: .code)])
    }

    func testLegacyMigrationKeepsAssociationsAndBackupCompatibility() throws {
        let state = try SyncDocument(backup: oldBackup(), deviceID: "A")
        let value = try state.materialized()
        XCTAssertEqual(value.accounts.first?.name, "Existing")
        XCTAssertEqual(value.expiries.first?.accountId, value.accounts.first?.id)
        XCTAssertEqual(value.usage.first?.accountId, value.accounts.first?.id)
        XCTAssertEqual(value.usage.first?.count, 3)
        XCTAssertNoThrow(try Backup.decode(value.encoded()))
    }

    func testIndependentLegacyIDsNeverOverwriteOtherDeviceAccount() throws {
        var a = try SyncDocument(backup: oldBackup("Phone"), deviceID: "A")
        let b = try SyncDocument(backup: oldBackup("Mac"), deviceID: "B")
        try a.merge(b.operations)
        let value = try a.materialized()
        XCTAssertEqual(Set(value.accounts.map(\.name)), ["Phone", "Mac"])
        XCTAssertEqual(value.expiries.count, 2)
        XCTAssertEqual(Set(value.expiries.compactMap(\.accountId)), Set(value.accounts.map(\.id)))
    }

    func testConcurrentUsageIsAdditiveAndMergingIsIdempotentCommutative() throws {
        var a = try SyncDocument(backup: oldBackup(), deviceID: "A")
        var b = try SyncDocument(backup: oldBackup(), deviceID: "B")
        let original = try a.materialized()
        var one = original
        one.usage[0].count += 1
        try a.recordChange(from: original, to: one)
        var two = original
        two.usage[0].count += 2
        try b.recordChange(from: original, to: two)
        let aOps = a.operations
        try a.merge(b.operations)
        try b.merge(aOps)
        XCTAssertEqual(try a.materialized().usage.first?.count, 6)
        XCTAssertEqual(try a.materialized(), try b.materialized())
        let count = a.operations.count
        try a.merge(b.operations)
        XCTAssertEqual(a.operations.count, count)
        XCTAssertEqual(try a.materialized().usage.first?.count, 6)
    }

    func testDeletionWinsOverOfflineEditAndHidesDependentRecords() throws {
        var a = try SyncDocument(backup: oldBackup(), deviceID: "A")
        var b = try SyncDocument(backup: oldBackup(), deviceID: "B")
        let original = try a.materialized()
        var deleted = original
        deleted.deleteAccount(id: original.accounts[0].id)
        try a.recordChange(from: original, to: deleted)
        var edited = original
        edited.accounts[0].name = "Edited while offline"
        edited.usage[0].count += 1
        try b.recordChange(from: original, to: edited)
        try a.merge(b.operations)
        let value = try a.materialized()
        XCTAssertTrue(value.accounts.isEmpty)
        XCTAssertTrue(value.expiries.isEmpty)
        XCTAssertTrue(value.usage.isEmpty)
    }

    func testConcurrentNewAccountsKeepStableIDsAndReferences() throws {
        var a = try SyncDocument(backup: Backup(), deviceID: "A")
        var b = try SyncDocument(backup: Backup(), deviceID: "B")
        let empty = try a.materialized()
        var phone = empty; phone.saveAccount(Account(name: "Phone", createdAt: now))
        var mac = empty; mac.saveAccount(Account(name: "Mac", createdAt: now))
        try a.recordChange(from: empty, to: phone)
        try b.recordChange(from: empty, to: mac)
        let phoneID = try XCTUnwrap(a.materialized().accounts.first?.id)
        try a.merge(b.operations)
        XCTAssertEqual(try a.materialized().accounts.first(where: { $0.name == "Phone" })?.id, phoneID)
        XCTAssertEqual(try a.materialized().accounts.count, 2)
    }

    func testDurableArchiveContainsPendingOperationsAndRemainsReadableByOldRepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let repository = SyncRepository(fileURL: file)
        let state = try SyncDocument(backup: oldBackup(), deviceID: "A")
        try repository.save(state)
        let reloaded = try repository.load(deviceID: "A")
        XCTAssertEqual(Set(reloaded.operations.map(\.id)), Set(state.operations.map(\.id)))
        XCTAssertEqual(try DataRepository(fileURL: file).load(), try state.materialized())
        let export = try state.materialized().encoded()
        XCTAssertNil((try JSONSerialization.jsonObject(with: export) as? [String: Any])?["_sync"])
    }

    func testImportReplacementDeletesKnownOldRecordsAndDoesNotResurrectOnMerge() throws {
        var a = try SyncDocument(backup: oldBackup(), deviceID: "A")
        let stale = a.operations
        try a.replace(with: oldBackup("Imported"))
        try a.merge(stale)
        let value = try a.materialized()
        XCTAssertEqual(value.accounts.map(\.name), ["Imported"])
        XCTAssertEqual(value.usage.first?.count, 3)
        XCTAssertEqual(value.expiries.first?.accountId, value.accounts.first?.id)
    }

    func testLocalChangeAfterSnapshotRemainsWhenRemoteOperationsArrive() throws {
        var a = try SyncDocument(backup: oldBackup(), deviceID: "A")
        var b = try SyncDocument(backup: oldBackup(), deviceID: "B")
        let snapshot = a.operations
        let before = try a.materialized()
        var after = before; after.accounts[0].note = "Saved during upload"
        try a.recordChange(from: before, to: after)
        var remote = try b.materialized(); remote.settings.handle = "remote"
        try b.recordChange(from: b.materialized(), to: remote)
        try a.merge(b.operations)
        XCTAssertEqual(try a.materialized().accounts.first?.note, "Saved during upload")
        XCTAssertEqual(try a.materialized().settings.handle, "remote")
        XCTAssertGreaterThan(a.operations.count, snapshot.count)
    }

    func testCloudAccountBindingSurvivesRestartAndRejectsDifferentAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SyncRepository(fileURL: directory.appendingPathComponent("data.json"))
        var state = try SyncDocument(backup: oldBackup(), deviceID: "A")
        try state.bindCloudAccount("account-A")
        try repository.save(state)
        var reloaded = try repository.load(deviceID: "B")
        XCTAssertEqual(reloaded.cloudAccountID, "account-A")
        XCTAssertEqual(reloaded.deviceID, "B")
        XCTAssertThrowsError(try reloaded.bindCloudAccount("account-B"))
        XCTAssertEqual(reloaded.cloudAccountID, "account-A")
        XCTAssertEqual(try reloaded.materialized().accounts.count, 1)
    }

    func testExplicitFalseHitLimitSurvivesMigrationExportAndMerge() throws {
        var backup = oldBackup()
        backup.usage[0].hitLimit = false
        let state = try SyncDocument(backup: backup, deviceID: "A")
        XCTAssertEqual(try state.materialized().usage.first?.hitLimit, false)
        XCTAssertEqual(try Backup.decode(state.materialized().encoded()).usage.first?.hitLimit, false)
    }

    func testDifferentLegacySnapshotsDoNotCountTheSameUsageBaselineTwice() throws {
        var older = oldBackup(), newer = oldBackup()
        older.usage[0].count = 3; newer.usage[0].count = 5
        var a = try SyncDocument(backup: older, deviceID: "A")
        let b = try SyncDocument(backup: newer, deviceID: "B")
        try a.merge(b.operations)
        XCTAssertEqual(try a.materialized().usage.first?.count, 5)
    }
}
