import XCTest
import TokenfieldCore
@testable import Tokenfield

final class SyncStoreTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("data.json")
    }

    @MainActor func testRemoteMergeKeepsEditsMadeAfterUploadSnapshotAndReloads() throws {
        let file = try temporaryFile()
        let store = AppStore(fileURL: file)
        XCTAssertTrue(store.saveAccount(Account(name: "Phone")))
        let snapshot = store.syncOperations
        var remote = try SyncDocument(backup: Backup(), deviceID: "remote")
        try remote.merge(snapshot)
        let before = try remote.materialized()
        var after = before; after.settings.handle = "Mac"
        try remote.recordChange(from: before, to: after)
        var edited = store.accounts[0]; edited.note = "Written during upload"
        XCTAssertTrue(store.saveAccount(edited))
        try store.mergeCloudOperations(remote.operations)
        XCTAssertEqual(store.accounts[0].note, "Written during upload")
        XCTAssertEqual(store.settings.handle, "Mac")
        XCTAssertEqual(AppStore(fileURL: file).backup, store.backup)
    }

    @MainActor func testAccountSwitchPreservesReadableBackupAndBindsFreshJournal() throws {
        let file = try temporaryFile()
        let store = AppStore(fileURL: file)
        XCTAssertTrue(store.saveAccount(Account(name: "Original cloud")))
        try store.bindCloudAccount("A")
        let originalJournal = store.syncJournalID
        XCTAssertThrowsError(try store.bindCloudAccount("B"))
        XCTAssertEqual(store.cloudAccountID, "A")
        let archive = try store.switchCloudAccount(to: "B")
        XCTAssertEqual(try Backup.decode(Data(contentsOf: archive)).accounts.first?.name, "Original cloud")
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertEqual(store.cloudAccountID, "B")
        XCTAssertNotEqual(store.syncJournalID, originalJournal)
        let reloaded = AppStore(fileURL: file)
        XCTAssertEqual(reloaded.cloudAccountID, "B")
        XCTAssertEqual(reloaded.syncJournalID, store.syncJournalID)
        XCTAssertTrue(reloaded.accounts.isEmpty)
    }

    @MainActor func testDeletedRemoteAccountCannotBeRecreatedByStaleEditorSave() throws {
        let store = AppStore(fileURL: try temporaryFile())
        XCTAssertTrue(store.saveAccount(Account(name: "Deleted")))
        var stale = store.accounts[0]
        var remote = try SyncDocument(backup: Backup(), deviceID: "remote")
        try remote.merge(store.syncOperations)
        let before = try remote.materialized()
        var after = before; after.deleteAccount(id: stale.id)
        try remote.recordChange(from: before, to: after)
        try store.mergeCloudOperations(remote.operations)
        stale.name = "Stale editor"
        XCTAssertFalse(store.saveAccount(stale))
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor func testImportPropagatesReplacementAndExportOmitsPrivateJournal() throws {
        let store = AppStore(fileURL: try temporaryFile())
        XCTAssertTrue(store.saveAccount(Account(name: "Old")))
        var remote = try SyncDocument(backup: Backup(), deviceID: "remote")
        try remote.merge(store.syncOperations)
        var imported = Backup(); imported.saveAccount(Account(name: "Imported"))
        XCTAssertTrue(store.importData(try imported.encoded()))
        try remote.merge(store.syncOperations)
        XCTAssertEqual(try remote.materialized().accounts.map(\.name), ["Imported"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any])
        XCTAssertNil(json["_sync"])
        XCTAssertEqual(json["version"] as? Int, 2)
    }
}
