import XCTest
import TokenfieldCore
@testable import Tokenfield

final class NativeFeatureStoreTests: XCTestCase {
    @MainActor func testExchangeRateUpdatePreservesOtherSettingsAndSavedStatements() throws {
        let store = AppStore(fileURL: try file())
        var settings = store.settings
        settings.handle = "Fixture"; settings.remindHours = 12
        XCTAssertTrue(store.updateSettings(settings))
        let statement = MonthlyStatement(month: "2026-10", accounts: store.accounts, settings: store.settings)
        XCTAssertTrue(store.saveStatement(statement))
        XCTAssertTrue(store.applyExchangeRate(6.6713))
        XCTAssertEqual(store.settings.usdRate, 6.6713)
        XCTAssertEqual(store.settings.handle, "Fixture")
        XCTAssertEqual(store.settings.remindHours, 12)
        XCTAssertEqual(store.statements.first, statement)
        let before = store.backup
        XCTAssertFalse(store.applyExchangeRate(-1))
        XCTAssertEqual(store.backup, before)
    }
    private func file() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("data.json")
    }
    @MainActor func testUndoAndMonthlySnapshotPersistAfterRelaunch() throws {
        let path = try file()
        let store = AppStore(fileURL: path)
        XCTAssertTrue(store.saveAccount(Account(name: "Frozen", monthlyCost: 20)))
        let id = try XCTUnwrap(store.accounts.first?.id)
        XCTAssertTrue(store.logUsage(accountID: id, intensity: .code))
        let reloaded = AppStore(fileURL: path)
        XCTAssertNotNil(reloaded.undoableUsage(accountID: id))
        XCTAssertTrue(reloaded.undoLastUsage(accountID: id))
        XCTAssertEqual(reloaded.usage.reduce(0) { $0 + $1.count }, 0)
        let statement = MonthlyStatement(month: "2026-10", accounts: reloaded.accounts, settings: reloaded.settings)
        XCTAssertTrue(reloaded.saveStatement(statement))
        var edited = reloaded.accounts[0]; edited.monthlyCost = 99
        XCTAssertTrue(reloaded.saveAccount(edited))
        XCTAssertTrue(reloaded.deleteAccount(id: id))
        let restored = AppStore(fileURL: path)
        XCTAssertEqual(restored.statements.first?.accounts.first?.monthlyCost, 20)
        XCTAssertFalse(restored.undoLastUsage(accountID: id))
        let imported = AppStore(fileURL: try file())
        XCTAssertTrue(imported.importData(try restored.exportData()))
        XCTAssertEqual(imported.statements.first?.month, "2026-10")
        XCTAssertEqual(imported.statements.first?.accounts.first?.name, "Frozen")
    }
    @MainActor func testFailedUndoAndSnapshotWriteDoNotPublish() throws {
        let path = try file()
        let store = AppStore(fileURL: path)
        XCTAssertTrue(store.saveAccount(Account()))
        let id = try XCTUnwrap(store.accounts.first?.id)
        XCTAssertTrue(store.logUsage(accountID: id, intensity: .chat))
        let before = store.backup, revision = store.revision
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        XCTAssertFalse(store.undoLastUsage(accountID: id))
        XCTAssertFalse(store.saveStatement(MonthlyStatement(month: "2026-10", accounts: store.accounts, settings: store.settings)))
        XCTAssertEqual(store.backup, before)
        XCTAssertEqual(store.revision, revision)
    }

    @MainActor func testFailedCatalogWriteRetainsPublishedCatalog() throws {
        let path = try file()
        let service = PricingCatalogService(directory: path.deletingLastPathComponent())
        var changed = service.catalog
        changed.plans[0].price += 1
        let prior = service.catalog
        let directory = path.deletingLastPathComponent().appendingPathComponent("pricing-catalog.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        XCTAssertThrowsError(try service.importData(changed.encoded()))
        XCTAssertEqual(service.catalog, prior)
    }

    @MainActor func testCorruptCatalogRemainsIntactAndValidImportReloads() throws {
        let path = try file()
        let catalogFile = path.deletingLastPathComponent().appendingPathComponent("pricing-catalog.json")
        let broken = Data("{invalid".utf8)
        try broken.write(to: catalogFile)
        let service = PricingCatalogService(directory: path.deletingLastPathComponent())
        XCTAssertEqual(service.catalog, .bundled)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertEqual(try Data(contentsOf: catalogFile), broken)
        var changed = service.catalog
        changed.plans[0].price += 1
        try service.importData(changed.encoded())
        XCTAssertEqual(PricingCatalogService(directory: path.deletingLastPathComponent()).catalog, changed)
    }
}
