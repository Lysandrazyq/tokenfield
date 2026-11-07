import Foundation

public struct CodexMonitorSnapshot: Equatable, Sendable {
    public let sessions: [CodexSessionSnapshot]
    public let quota: CodexQuotaSnapshot?
    public let scannedAt: Date
    public let warnings: Int
    public let bytesRead: Int
}

public enum CodexLogIssue: Error, LocalizedError {
    case missingSessions
    public var errorDescription: String? { "所选目录里没有 sessions 文件夹。请选择 Codex 数据目录（通常为 ~/.codex），或其中的 sessions 文件夹。" }
}

/// Bounded, passive reader. No authentication files or transcript text are retained.
public actor CodexLogReader {
    private struct Cursor {
        var accumulator: CodexTelemetryAccumulator
        var offset: UInt64 = 0
        var inode: UInt64 = 0
        var identity = Data()
        var pending = Data()
        var droppingLine = false
        var oversizedLines = 0
    }
    private let root: URL
    private let sessionsRoot: URL
    private var cursors: [URL: Cursor] = [:]
    private var files: [URL] = []
    private var lastDiscovery: Date?
    private var titles: [String: String] = [:]
    private var indexModified: Date?
    private var discoveryWarnings = 0
    private let maximumLine = 262_144
    private let initialTail = 131_072
    private let incrementalLimit = 1_048_576

    public init(rootURL: URL) {
        root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        sessionsRoot = root.lastPathComponent == "sessions" ? root : root.appendingPathComponent("sessions", isDirectory: true)
    }

    public func refresh(now: Date = Date()) throws -> CodexMonitorSnapshot {
        try Task.checkCancellation()
        let manager = FileManager.default
        var directory: ObjCBool = false
        guard manager.fileExists(atPath: sessionsRoot.path, isDirectory: &directory), directory.boolValue,
              allowed(sessionsRoot) else { throw CodexLogIssue.missingSessions }
        var bytesRead = 0
        if lastDiscovery == nil || abs(now.timeIntervalSince(lastDiscovery!)) >= 5 {
            files = try discover()
            lastDiscovery = now
            let keep = Set(files)
            cursors = cursors.filter { keep.contains($0.key) }
            bytesRead += readTitles()
        }
        var inaccessible = 0
        for url in files {
            try Task.checkCancellation()
            do {
                guard allowed(url), !isLink(url), manager.fileExists(atPath: url.path) else {
                    cursors.removeValue(forKey: url); continue
                }
                bytesRead += try read(url)
            } catch is CancellationError { throw CancellationError() }
            catch { cursors.removeValue(forKey: url); inaccessible += 1 }
        }
        if inaccessible > 0 && cursors.isEmpty { throw CocoaError(.fileReadNoPermission) }
        let sessions = cursors.values.map { cursor -> CodexSessionSnapshot in
            let id = cursor.accumulator.snapshot().id
            return cursor.accumulator.snapshot(title: titles[id])
        }.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
        let quota = sessions.compactMap(\.quota).filter { $0.limitID == nil || $0.limitID == "codex" }
            .max { $0.reportedAt < $1.reportedAt }
        let warnings = discoveryWarnings + inaccessible + cursors.values.reduce(0) { $0 + $1.oversizedLines + $1.accumulator.malformedLineCount }
        return CodexMonitorSnapshot(sessions: sessions, quota: quota, scannedAt: now, warnings: warnings, bytesRead: bytesRead)
    }

    private func allowed(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == root.path || path.hasPrefix(root.path + "/")
    }
    private func isLink(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true }

    private func discover() throws -> [URL] {
        // The supported log layout is sessions/YYYY/MM/DD/*.jsonl. Do not walk arbitrary trees.
        var candidates: [(URL, Date)] = []
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let rootItems = try manager.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: keys)
        var failures: [Error] = []
        func children(_ folder: URL) -> [URL] {
            if folder == sessionsRoot { return rootItems }
            do { return try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) }
            catch { failures.append(error); return [] }
        }
        func numericFolders(_ folder: URL, digits: Int) -> [URL] {
            children(folder).filter { url in
                let name = url.lastPathComponent
                return name.count == digits && name.allSatisfy(\.isNumber) && !isLink(url) && allowed(url)
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        for year in numericFolders(sessionsRoot, digits: 4).prefix(5) {
            for month in numericFolders(year, digits: 2).prefix(12) {
                for day in numericFolders(month, digits: 2).prefix(31) {
                    for url in children(day) where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
                        guard !isLink(url), allowed(url),
                              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]), values.isRegularFile == true else { continue }
                        candidates.append((url, values.contentModificationDate ?? .distantPast))
                    }
                }
            }
        }
        if candidates.isEmpty, let error = failures.first { throw error }
        discoveryWarnings = failures.count
        return candidates.sorted { $0.1 > $1.1 }.prefix(30).map(\.0)
    }

    private func readTitles() -> Int {
        guard root.lastPathComponent != "sessions" else { return 0 }
        let url = root.appendingPathComponent("session_index.jsonl")
        guard allowed(url), !isLink(url), let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate, modified != indexModified,
              let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        let size = values.fileSize ?? 0, start = max(0, size - incrementalLimit)
        try? handle.seek(toOffset: UInt64(start))
        guard let data = try? handle.read(upToCount: incrementalLimit) else { return 0 }
        var next: [String: String] = [:]
        for (index, line) in data.split(separator: 10).enumerated() {
            if start > 0 && index == 0 { continue }
            guard line.count <= maximumLine,
                  let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = row["id"] as? String, let title = row["thread_name"] as? String else { continue }
            next[String(id.prefix(160))] = String(title.prefix(160))
        }
        titles = next; indexModified = modified
        return data.count
    }

    private func read(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let identity = try handle.read(upToCount: 256) ?? Data()
        var readCount = identity.count
        var cursor = cursors[url]
        if cursor == nil || cursor!.inode != inode || size < cursor!.offset || cursor!.identity != identity {
            cursor = Cursor(accumulator: CodexTelemetryAccumulator(fileID: url.deletingPathExtension().lastPathComponent), inode: inode, identity: identity)
            try handle.seek(toOffset: 0)
            var header = Data()
            while header.count < maximumLine && !header.contains(10) {
                let chunk = try handle.read(upToCount: min(8192, maximumLine - header.count)) ?? Data()
                readCount += chunk.count
                if chunk.isEmpty { break }
                header.append(chunk)
            }
            if let newline = header.firstIndex(of: 10) {
                let first = Data(header[..<newline])
                if let row = try? JSONSerialization.jsonObject(with: first) as? [String: Any], row["type"] as? String == "session_meta" {
                    cursor!.accumulator.consume(line: first)
                }
            }
            cursor!.offset = size > UInt64(initialTail) ? size - UInt64(initialTail) : 0
            if cursor!.offset > 0 {
                try handle.seek(toOffset: cursor!.offset - 1)
                let preceding = try handle.read(upToCount: 1)
                readCount += preceding?.count ?? 0
                cursor!.droppingLine = preceding?.first != 10
            }
        }
        guard var next = cursor else { return readCount }
        try handle.seek(toOffset: next.offset)
        let count = min(incrementalLimit, Int(min(UInt64(incrementalLimit), size - next.offset)))
        if count > 0 {
            let data = try handle.read(upToCount: count) ?? Data()
            readCount += data.count
            ingest(data, into: &next)
            next.offset += UInt64(data.count)
        }
        cursors[url] = next
        return readCount
    }

    private func ingest(_ data: Data, into cursor: inout Cursor) {
        let segments = data.split(separator: 10, omittingEmptySubsequences: false)
        for (index, segment) in segments.enumerated() {
            let ended = index < segments.count - 1
            if cursor.droppingLine {
                if ended { cursor.droppingLine = false }
                continue
            }
            if cursor.pending.count + segment.count > maximumLine {
                cursor.pending.removeAll(keepingCapacity: false)
                cursor.oversizedLines += 1
                cursor.droppingLine = !ended
            } else {
                cursor.pending.append(contentsOf: segment)
                if ended {
                    cursor.accumulator.consume(line: cursor.pending)
                    cursor.pending.removeAll(keepingCapacity: true)
                }
            }
        }
    }
}
