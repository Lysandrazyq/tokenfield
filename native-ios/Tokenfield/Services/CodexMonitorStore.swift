#if os(macOS)
import AppKit
import Darwin
import Foundation
import Observation
import TokenfieldCore

@MainActor @Observable
final class CodexMonitorStore {
    private(set) var snapshot: CodexMonitorSnapshot? { didSet { publishQuotaContext() } }
    private(set) var directory: URL? { didSet { publishQuotaContext() } }
    var issue: String? { connectionIssue ?? refreshIssue }
    private var connectionIssue: String? { didSet { publishQuotaContext() } }
    private var refreshIssue: String? { didSet { publishQuotaContext() } }
    private(set) var isRefreshing = false
    private(set) var isConnecting = false { didSet { publishQuotaContext() } }
    private(set) var automaticallyConnected = false
    @ObservationIgnored private var reader: CodexLogReader?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var ownsScope = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let resolveBookmark: @Sendable (Data) async throws -> URL
    @ObservationIgnored private let discoverDirectory: @Sendable () async throws -> URL?
    @ObservationIgnored private let createBookmark: @Sendable (URL) throws -> Data
    private let bookmarkKey = "codex.monitor.readonly-folder.v1"
    private let automaticDisabledKey = "codex.monitor.automatic-disabled.v1"
    private enum ConnectionOrigin { case automatic, restored, selected }
    @ObservationIgnored var onQuotaContextChange: ((CodexQuotaSnapshot?, URL?, Bool) -> Void)?

    private func publishQuotaContext() {
        // A replacement assigns directory and snapshot separately. Never publish the old
        // snapshot under the new source while that transaction is still in progress.
        onQuotaContextChange?(isConnecting ? nil : snapshot?.quota, directory, directory != nil && issue == nil && !isConnecting)
    }

