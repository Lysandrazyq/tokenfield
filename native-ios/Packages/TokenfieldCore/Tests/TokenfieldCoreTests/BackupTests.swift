import XCTest
@testable import TokenfieldCore

final class BackupTests: XCTestCase {
    // Catches loss of legacy compatibility and changes to persisted strings/identifiers.
    func testLegacyBackupWithoutUsageAndModernRoundTrip() throws {
        let legacy = Data(#"{"app":"ai-quota-keeper","version":1,"exportedAt":"2026-10-10T00:00:00.000Z","accounts":[{"id":7,"name":"旧账号","provider":"custom","billing":"subscription","monthlyCost":20,"currency":"USD","resetKind":"none","notifyReset":false,"models":"原样","note":"注释","createdAt":"2026-01-31T10:00:00+08:00"}],"expiries":[],"settings":{"id":"main","usdRate":7.1,"remindHours":24,"handle":"L"}}"#.utf8)
        let backup = try Backup.decode(legacy)
        XCTAssertEqual(backup.usage, [])
        XCTAssertEqual(backup.accounts.first?.createdAt, "2026-01-31T10:00:00+08:00")
        XCTAssertEqual(try Backup.decode(backup.encoded()), backup)
        var modern = backup
        modern.version = 2
        modern.usage = [Usage(id: 3, accountId: 7, day: "2026-10-10", count: 2, intensity: .agent, hitLimit: true)]
        modern.expiries = [Expiry(id: 4, title: "到期", accountId: 7, expiresAt: "2026-11-01T00:00:00Z")]
        XCTAssertEqual(try Backup.decode(modern.encoded()), modern)
    }

    // Removing validation or writing before validation corrupts the on-disk good backup.
    func testInvalidImportAndSavePreserveExistingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = DataRepository(fileURL: folder.appendingPathComponent("state.json"))
        XCTAssertEqual(try repository.load().accounts, [])
        var good = Backup()
        good.saveAccount(Account(name: "保存的账号"))
        try repository.save(good)
        let original = try Data(contentsOf: folder.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try repository.importData(Data("{}".utf8)))
        var invalid = good
        invalid.accounts[0].monthlyCost = -.infinity
        XCTAssertThrowsError(try repository.save(invalid))
        invalid = good
        invalid.accounts.append(invalid.accounts[0])
        let duplicateJSON = try JSONEncoder().encode(invalid)
        XCTAssertThrowsError(try repository.importData(duplicateJSON))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), original)
        XCTAssertEqual(try repository.load(), good)
    }

    func testMalformedUsageCannotReplaceExistingBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let repository = DataRepository(fileURL: file)
        let good = Backup(accounts: [Account(id: 1, name: "已有账号")], usage: [Usage(id: 1, accountId: 1, day: "2026-10-15", count: 4, intensity: .chat)])
        try repository.save(good)
        let original = try Data(contentsOf: file)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: good.encoded()) as? [String: Any])
        let malformed: [(Int, Any?)] = [(1, NSNull()), (2, nil), (2, NSNull()), (2, [:])]
        for (version, usage) in malformed {
            try repository.save(good)
            var candidate = object
            candidate["version"] = version
            candidate["usage"] = usage
            let data = try JSONSerialization.data(withJSONObject: candidate)
            XCTAssertThrowsError(try Backup.decode(data), "version \(version), usage \(String(describing: usage))")
            XCTAssertThrowsError(try repository.importData(data))
            XCTAssertEqual(try Data(contentsOf: file), original)
            XCTAssertEqual(try repository.load().usage, good.usage)
        }
    }

    // Catches holes in numeric, date, uniqueness and relationship validation.
    func testValidationRejectsMalformedValuesAndReferences() throws {
        var good = Backup()
        good.saveAccount(Account(name: "有效"))
        let invalids: [(inout Backup) -> Void] = [
            { $0.app = "other" }, { $0.version = 99 }, { $0.exportedAt = "bad" },
            { $0.settings.usdRate = 0 }, { $0.settings.remindHours = -1 },
            { $0.settings.usdRate = .nan }, { $0.accounts[0].monthlyCost = -1 },
            { $0.accounts[0].balance = -1 }, { $0.accounts[0].resetHours = 0 },
            { $0.accounts[0].renewAt = "2026-02-30T00:00:00Z" },
            { $0.accounts[0].resetAnchor = "bad" }, { $0.accounts[0].id = 0 },
            { $0.accounts.append($0.accounts[0]) },
            { $0.expiries = [Expiry(id: 1, accountId: 77)] },
            { $0.expiries = [Expiry(id: 1, expiresAt: "bad")] },
            { $0.expiries = [Expiry(id: 1), Expiry(id: 1)] },
            { $0.usage = [Usage(id: 1, accountId: 77, day: "2026-10-10", count: 1, intensity: .chat)] },
            { $0.usage = [Usage(id: 1, accountId: 1, day: "2026-02-30", count: 1, intensity: .chat)] },
            { $0.usage = [Usage(id: 1, accountId: 1, day: "2026-10-10", count: -1, intensity: .chat)] },
            { $0.usage = [Usage(id: 1, accountId: 1, day: "2026-10-10", count: 1, intensity: .chat), Usage(id: 1, accountId: 1, day: "2026-10-11", count: 1, intensity: .chat)] }
        ]
        for (index, mutation) in invalids.enumerated() {
            var invalid = good
            mutation(&invalid)
            XCTAssertThrowsError(try invalid.validated(), "case \(index)")
        }
        XCTAssertNoThrow(try good.validated())
    }

    // Catches IDs being allocated by count and a partial account-delete cascade.
    func testMutationsAllocateUniqueIDsUpdateAndCascade() throws {
        var backup = Backup(accounts: [Account(id: 9, name: "原有")])
        backup.saveAccount(Account(name: "新增"))
        XCTAssertEqual(backup.accounts.map(\.id), [9, 10])
        backup.saveAccount(Account(id: 9, name: "修改"))
        XCTAssertEqual(backup.accounts.count, 2)
        XCTAssertEqual(backup.accounts[0].name, "修改")
        backup.saveExpiry(Expiry(accountId: 9))
        backup.saveExpiry(Expiry(title: "独立"))
        var expiry = backup.expiries[0]
        expiry.done = true
        backup.saveExpiry(expiry)
        XCTAssertEqual(backup.expiries.count, 2)
        XCTAssertTrue(backup.expiries[0].done)
        let noon = Date(timeIntervalSince1970: 1791633600)
        backup.logUsage(accountID: 9, intensity: .chat, now: noon)
        backup.logUsage(accountID: 9, intensity: .chat, now: noon)
        backup.logUsage(accountID: 9, intensity: .agent, now: noon)
        backup.logUsage(accountID: 10, intensity: .write, now: noon)
        backup.logUsage(accountID: 999, intensity: .chat, now: noon)
        XCTAssertEqual(backup.usage.count, 3)
        XCTAssertEqual(backup.usage[0].count, 2)
        XCTAssertEqual(backup.usage[0].intensity, .chat)
        backup.deleteAccount(id: 9)
        XCTAssertEqual(backup.accounts.map(\.id), [10])
        XCTAssertEqual(backup.usage.map(\.accountId), [10])
        XCTAssertEqual(backup.expiries.map(\.title), ["独立"])
        backup.deleteExpiry(id: backup.expiries[0].id)
        XCTAssertTrue(backup.expiries.isEmpty)
        XCTAssertNoThrow(try backup.validated())
    }
}
