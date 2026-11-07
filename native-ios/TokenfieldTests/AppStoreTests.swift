import XCTest
import TokenfieldCore
@testable import Tokenfield

final class AppStoreTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("data.json")
    }

    @MainActor func testSaveAndReloadPublishOnlyPersistedData() throws {
        let file = try temporaryFile()
        let store = AppStore(fileURL: file)
        var account = Account.blank()
        account.name = "Persisted account"
        XCTAssertTrue(store.saveAccount(account))
        XCTAssertEqual(store.revision, 1)
        XCTAssertGreaterThan(store.accounts[0].id, 0)
        XCTAssertTrue(store.logUsage(accountID: store.accounts[0].id, intensity: .code))
        let reloaded = AppStore(fileURL: file)
        XCTAssertEqual(reloaded.backup, store.backup)
        XCTAssertEqual(reloaded.usage.first?.count, 1)
    }

    @MainActor func testFailedWriteDoesNotPublishOrIncrementRevision() throws {
        let file = try temporaryFile()
        let store = AppStore(fileURL: file)
        // A directory at the destination deterministically makes atomic replacement fail.
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertFalse(store.saveAccount(Account.blank()))
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertEqual(store.revision, 0)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue((try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true)
    }

    @MainActor func testCorruptStartupFileStaysIntactUntilValidImport() throws {
        let file = try temporaryFile()
        let damaged = Data("{unfinished".utf8)
        try damaged.write(to: file)
        let store = AppStore(fileURL: file)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.saveAccount(Account.blank()))
        XCTAssertThrowsError(try store.exportData(), "Unreadable data must not export an empty fallback as a valid backup")
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        XCTAssertFalse(store.importData(Data("{}".utf8)))
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        var valid = Backup()
        valid.saveAccount(Account.blank())
        XCTAssertTrue(store.importData(try valid.encoded()))
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertTrue(store.logUsage(accountID: store.accounts[0].id, intensity: .chat))
        XCTAssertEqual(AppStore(fileURL: file).usage.count, 1)
    }

    @MainActor func testInvalidSettingsLeaveMemoryAndFileUnchanged() throws {
        let file = try temporaryFile()
        let store = AppStore(fileURL: file)
        XCTAssertTrue(store.saveAccount(Account.blank()))
        let before = try Data(contentsOf: file)
        let revision = store.revision
        var invalid = store.settings
        invalid.usdRate = -1
        XCTAssertFalse(store.updateSettings(invalid))
        XCTAssertEqual(store.settings.usdRate, 7.1)
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
}
