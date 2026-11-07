import Foundation

/// One atomic file commits the visible data and its event journal together.
/// The top level retains the website Backup schema; old readers ignore `_sync`.
public struct SyncRepository: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load(deviceID: String) throws -> SyncDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return try SyncDocument(backup: Backup(), deviceID: deviceID)
        }
        let data = try Data(contentsOf: fileURL)
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        let document = try archive.document ?? SyncDocument(backup: archive.backup, deviceID: deviceID)
        // Validate all journal entries even when loaded from disk.
        var checked = try SyncDocument(backup: Backup(), deviceID: deviceID)
        try checked.merge(document.operations)
        try checked.restoreJournalID(document.journalID)
        if let owner = document.cloudAccountID { try checked.bindCloudAccount(owner) }
        if archive.document != nil, try checked.materialized() != archive.backup { throw SyncError.invalid }
        return checked
    }

    public func save(_ document: SyncDocument) throws {
        let backup = try document.materialized()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Archive(backup: backup, document: document))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private struct Archive: Codable {
        let backup: Backup
        let document: SyncDocument?
        private enum CodingKeys: String, CodingKey { case document = "_sync" }
        init(backup: Backup, document: SyncDocument?) { self.backup = backup; self.document = document }
        init(from decoder: Decoder) throws {
            backup = try Backup(from: decoder).validated()
            document = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(SyncDocument.self, forKey: .document)
        }
        func encode(to encoder: Encoder) throws {
            try backup.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(document, forKey: .document)
        }
    }
}
