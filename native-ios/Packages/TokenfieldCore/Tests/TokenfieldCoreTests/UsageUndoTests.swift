import XCTest
@testable import TokenfieldCore

final class UsageUndoTests: XCTestCase {
    private func state() throws -> SyncDocument {
        try SyncDocument(backup: Backup(accounts: [Account(id: 1, name: "Test")],
            usage: [Usage(id: 1, accountId: 1, day: "2026-10-31", count: 3, intensity: .chat)]), deviceID: "A")
    }
    private func record(_ state: inout SyncDocument) throws -> Int {
        let before = try state.materialized()
        var after = before
        let id = try XCTUnwrap(before.accounts.first?.id)
        after.logUsage(accountID: id, intensity: .chat, now: DateCodec.date("2026-10-31T12:00:00Z")!)
        try state.recordChange(from: before, to: after)
        return id
    }

    func testUndoTargetsOnlyOneLocalIncrementAndSurvivesReload() throws {
        var a = try state()
        let id = try record(&a)
        let first = try XCTUnwrap(a.latestUndoableUsage(accountID: id))
        _ = try record(&a)
        let latest = try XCTUnwrap(a.latestUndoableUsage(accountID: id))
        XCTAssertNotEqual(first.id, latest.id)
        XCTAssertEqual(try a.materialized().usage.first?.count, 5)
        try a.undoUsage(operationID: latest.id)
        XCTAssertEqual(try a.materialized().usage.first?.count, 4)
        XCTAssertEqual(a.latestUndoableUsage(accountID: id)?.id, first.id)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let repository = SyncRepository(fileURL: file)
        try repository.save(a)
        var reloaded = try repository.load(deviceID: "A")
        try reloaded.undoUsage(operationID: first.id)
        XCTAssertEqual(try reloaded.materialized().usage.first?.count, 3)
        XCTAssertNil(reloaded.latestUndoableUsage(accountID: id))
    }

    func testConcurrentIncrementsAndRepeatedCancellationConverge() throws {
        var a = try state()
        var b = a
        b.setDeviceID("B")
        let id = try record(&a)
        let target = try XCTUnwrap(a.latestUndoableUsage(accountID: id))
        _ = try record(&b)
        try a.undoUsage(operationID: target.id)
        try a.undoUsage(operationID: target.id)
        try a.merge(b.operations)
        try b.merge(a.operations.reversed())
        try a.merge(b.operations)
        XCTAssertEqual(try a.materialized().usage.first?.count, 4)
        XCTAssertEqual(try a.materialized(), try b.materialized())
        XCTAssertNil(a.latestUndoableUsage(accountID: id))
        XCTAssertNotNil(b.latestUndoableUsage(accountID: id))
    }

    func testLegacyAndOtherDeviceEventsCannotBeUndone() throws {
        var a = try state()
        let legacy = try XCTUnwrap(a.operations.first { if case .usage = $0.payload { return true }; return false })
        XCTAssertThrowsError(try a.undoUsage(operationID: legacy.id))
        var b = a; b.setDeviceID("B")
        let id = try record(&b)
        let remote = try XCTUnwrap(b.latestUndoableUsage(accountID: id))
        try a.merge(b.operations)
        XCTAssertThrowsError(try a.undoUsage(operationID: remote.id))
        XCTAssertEqual(try a.materialized().usage.first?.count, 4)
    }

    func testImportedSingleCountIsNotMistakenForANativeTap() throws {
        var a = try SyncDocument(backup: Backup(), deviceID: "A")
        try a.replace(with: Backup(accounts: [Account(id: 1)],
            usage: [Usage(id: 1, accountId: 1, day: "2026-10-31", count: 1, intensity: .chat)]))
        let id = try XCTUnwrap(a.materialized().accounts.first?.id)
        XCTAssertNil(a.latestUndoableUsage(accountID: id))
    }

    func testCancellationCanArriveBeforeItsTapWithoutRestoringUsageLater() throws {
        var origin = try state()
        var receiver = origin; receiver.setDeviceID("B")
        let id = try record(&origin)
        let tap = try XCTUnwrap(origin.latestUndoableUsage(accountID: id))
        try origin.undoUsage(operationID: tap.id)
        let cancellation = try XCTUnwrap(origin.operations.first { if case .undoUsage = $0.payload { return true }; return false })
        try receiver.merge([cancellation])
        XCTAssertEqual(try receiver.materialized().usage.first?.count, 3)
        try receiver.merge([tap])
        XCTAssertEqual(try receiver.materialized().usage.first?.count, 3)
        try receiver.merge(origin.operations)
        XCTAssertEqual(try receiver.materialized(), try origin.materialized())
    }
}
