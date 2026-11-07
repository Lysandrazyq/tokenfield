import Foundation
import Observation
import TokenfieldCore

@MainActor @Observable
final class PricingCatalogService {
    private(set) var catalog: Catalog
    private(set) var statusText: String
    private(set) var errorMessage: String?
    private(set) var isBundled: Bool
    private let repository: CatalogRepository

    init(directory: URL) {
        let repository = CatalogRepository(fileURL: directory.appendingPathComponent("pricing-catalog.json"))
        self.repository = repository
        do {
            let loaded = try repository.load()
            let bundled = loaded == Catalog.bundled
            catalog = loaded
            isBundled = bundled
            statusText = bundled ? "正在使用内置目录" : "正在使用导入的本地目录"
        } catch {
            catalog = .bundled
            isBundled = true
            statusText = "正在使用内置目录"
            errorMessage = "本地价格目录无法读取，原文件已保留。\n\(error.localizedDescription)"
        }
    }

    func importData(_ data: Data) throws {
        do {
            let candidate = try repository.importData(data)
            catalog = candidate
            isBundled = candidate == .bundled
            statusText = "价格目录已导入并保存到本机"
            errorMessage = nil
        } catch {
            errorMessage = "价格目录导入失败，当前目录已保留。\n\(error.localizedDescription)"
            throw error
        }
    }

    func exportData() throws -> Data { try catalog.encoded() }

    func restoreBundled() throws {
        do {
            try repository.restoreBundled()
            catalog = .bundled
            isBundled = true
            statusText = "已恢复内置价格目录"
            errorMessage = nil
        } catch {
            errorMessage = "恢复内置目录失败，当前目录已保留。\n\(error.localizedDescription)"
            throw error
        }
    }
}
