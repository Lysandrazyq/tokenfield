import XCTest
@testable import InstallerCore

final class OldApplicationsTests: XCTestCase {
    var fixture: URL!
    var applications: URL!
    var trash: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        fixture = fm.temporaryDirectory.appendingPathComponent("TokenfieldUninstallerTests-\(UUID().uuidString)")
        applications = fixture.appendingPathComponent("Applications")
        trash = fixture.appendingPathComponent("Trash")
        try fm.createDirectory(at: applications, withIntermediateDirectories: true)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try fm.removeItem(at: fixture) }

    @discardableResult
    func app(_ name: String, version: String, build: String = "1", id: String = "space.lysandra.quotakeeper", parent: URL? = nil) throws -> URL {
        let app = (parent ?? applications).appendingPathComponent(name + ".app")
        let contents = app.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try plist(app, version: version, build: build, id: id)
        let executable = contents.appendingPathComponent("MacOS/TokenfieldMac")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return app
    }
    func plist(_ app: URL, version: String, build: String, id: String = "space.lysandra.quotakeeper") throws {
        let data: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL", "CFBundleExecutable": "TokenfieldMac", "CFBundleShortVersionString": version, "CFBundleVersion": build]
        try PropertyListSerialization.data(fromPropertyList: data, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
    }
    func finder(version: String = "1.1.4", build: String = "7", protected: [URL] = []) -> OldAppFinder {
        OldAppFinder(latestVersion: version, latestBuild: build, protectedApps: protected)
    }
    func uninstaller(_ finder: OldAppFinder) -> OldAppUninstaller {
        OldAppUninstaller(finder: finder) { source in
            let target = self.trash.appendingPathComponent(source.lastPathComponent)
            try self.fm.moveItem(at: source, to: target)
            return target
        }
    }

    // Catches deleting current/newer apps, lexicographic version comparison and scanning unrelated apps.
    func testScanFindsOnlyOlderReleasesAndBuilds() throws {
        try app("旧版", version: "1.1.3", build: "6")
        try app("旧构建", version: "1.1.4", build: "6")
        try app("当前版", version: "1.1.4", build: "7")
        try app("新构建", version: "1.1.4", build: "8")
        try app("未来版", version: "1.10.0", build: "1")
        try app("其他软件", version: "1.0.0", id: "example.other")
        try app("未知版本", version: "development")
        XCTAssertEqual(finder().scan(roots: [applications]).map { $0.url.lastPathComponent }.sorted(), ["旧构建.app", "旧版.app"])
    }
    // Catches incorrectly ordering 1.9 after 1.10 or comparing a marketing version by its build.
    func testNumericVersionComponentsTakePriorityOverBuild() throws {
        let old = try app("数值旧版", version: "1.9.9", build: "999")
        XCTAssertEqual(try finder(version: "1.10.0").inspect(old).version, "1.9.9")
        XCTAssertThrowsError(try finder(version: "1.9.9", build: "998").inspect(old))
    }
    // Catches broad recursive cleanup and touching a protected source application.
    func testScanIsShallowDeduplicatedAndHonorsProtectedApps() throws {
        let old = try app("旧版", version: "1.0.0")
        let source = try app("安装源", version: "1.0.0")
        let folder = applications.appendingPathComponent("Archive")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try app("不递归查找", version: "1.0.0", parent: folder)
        let result = finder(protected: [source]).scan(roots: [applications], additionalApps: [old])
        XCTAssertEqual(result.map { $0.url.lastPathComponent }, ["旧版.app"])
        XCTAssertThrowsError(try finder(protected: [source]).inspect(source))
    }
    // Catches following an app alias/symlink or metadata/executable links into other folders.
    func testRejectsSymbolicLinksAndMalformedBundles() throws {
        let old = try app("旧版", version: "1.0.0")
        let alias = applications.appendingPathComponent("链接.app")
        try fm.createSymbolicLink(at: alias, withDestinationURL: old)
        XCTAssertThrowsError(try finder().inspect(alias))
        let malformed = try app("损坏", version: "1.0.0")
        try fm.removeItem(at: malformed.appendingPathComponent("Contents/MacOS/TokenfieldMac"))
        XCTAssertThrowsError(try finder().inspect(malformed))
        let linked = try app("链接元数据", version: "1.0.0")
        let info = linked.appendingPathComponent("Contents/Info.plist")
        try fm.removeItem(at: info)
        try fm.createSymbolicLink(at: info, withDestinationURL: old.appendingPathComponent("Contents/Info.plist"))
        XCTAssertThrowsError(try finder().inspect(linked))
    }
    // Catches deleting the selected path after its contents or app identity were replaced.
    func testRechecksVersionAndFileIdentityImmediatelyBeforeTrash() throws {
        let old = try app("旧版", version: "1.0.0")
        let found = try finder().inspect(old)
        XCTAssertNoThrow(try uninstaller(finder()).validate(found))
        try plist(old, version: "1.1.4", build: "7")
        XCTAssertThrowsError(try uninstaller(finder()).validate(found))
        XCTAssertThrowsError(try uninstaller(finder()).trash(found))
        XCTAssertTrue(fm.fileExists(atPath: old.path))
        try fm.removeItem(at: old)
        try app("旧版", version: "1.0.0")
        XCTAssertThrowsError(try uninstaller(finder()).validate(found))
        XCTAssertThrowsError(try uninstaller(finder()).trash(found))
        XCTAssertTrue(fm.fileExists(atPath: old.path))
    }
    // Catches removing a folder containing user records rather than just the validated .app.
    func testTrashMovesOnlyAppAndPreservesUserData() throws {
        let old = try app("旧版", version: "1.0.0")
        let data = fixture.appendingPathComponent("Library/Application Support/Tokenfield/data.json")
        try fm.createDirectory(at: data.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep-my-records".utf8).write(to: data)
        let found = try finder().inspect(old)
        let result = try uninstaller(finder()).trash(found)
        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: result.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertEqual(try String(contentsOf: data), "keep-my-records")
    }
    // Catches swallowing a failed Trash operation or reporting success when nothing moved.
    func testTrashFailureIsReportedAndLeavesAppInPlace() throws {
        let old = try app("旧版", version: "1.0.0")
        let found = try finder().inspect(old)
        let remover = OldAppUninstaller(finder: finder()) { _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try remover.trash(found))
        XCTAssertTrue(fm.fileExists(atPath: old.path))
    }
}
