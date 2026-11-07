import XCTest
import CloudKit
import TokenfieldCore
@testable import Tokenfield

final class CloudTransportTests: XCTestCase {
    // These fixtures fail if batching reverts to count-only: three individually
    // valid inline records exceed CloudKit's 2 MB non-asset request limit.
    func testLargeNotesAreByteBoundedWithoutLosingAnyOperation() throws {
        let document = try fixture(count: 3, noteBytes: 750_000)
        let batches = try CloudUploadBatching.batches(document.operations)
        XCTAssertGreaterThan(batches.count, 1)
        for batch in batches {
            XCTAssertLessThanOrEqual(batch.reduce(0) { $0 + $1.estimatedRecordBytes }, 1_500_000)
            XCTAssertLessThanOrEqual(batch.count, 200)
        }
        XCTAssertEqual(batches.flatMap { $0.map(\.event.id) }, document.operations.map(\.id))
        var received = try SyncDocument(backup: Backup(), deviceID: "receiver")
        try received.merge(batches.flatMap { $0 }.map { try SyncOperation.decode($0.payload) })
        XCTAssertEqual(try received.materialized(), try document.materialized())
    }

    func testSmallOperationsStillRespectRecordCountLimit() throws {
        let document = try fixture(count: 420, noteBytes: 1)
        let batches = try CloudUploadBatching.batches(document.operations)
        XCTAssertEqual(batches.map(\.count), [200, 200, 20])
        XCTAssertEqual(batches.flatMap { $0.map(\.event.id) }, document.operations.map(\.id))
    }

    func testLargeIndividualOperationUsesReadableAsset() throws {
        let directory = try temporaryDirectory()
        let document = try fixture(count: 1, noteBytes: 1_000_000)
        let item = try XCTUnwrap(CloudUploadBatching.batches(document.operations).first?.first)
        let record = try item.record(zoneID: zoneID, temporaryDirectory: directory, forceAsset: false)
        XCTAssertNil(record["payload"])
        let asset = try XCTUnwrap(record["payloadAsset"] as? CKAsset)
        let data = try Data(contentsOf: XCTUnwrap(asset.fileURL))
        XCTAssertEqual(try SyncOperation.decode(data), document.operations.first)
    }

    @MainActor func testLimitExceededSplitsAndSafelyReplaysPartialSuccess() async throws {
        let document = try fixture(count: 3, noteBytes: 300_000)
        let batch = try XCTUnwrap(CloudUploadBatching.batches(document.operations).first)
        var received = try SyncDocument(backup: Backup(), deviceID: "receiver")
        try await CloudUploadBatching.send(batch) { items, _ in
            // A non-atomic request can save an event before reporting failure.
            // The real journal merge must tolerate that event being sent again.
            if items.count > 1 {
                try received.merge([items[0].event])
                throw self.partialError(.limitExceeded)
            }
            try received.merge(items.map { try SyncOperation.decode($0.payload) })
        }
        XCTAssertEqual(received.operationIDs, document.operationIDs)
        XCTAssertEqual(try received.materialized(), try document.materialized())
    }

