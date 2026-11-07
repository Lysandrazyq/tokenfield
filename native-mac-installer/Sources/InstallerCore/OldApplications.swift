import Foundation

public struct OldApplication: Identifiable {
    public let url: URL
    public let version: String
    public let build: String
    public var id: String { url.path }
    fileprivate let snapshot: BundleSnapshot
}

public enum RemovalError: LocalizedError {
    case invalidApplication, differentApplication, notOlder, protectedApplication, changed
    public var errorDescription: String? {
        switch self {
        case .invalidApplication: return "这个文件不是可识别的额度终端应用，或应用已损坏。"
        case .differentApplication: return "所选应用不是额度终端，未作任何修改。"
        case .notOlder: return "这个应用与安装包版本相同、更新，或版本号无法确认，不能作为旧版卸载。"
        case .protectedApplication: return "不能卸载安装包里的应用或卸载助手本身。"
        case .changed: return "应用在检查后发生了变化。请重新扫描再操作。"
        }
    }
}

private struct NumericVersion: Comparable {
    let parts: [Int]
    init?(_ text: String) {
        let components = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 5 else { return nil }
        var numbers: [Int] = []
        for part in components {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.last == 0 && numbers.count > 1 { numbers.removeLast() }
        parts = numbers
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }
}

fileprivate struct FileSnapshot: Equatable {
    let inode: UInt64
    let device: UInt64
    let created: Date?
    let modified: Date?
    let size: UInt64
    init(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        device = (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0
        created = attributes[.creationDate] as? Date
        modified = attributes[.modificationDate] as? Date
        size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }
}

fileprivate struct BundleSnapshot: Equatable {
    let root: FileSnapshot
    let metadata: FileSnapshot
    let executable: FileSnapshot
    let plist: Data
}

public struct OldAppFinder {
    public static let bundleID = "space.lysandra.quotakeeper"
    private let latestVersion: NumericVersion?
    private let latestBuild: NumericVersion?
    private let protectedPaths: Set<String>

    public init(latestVersion: String, latestBuild: String, protectedApps: [URL] = []) {
        self.latestVersion = NumericVersion(latestVersion)
        self.latestBuild = NumericVersion(latestBuild)
        protectedPaths = Set(protectedApps.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
    }

    public func scan(roots: [URL], additionalApps: [URL] = []) -> [OldApplication] {
        let fm = FileManager.default
        var urls = additionalApps
        for root in roots {
            let directory = root.resolvingSymlinksInPath().standardizedFileURL
            if let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                urls.append(contentsOf: children.filter { $0.pathExtension.lowercased() == "app" })
            }
        }
        var found: [String: OldApplication] = [:]
        for url in urls {
            if let app = try? inspect(url) { found[app.id] = app }
        }
        return found.values.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    public func inspect(_ app: URL) throws -> OldApplication {
        let fm = FileManager.default
        let input = app.standardizedFileURL
        guard input.isFileURL, input.pathExtension.lowercased() == "app",
              (try? input.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else {
            throw RemovalError.invalidApplication
        }
        let canonical = input.resolvingSymlinksInPath().standardizedFileURL
        guard !protectedPaths.contains(canonical.path) else { throw RemovalError.protectedApplication }
        guard (try? canonical.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              (try? canonical.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) != true else {
            throw RemovalError.invalidApplication
        }
        let info = canonical.appendingPathComponent("Contents/Info.plist")
        guard info == info.resolvingSymlinksInPath().standardizedFileURL,
              (try? info.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let data = try? Data(contentsOf: info),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            throw RemovalError.invalidApplication
        }
        guard plist["CFBundleIdentifier"] as? String == Self.bundleID else { throw RemovalError.differentApplication }
        guard plist["CFBundlePackageType"] as? String == "APPL",
              let name = plist["CFBundleExecutable"] as? String,
              !name.isEmpty, name != ".", name != "..", !name.contains("/") else { throw RemovalError.invalidApplication }
        let executable = canonical.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
        guard executable == executable.resolvingSymlinksInPath().standardizedFileURL,
              (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              fm.isExecutableFile(atPath: executable.path) else { throw RemovalError.invalidApplication }
        guard let versionText = plist["CFBundleShortVersionString"] as? String,
              let version = NumericVersion(versionText), let latestVersion,
              let buildText = plist["CFBundleVersion"] as? String else { throw RemovalError.notOlder }
        let older: Bool
        if version < latestVersion {
            older = true
        } else if version == latestVersion, let build = NumericVersion(buildText), let latestBuild {
            older = build < latestBuild
        } else {
            older = false
        }
        guard older else { throw RemovalError.notOlder }
        let snapshot = try BundleSnapshot(root: FileSnapshot(canonical), metadata: FileSnapshot(info), executable: FileSnapshot(executable), plist: data)
        return OldApplication(url: canonical, version: versionText, build: buildText, snapshot: snapshot)
    }
}

public struct OldAppUninstaller {
    private let finder: OldAppFinder
    private let moveToTrash: (URL) throws -> URL
    public init(finder: OldAppFinder, moveToTrash: @escaping (URL) throws -> URL = { url in
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        guard let result = trashed as URL? else { throw CocoaError(.fileWriteUnknown) }
        return result
    }) {
        self.finder = finder
        self.moveToTrash = moveToTrash
    }
    public func trash(_ app: OldApplication) throws -> URL {
        try validate(app)
        return try moveToTrash(app.url)
    }
    public func validate(_ app: OldApplication) throws {
        let current = try finder.inspect(app.url)
        guard current.snapshot == app.snapshot else { throw RemovalError.changed }
    }
}
