import XCTest
@testable import TokenfieldCore

final class CodexLogReaderTests: XCTestCase {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions/2033/05/18"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func file(_ root: URL, _ id: String = "one") -> URL { root.appendingPathComponent("sessions/2033/05/18/rollout-\(id).jsonl") }
    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
    private let header = #"{"type":"session_meta","payload":{"id":"one","cwd":"/tmp/project"}}"# + "\n"
    private let start = #"{"timestamp":"2033-05-18T03:33:20Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"# + "\n"
    private let finish = #"{"timestamp":"2033-05-18T03:33:21Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}"# + "\n"
    private let now = Date(timeIntervalSince1970: 2_000_000_002)

    func testAppendAndSplitUTF8AreReadOnlyAndNotDuplicatedOnRefresh() async throws {
        let root = try folder(), url = file(root)
        try Data((header + start).utf8).write(to: url)
        try Data((#"{"id":"one","thread_name":"真实任务标题","updated_at":"2033-05-18T03:33:20Z"}"# + "\n").utf8).write(to: root.appendingPathComponent("session_index.jsonl"))
        let reader = CodexLogReader(rootURL: root)
        let first = try await reader.refresh(now: now)
        XCTAssertEqual(first.sessions.first?.title, "真实任务标题")
        XCTAssertEqual(first.sessions.first?.phase(at: now), .running)
        let model = Data((#"{"timestamp":"2033-05-18T03:33:20Z","type":"turn_context","payload":{"model":"模型甲"}}"# + "\n").utf8)
        let split = model.firstIndex(of: 0xE6) ?? model.count / 2
        try append(model.prefix(split + 1), to: url)
        _ = try await reader.refresh(now: now)
        try append(model.dropFirst(split + 1) + Data(finish.utf8), to: url)
        let original = try Data(contentsOf: url)
        let second = try await reader.refresh(now: now)
        XCTAssertEqual(second.sessions.first?.model, "模型甲")
        XCTAssertEqual(second.sessions.first?.phase(at: now), .completed)
        let repeated = try await reader.refresh(now: now)
        XCTAssertEqual(repeated.sessions, second.sessions)
        XCTAssertLessThanOrEqual(repeated.bytesRead, 512, "Unchanged logs must not be reread in full.")
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testPartialFinalLineIsConsumedOnlyAfterNewline() async throws {
        let root = try folder(), url = file(root)
        try Data((header + start + String(finish.dropLast())).utf8).write(to: url)
        let reader = CodexLogReader(rootURL: root)
        let first = try await reader.refresh(now: now)
        XCTAssertEqual(first.sessions.first?.phase(at: now), .running)
        try append(Data("\n".utf8), to: url)
        let second = try await reader.refresh(now: now)
        XCTAssertEqual(second.sessions.first?.phase(at: now), .completed)
    }

    func testTruncateAndAtomicReplacementResetOldSessionState() async throws {
        let root = try folder(), url = file(root)
        try Data((header + start + finish).utf8).write(to: url)
        let reader = CodexLogReader(rootURL: root)
        _ = try await reader.refresh(now: now)
        try Data((header + start).utf8).write(to: url)
        let truncated = try await reader.refresh(now: now)
        XCTAssertEqual(truncated.sessions.first?.phase(at: now), .running)
        let replacement = header.replacingOccurrences(of: "one", with: "replacement") + start + finish
        try Data(replacement.utf8).write(to: url, options: .atomic)
        let changed = try await reader.refresh(now: now)
        XCTAssertEqual(changed.sessions.map(\.id), ["replacement"])
        XCTAssertEqual(changed.sessions.first?.phase(at: now), .completed)
    }

    func testSymlinkOutsideSelectedDirectoryIsNeverRead() async throws {
        let root = try folder(), outside = try folder()
        try Data((header + start).utf8).write(to: file(outside))
        try FileManager.default.createSymbolicLink(at: file(root), withDestinationURL: file(outside))
        let result = try await CodexLogReader(rootURL: root).refresh(now: now)
        XCTAssertTrue(result.sessions.isEmpty)
    }

    func testLargeLogUsesBoundedTailAndRecoversAfterOversizedLine() async throws {
        let root = try folder(), url = file(root)
        var data = Data(header.utf8)
        data.append(Data(repeating: 65, count: 3_000_000)); data.append(10)
        data.append(Data(start.utf8))
        try data.write(to: url)
        let result = try await CodexLogReader(rootURL: root).refresh(now: now)
        XCTAssertEqual(result.sessions.first?.id, "one")
        XCTAssertEqual(result.sessions.first?.phase(at: now), .running)
        XCTAssertLessThan(result.bytesRead, 800_000)
    }

    func testNewSessionsAreDiscoveredAndDeletedFilesDisappear() async throws {
        let root = try folder()
        let reader = CodexLogReader(rootURL: root)
        let empty = try await reader.refresh(now: now)
        XCTAssertTrue(empty.sessions.isEmpty)
        try Data((header + start).utf8).write(to: file(root))
        let discovered = try await reader.refresh(now: now.addingTimeInterval(6))
        XCTAssertEqual(discovered.sessions.count, 1)
        try FileManager.default.removeItem(at: file(root))
        let removed = try await reader.refresh(now: now.addingTimeInterval(12))
        XCTAssertTrue(removed.sessions.isEmpty)
    }

    func testShortMetadataDoesNotForceFullHeadAndTailBudgets() async throws {
        let root = try folder(), url = file(root)
        var data = Data(header.utf8)
        data.append(Data(repeating: 65, count: 500_000)); data.append(10)
        data.append(Data(start.utf8))
        try data.write(to: url)
        let result = try await CodexLogReader(rootURL: root).refresh(now: now)
        XCTAssertEqual(result.sessions.first?.phase(at: now), .running)
        XCTAssertLessThan(result.bytesRead, 200_000, "Initial work should depend on the recent tail and actual metadata length, not the entire log.")
    }

    func testRevokedDirectoryAccessIsAnErrorInsteadOfHealthyEmptyData() async throws {
        let root = try folder(), sessions = root.appendingPathComponent("sessions")
        try Data((header + start).utf8).write(to: file(root))
        let reader = CodexLogReader(rootURL: root)
        _ = try await reader.refresh(now: now)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: sessions.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessions.path) }
        do {
            _ = try await reader.refresh(now: now.addingTimeInterval(6))
            XCTFail("An unreadable sessions directory must not be reported as a connected empty account.")
        } catch { XCTAssertTrue(error is CocoaError) }
    }
}
