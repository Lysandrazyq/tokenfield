import Foundation
import CloudKit
import TokenfieldCore

struct CloudUploadItem {
    let event: SyncOperation
    let payload: Data
    static let inlineByteLimit = 800_000
    // Reserve space for record names, field names, schema and asset metadata.
    // CloudKit can change its limits; server rejection is handled by splitting.
    var estimatedRecordBytes: Int { (payload.count <= Self.inlineByteLimit ? payload.count : 0) + 2_048 }

    func record(zoneID: CKRecordZone.ID, temporaryDirectory: URL, forceAsset: Bool) throws -> CKRecord {
        let record = CKRecord(recordType: "TokenfieldOperation", recordID: CKRecord.ID(recordName: event.id, zoneID: zoneID))
        if !forceAsset && payload.count <= Self.inlineByteLimit { record["payload"] = payload as CKRecordValue }
        else {
            let file = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            try payload.write(to: file, options: .atomic)
            record["payloadAsset"] = CKAsset(fileURL: file)
        }
        record["schemaVersion"] = NSNumber(value: 1)
        return record
    }
}

enum CloudUploadBatching {
    static func batches(_ events: [SyncOperation]) throws -> [[CloudUploadItem]] {
        var result: [[CloudUploadItem]] = []
        var batch: [CloudUploadItem] = []
        var bytes = 0
        for event in events {
            let item = CloudUploadItem(event: event, payload: try event.encoded())
            // Keep substantial headroom under CloudKit's current 2 MB request
            // guideline. Asset file bytes do not count toward that limit.
            if !batch.isEmpty && (batch.count == 200 || bytes + item.estimatedRecordBytes > 1_500_000) {
                result.append(batch)
                batch = []; bytes = 0
            }
            batch.append(item)
            bytes += item.estimatedRecordBytes
        }
        if !batch.isEmpty { result.append(batch) }
        return result
    }

    @MainActor static func send(_ batch: [CloudUploadItem], didSave: ([CloudUploadItem]) async throws -> Void = { _ in }, using attempt: ([CloudUploadItem], Bool) async throws -> Void) async throws {
        guard !batch.isEmpty else { return }
        do { try await attempt(batch, false) }
        catch {
            guard CloudSyncErrors.contains(.limitExceeded, in: error) else { throw error }
            if batch.count > 1 {
                let middle = batch.count / 2
                try await send(Array(batch[..<middle]), didSave: didSave, using: attempt)
                try await send(Array(batch[middle...]), didSave: didSave, using: attempt)
                return
            }
            // If the service's record limit is lower than our estimate, move
            // even a small singleton payload to an asset once. Never loop on
            // an asset that the server also rejects, and never acknowledge it.
            guard batch[0].payload.count <= CloudUploadItem.inlineByteLimit else { throw error }
            try await attempt(batch, true)
        }
        try await didSave(batch)
    }
}

enum CloudSyncErrors {
    static func contains(_ code: CKError.Code, in error: Error) -> Bool {
        guard let cloud = error as? CKError else { return false }
        if cloud.code == code { return true }
        guard cloud.code == .partialFailure else { return false }
        return cloud.partialErrorsByItemID?.values.contains { contains(code, in: $0) } ?? false
    }

    // A zone callback carries the actionable error even when the overall
    // operation finishes with an enclosing partialFailure.
    static func fetchFailure(operation: Error, zone: Error?) -> Error { zone ?? operation }

    @MainActor static func fetchResettingExpiredToken<Cursor, Value>(token: Cursor?, reset: () -> Void, fetch: (Cursor?) async throws -> Value) async throws -> Value {
        do { return try await fetch(token) }
        catch where contains(.changeTokenExpired, in: error) {
            reset()
            return try await fetch(nil)
        }
    }
}
