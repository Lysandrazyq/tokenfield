import XCTest
@testable import TokenfieldCore

final class CatalogMaintenanceTests: XCTestCase {
    // These tests reject imported prices before any existing local catalog is replaced.
    func testBundledCatalogPassesStrictValidationAndRoundTrips() throws {
        let catalog = try Catalog.bundled.validated()
        XCTAssertEqual(try Catalog.decode(catalog.encoded()), catalog)
    }

    func testRejectsDuplicateIDsInEveryCollection() throws {
        var catalog = Catalog.bundled
        catalog.providers.append(catalog.providers[0])
        XCTAssertThrowsError(try catalog.validated())
        catalog = .bundled; catalog.plans.append(catalog.plans[0])
        XCTAssertThrowsError(try catalog.validated())
        catalog = .bundled; catalog.models.append(catalog.models[0])
        XCTAssertThrowsError(try catalog.validated())
        catalog = .bundled; catalog.personas.append(catalog.personas[0])
        XCTAssertThrowsError(try catalog.validated())
    }

    func testRejectsUnknownProvidersAndEmptyIDs() throws {
        var catalog = Catalog.bundled
        catalog.plans[0].provider = "unknown"
        XCTAssertThrowsError(try catalog.validated())
        catalog = .bundled; catalog.models[0].provider = "unknown"
        XCTAssertThrowsError(try catalog.validated())
        catalog = .bundled; catalog.providers[0].key = " "
        XCTAssertThrowsError(try catalog.validated())
        XCTAssertThrowsError(try Catalog().validated())
    }

    func testRejectsNegativeAndNonFinitePricesAndInvalidUsageValues() throws {
        for value in [-1, Double.infinity, Double.nan] {
            var catalog = Catalog.bundled; catalog.plans[0].price = value
            XCTAssertThrowsError(try catalog.validated())
            catalog = .bundled; catalog.models[0].input = value
            XCTAssertThrowsError(try catalog.validated())
            catalog = .bundled; catalog.models[0].output = value
            XCTAssertThrowsError(try catalog.validated())
            catalog = .bundled; catalog.models[0].cachedInput = value
            XCTAssertThrowsError(try catalog.validated())
        }
        var catalog = Catalog.bundled
        catalog.plans[0].resetKind = .hours; catalog.plans[0].resetHours = 0
        XCTAssertThrowsError(try catalog.validated())
        catalog = .bundled; catalog.personas[0].usesPerMonth = -1
        XCTAssertThrowsError(try catalog.validated())
    }

    func testRejectsInvalidCalendarDatesAndUnsafeOrUnofficialLinks() throws {
        for day in ["2026-02-29", "2026-13-01", "2026-1-01", "2026-10-10T00:00:00Z"] {
            var catalog = Catalog.bundled; catalog.plans[0].checked = day
            XCTAssertThrowsError(try catalog.validated(), day)
        }
        for source in ["http://chatgpt.com/pricing", "javascript:alert(1)", "https://evil.example/pricing", "https://chatgpt.com.evil.example/", "https://user@chatgpt.com/pricing"] {
            var catalog = Catalog.bundled; catalog.plans[0].source = source
            XCTAssertThrowsError(try catalog.validated(), source)
        }
        var catalog = Catalog.bundled; catalog.providers[0].pricingUrl = "file:///tmp/catalog.json"
        XCTAssertThrowsError(try catalog.validated())
    }

    func testRejectsOversizedDataCollectionsAndText() throws {
        XCTAssertThrowsError(try Catalog.decode(Data(repeating: 32, count: Catalog.maximumDataBytes + 1)))
        var catalog = Catalog.bundled
        catalog.models = (0...Catalog.maximumModels).map { index in
            var model = Catalog.bundled.models[0]; model.id = "model-\(index)"; return model
        }
        XCTAssertThrowsError(try catalog.validated())
        catalog = .bundled; catalog.plans[0].limits = String(repeating: "x", count: 8_193)
        XCTAssertThrowsError(try catalog.validated())
    }

    func testNewProviderUsesItsDeclaredHTTPSWebsiteAndRejectsLocalAddresses() throws {
        var catalog = Catalog.bundled
        catalog.providers.append(Provider(key: "new-provider", name: "New provider", color: "#112233", hasSubscription: true,
                                          defaultBilling: .subscription, currency: .usd, pricingUrl: "https://example.com/pricing"))
        var plan = catalog.plans[0]; plan.id = "new-plan"; plan.provider = "new-provider"; plan.source = "https://docs.example.com/pricing"
        catalog.plans.append(plan)
        XCTAssertNoThrow(try catalog.validated())
        catalog.providers[catalog.providers.count - 1].pricingUrl = "https://127.0.0.1/pricing"
        catalog.plans[catalog.plans.count - 1].source = "https://127.0.0.1/pricing"
        XCTAssertThrowsError(try catalog.validated())
    }

    func testImportPersistsAndExportReflectsRestartedCatalog() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CatalogRepository(fileURL: directory.appendingPathComponent("catalog.json"))
        XCTAssertEqual(try repository.load(), .bundled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
        var modified = Catalog.bundled; modified.plans[0].price = 12.34
        XCTAssertEqual(try repository.importData(modified.encoded()), modified)
        XCTAssertEqual(try CatalogRepository(fileURL: repository.fileURL).load(), modified)
        XCTAssertEqual(try Catalog.decode(Data(contentsOf: repository.fileURL)), modified)
    }

    func testInvalidImportPreservesExistingBytesAndBadInput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CatalogRepository(fileURL: directory.appendingPathComponent("catalog.json"))
        try repository.save(.bundled)
        let original = try Data(contentsOf: repository.fileURL)
        let badURL = directory.appendingPathComponent("bad-import.json")
        let badData = Data("{broken".utf8)
        try badData.write(to: badURL)
        XCTAssertThrowsError(try repository.importData(Data(contentsOf: badURL)))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
        XCTAssertEqual(try Data(contentsOf: badURL), badData)
    }

    func testCorruptLocalFileIsNotSilentlyOverwrittenOnLoad() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CatalogRepository(fileURL: directory.appendingPathComponent("catalog.json"))
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), corrupt)
    }

    func testFailedWriteLeavesExistingFileAndRestoreWritesBundledCatalog() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("blocker")
        let original = Data("keep me".utf8); try original.write(to: blocker)
        let blocked = CatalogRepository(fileURL: blocker.appendingPathComponent("catalog.json"))
        XCTAssertThrowsError(try blocked.importData(Catalog.bundled.encoded()))
        XCTAssertEqual(try Data(contentsOf: blocker), original)
        let repository = CatalogRepository(fileURL: directory.appendingPathComponent("catalog.json"))
        var modified = Catalog.bundled; modified.plans[0].price = 12.34
        try repository.save(modified)
        try repository.restoreBundled()
        XCTAssertEqual(try repository.load(), .bundled)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-maintenance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