    init(defaults: UserDefaults = .standard, resolver: (@Sendable (Data) async throws -> URL)? = nil,
         discovery: (@Sendable () async throws -> URL?)? = nil,
         bookmarkCreator: (@Sendable (URL) throws -> Data)? = nil) {
        self.defaults = defaults
        createBookmark = bookmarkCreator ?? { url in
            try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        discoverDirectory = discovery ?? {
            await Task.detached(priority: .utility) {
                // Foundation also redirects a named current user's home into the sandbox container.
                guard let home = CodexMonitorStore.userHomeDirectory() else { return nil }
                let root = home.appendingPathComponent(".codex", isDirectory: true)
                let sessions = root.appendingPathComponent("sessions", isDirectory: true)
                for url in [root, sessions] {
                    if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return nil }
                }
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: sessions.path, isDirectory: &directory), directory.boolValue else { return nil }
                return root
            }.value
        }
        resolveBookmark = resolver ?? { data in
            try await Task.detached(priority: .utility) {
                var stale = false
                return try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
            }.value
        }
    }

    nonisolated private static func userHomeDirectory() -> URL? {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        return buffer.withUnsafeMutableBufferPointer { bytes in
            guard getpwuid_r(getuid(), &entry, bytes.baseAddress, bytes.count, &result) == 0,
                  result != nil, let path = entry.pw_dir else { return nil }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
    }

    func connectAutomatically() async {
        restored = true
        defaults.set(false, forKey: automaticDisabledKey)
        clearConnection(removeBookmark: true)
        await discoverAndConnect(ticket: generation)
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        guard !defaults.bool(forKey: automaticDisabledKey) else { return }
        let ticket = generation
        guard let data = defaults.data(forKey: bookmarkKey) else {
            await discoverAndConnect(ticket: ticket)
            return
        }
        isConnecting = true
        do {
            let url = try await resolveBookmark(data)
            guard acceptsResult(ticket: ticket) else { return }
            await connect(to: url, origin: .restored)
        } catch {
            guard acceptsResult(ticket: ticket) else { return }
            isConnecting = false
            connectionIssue = "日志目录授权已失效，请重新选择 Codex 数据目录。"
        }
    }

    private func discoverAndConnect(ticket: Int) async {
        isConnecting = true
        do {
            let url = try await discoverDirectory()
            guard acceptsResult(ticket: ticket) else { return }
            guard let url else {
                isConnecting = false
                connectionIssue = "未检测到 Codex 日志。先在 Codex 中运行一个任务，再点「自动连接」；自定义位置可点「选择目录」。"
                return
            }
            await connect(to: url, origin: .automatic)
        } catch {
            guard acceptsResult(ticket: ticket) else { return }
            isConnecting = false
            connectionIssue = "自动检测暂不可用，请点击「选择目录」完成一次授权。\n\(error.localizedDescription)"
        }
    }

    private func acceptsResult(ticket: Int) -> Bool {
        guard ticket == generation else { return false }
        guard !Task.isCancelled else {
            isConnecting = false
            restored = false
            return false
        }
        return true
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "连接本机 Codex"
        panel.message = "选择 Codex 数据目录（通常为 ~/.codex）或其中的 sessions 文件夹。仅提取任务状态与用量，不需要 API Key。可按 ⌘⇧G 输入路径。"
        panel.prompt = "连接此目录"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        if let home = Self.userHomeDirectory() {
            panel.directoryURL = home.appendingPathComponent(".codex", isDirectory: true)
        }
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.connectSelectedDirectory(url) }
        }
    }

    func connectSelectedDirectory(_ url: URL) async { await connect(to: url, origin: .selected) }

    private func connect(to url: URL, origin: ConnectionOrigin) async {
        // Keep the current reader, scope and bookmark until the replacement is fully ready.
        generation += 1
        let ticket = generation
        pollTask?.cancel(); pollTask = nil
        isRefreshing = false
        isConnecting = true
        connectionIssue = nil
        let scoped = origin != .automatic && url.startAccessingSecurityScopedResource()
        let candidate = CodexLogReader(rootURL: url)
        do {
            let next = try await candidate.refresh()
            guard acceptsResult(ticket: ticket) else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                if ticket == generation { startPolling() }
                return
            }
            let bookmark = origin == .selected ? try createBookmark(url) : nil
            guard acceptsResult(ticket: ticket) else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                if ticket == generation { startPolling() }
                return
            }
            if ownsScope { scopedURL?.stopAccessingSecurityScopedResource() }
            if let bookmark { defaults.set(bookmark, forKey: bookmarkKey) }
            defaults.set(false, forKey: automaticDisabledKey)
            reader = candidate; directory = url; scopedURL = scoped ? url : nil; ownsScope = scoped
            automaticallyConnected = origin != .selected
            snapshot = next; connectionIssue = nil; refreshIssue = nil; isConnecting = false
            startPolling()
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            guard acceptsResult(ticket: ticket) else {
                if ticket == generation { startPolling() }
                return
            }
            isConnecting = false
            connectionIssue = directory != nil
                ? "新目录连接失败，仍使用原来的日志目录。\n\(error.localizedDescription)"
                : origin == .automatic
                ? "自动连接暂不可用。请确认 Codex 已运行任务，或点击「选择目录」完成一次授权。\n\(error.localizedDescription)"
                : "无法连接日志目录：\(error.localizedDescription)"
            startPolling()
        }
    }

    private func startPolling() {
        guard reader != nil, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(self.foreground ? 1 : 5)) }
                catch { return }
            }
        }
    }

    func refresh() async {
        guard !isRefreshing, let reader else { return }
        let ticket = generation
        isRefreshing = true
        do {
            let next = try await reader.refresh()
            guard ticket == generation else { return }
            snapshot = next; refreshIssue = nil; isRefreshing = false
        } catch {
            guard ticket == generation else { return }
            snapshot = nil; isRefreshing = false
            if !(error is CancellationError) { refreshIssue = "读取暂停，请检查目录授权或重新连接。\n\(error.localizedDescription)" }
        }
    }

    func setForeground(_ value: Bool) { foreground = value }

    func disconnect() {
        defaults.set(true, forKey: automaticDisabledKey)
        clearConnection(removeBookmark: true)
    }

    private func clearConnection(removeBookmark: Bool) {
        generation += 1
        pollTask?.cancel(); pollTask = nil
        reader = nil; snapshot = nil; directory = nil; connectionIssue = nil; refreshIssue = nil
        isRefreshing = false; isConnecting = false; automaticallyConnected = false
        if ownsScope { scopedURL?.stopAccessingSecurityScopedResource() }
        scopedURL = nil; ownsScope = false
        if removeBookmark { defaults.removeObject(forKey: bookmarkKey) }
    }

    deinit { pollTask?.cancel(); if ownsScope { scopedURL?.stopAccessingSecurityScopedResource() } }
}
#endif
