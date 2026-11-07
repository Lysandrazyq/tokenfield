import Foundation

/// The pricing catalog is local reference data, separate from account/cloud documents.
public struct CatalogRepository: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> Catalog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return try Catalog.bundled.validated() }
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Catalog.maximumDataBytes else { throw CatalogIssue.tooLarge }
        return try Catalog.decode(Data(contentsOf: fileURL))
    }

    public func save(_ catalog: Catalog) throws {
        let data = try catalog.encoded()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult public func importData(_ data: Data) throws -> Catalog {
        let catalog = try Catalog.decode(data)
        try save(catalog)
        return catalog
    }

    public func restoreBundled() throws { try save(.bundled) }
}