    @MainActor func testSingleRejectedInlineRecordRetriesAsDownloadedReadableAsset() async throws {
        let directory = try temporaryDirectory()
        let document = try fixture(count: 1, noteBytes: 750_000)
        let batch = try XCTUnwrap(CloudUploadBatching.batches(document.operations).first)
        var received: SyncOperation?
        var attempts = 0
        try await CloudUploadBatching.send(batch) { items, forceAsset in
            attempts += 1
            let record = try XCTUnwrap(items.first).record(zoneID: self.zoneID, temporaryDirectory: directory, forceAsset: forceAsset)
            if record["payload"] != nil { throw CKError(.limitExceeded) }
            let asset = try XCTUnwrap(record["payloadAsset"] as? CKAsset)
            received = try SyncOperation.decode(Data(contentsOf: XCTUnwrap(asset.fileURL)))
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(received, document.operations.first)
    }

    @MainActor func testUnrecoverableLimitExceededTerminatesWithoutAcknowledgingSuccess() async throws {
        let batch = try XCTUnwrap(CloudUploadBatching.batches(fixture(count: 1, noteBytes: 1).operations).first)
        var attempts = 0
        do {
            try await CloudUploadBatching.send(batch) { _, _ in
                attempts += 1
                throw CKError(.limitExceeded)
            }
            XCTFail("The event must remain pending when both inline and asset saves fail")
        } catch {
            XCTAssertTrue(CloudSyncErrors.contains(.limitExceeded, in: error))
        }
        XCTAssertEqual(attempts, 2)
    }

    @MainActor func testNetworkFailureDoesNotSplitOrRetryImmediately() async throws {
        let batch = try XCTUnwrap(CloudUploadBatching.batches(fixture(count: 3, noteBytes: 1).operations).first)
        var attempts = 0
        do {
            try await CloudUploadBatching.send(batch) { _, _ in
                attempts += 1
                throw CKError(.networkUnavailable)
            }
            XCTFail("Network failures must keep the batch pending")
        } catch {
            XCTAssertEqual((error as? CKError)?.code, .networkUnavailable)
        }
        XCTAssertEqual(attempts, 1)
    }

    @MainActor func testOnlySuccessfulSubBatchIsAcknowledgedWhenLaterSplitFails() async throws {
        let document = try fixture(count: 2, noteBytes: 1)
        let batch = try XCTUnwrap(CloudUploadBatching.batches(document.operations).first)
        var acknowledged = Set<String>()
        do {
            try await CloudUploadBatching.send(batch, didSave: { saved in
                acknowledged.formUnion(saved.map(\.event.id))
            }) { items, _ in
                if items.count > 1 { throw CKError(.limitExceeded) }
                if items[0].event.id == batch[1].event.id { throw CKError(.networkUnavailable) }
            }
            XCTFail("The second event must remain pending")
        } catch {
            XCTAssertEqual((error as? CKError)?.code, .networkUnavailable)
        }
        XCTAssertEqual(acknowledged, [batch[0].event.id])
    }

    @MainActor func testExpiredTokenResetsCursorAndAcknowledgementsBeforeFullFetch() async throws {
        var cursor: String? = "expired"
        var acknowledged = Set(["previously-sent"])
        var steps: [String] = []
        let value = try await CloudSyncErrors.fetchResettingExpiredToken(token: cursor, reset: {
            cursor = nil
            acknowledged.removeAll()
            steps.append("reset")
        }) { token in
            steps.append(token == nil ? "full-fetch" : "incremental-fetch")
            if token != nil { throw self.partialError(.changeTokenExpired) }
            XCTAssertNil(cursor)
            XCTAssertTrue(acknowledged.isEmpty)
            return "durable-changes"
        }
        XCTAssertEqual(value, "durable-changes")
        XCTAssertEqual(steps, ["incremental-fetch", "reset", "full-fetch"])
    }

    func testExpiredTokenIsRecognizedInsideActualCloudKitPartialFailure() {
        let nested = partialError(.changeTokenExpired)
        XCTAssertTrue(CloudSyncErrors.contains(.changeTokenExpired, in: nested))
        let twiceNested = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [zoneID: nested]])
        XCTAssertTrue(CloudSyncErrors.contains(.changeTokenExpired, in: twiceNested))
        XCTAssertFalse(CloudSyncErrors.contains(.changeTokenExpired, in: partialError(.networkUnavailable)))
    }

    func testZoneFailureSurvivesOverallPartialFailure() {
        let failure = CloudSyncErrors.fetchFailure(operation: partialError(.changeTokenExpired), zone: CKError(.changeTokenExpired))
        XCTAssertEqual((failure as? CKError)?.code, .changeTokenExpired)
    }

    @MainActor func testAssetConflictDownloadsRecordBeforeComparingImmutablePayload() async throws {
        let directory = try temporaryDirectory()
        let document = try fixture(count: 1, noteBytes: 1_000_000)
        let item = try XCTUnwrap(CloudUploadBatching.batches(document.operations).first?.first)
        let local = try item.record(zoneID: zoneID, temporaryDirectory: directory, forceAsset: false)
        let server = CKRecord(recordType: "TokenfieldOperation", recordID: local.recordID)
        // Apple's error serverRecord has a CKAsset without a staged file. The
        // public initializer requires a URL; an absent file reproduces the same
        // unreadable payload boundary without private API or live cloud calls.
        server["payloadAsset"] = CKAsset(fileURL: directory.appendingPathComponent("not-downloaded.json"))
        let matches = try await CloudSyncService.matchesImmutableRecord(server: server, local: local) { id in
            XCTAssertEqual(id, local.recordID)
            return local
        }
        XCTAssertTrue(matches)
    }

    @MainActor func testAssetConflictDoesNotAcknowledgeDifferentDownloadedEvent() async throws {
        let directory = try temporaryDirectory()
        let first = try XCTUnwrap(CloudUploadBatching.batches(fixture(count: 1, noteBytes: 1_000_000).operations).first?.first)
        let second = try XCTUnwrap(CloudUploadBatching.batches(fixture(count: 1, noteBytes: 900_000).operations).first?.first)
        let local = try first.record(zoneID: zoneID, temporaryDirectory: directory, forceAsset: false)
        let server = CKRecord(recordType: "TokenfieldOperation", recordID: local.recordID)
        server["payloadAsset"] = CKAsset(fileURL: directory.appendingPathComponent("not-downloaded.json"))
        let downloaded = try second.record(zoneID: zoneID, temporaryDirectory: directory, forceAsset: false)
        let matches = try await CloudSyncService.matchesImmutableRecord(server: server, local: local) { _ in downloaded }
        XCTAssertFalse(matches)
    }

    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: "transport-test", ownerName: CKCurrentUserDefaultName) }

    private func partialError(_ code: CKError.Code) -> CKError {
        CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [zoneID: CKError(code)]])
    }

    private func fixture(count: Int, noteBytes: Int) throws -> SyncDocument {
        var backup = Backup()
        backup.accounts = (0..<count).map { index in
            var account = Account(id: index + 1, name: "Account \(index)", createdAt: "2026-10-31T00:00:00.000Z")
            account.note = String(repeating: "x", count: noteBytes)
            return account
        }
        return try SyncDocument(backup: backup, deviceID: "sender")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
