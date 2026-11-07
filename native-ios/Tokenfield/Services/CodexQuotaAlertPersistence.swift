#if os(macOS)
import Foundation
import Darwin

@MainActor protocol CodexQuotaAlertPersistence {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

/// Checked atomic app-local state, separate from the business ledger and cloud sync.
@MainActor final class CodexQuotaFilePersistence: CodexQuotaAlertPersistence {
    let url: URL
    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("Tokenfield/CodexQuotaAlerts.json")) { self.url = url }
    func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
        return try Data(contentsOf: url)
    }
    func save(_ data: Data) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        let file = try FileHandle(forWritingTo: url)
        do { try file.synchronize(); try file.close() }
        catch { try? file.close(); throw error }
        let descriptor = open(folder.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// Explicit test/legacy preference injection. The shipping app uses the checked file above.
@MainActor final class CodexQuotaPreferencePersistence: CodexQuotaAlertPersistence {
    let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    func load() throws -> Data? { defaults.data(forKey: CodexQuotaAlertStore.preferenceKey) }
    func save(_ data: Data) throws { defaults.set(data, forKey: CodexQuotaAlertStore.preferenceKey) }
}
#endif
