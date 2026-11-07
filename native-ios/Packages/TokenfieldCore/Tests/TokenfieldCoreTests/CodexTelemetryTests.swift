import XCTest
@testable import TokenfieldCore

final class CodexTelemetryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func event(_ type: String, _ payload: String, seconds: Int = 0) -> Data {
        let time = ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(seconds)))
        return Data("{\"timestamp\":\"\(time)\",\"type\":\"\(type)\",\"payload\":\(payload)}".utf8)
    }

    func testRealQuotaWindowIsIndependentOfTokensAndExpiresToUnknown() {
        var log = CodexTelemetryAccumulator(fileID: "fixture")
        log.consume(line: event("event_msg", #"{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":1000,"output_tokens":80,"reasoning_output_tokens":20,"total_tokens":1280}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":90,"window_minutes":300,"resets_at":2000000060},"secondary":{"used_percent":14,"window_minutes":10080,"resets_at":2000003600},"plan_type":"plus"}}"#))
        let snapshot = log.snapshot()
        XCTAssertEqual(snapshot.tokens?.total, 1280)
        XCTAssertEqual(snapshot.tokens?.cachedInput, 1000)
        XCTAssertEqual(snapshot.quota?.primary?.remainingPercent(at: now), 10)
        XCTAssertEqual(snapshot.quota?.secondary?.remainingPercent(at: now), 86)
        XCTAssertNil(snapshot.quota?.primary?.remainingPercent(at: now.addingTimeInterval(60)))
        XCTAssertEqual(snapshot.quota?.reportedAt, now)
    }

    func testUnknownInvalidAndNullDataNeverBecomeZeroQuota() {
        var log = CodexTelemetryAccumulator(fileID: "fixture")
        log.consume(line: event("event_msg", #"{"type":"token_count","info":null,"rate_limits":null}"#))
        XCTAssertNil(log.snapshot().tokens)
        XCTAssertNil(log.snapshot().quota)
        log.consume(line: event("event_msg", #"{"type":"token_count","info":{"total_token_usage":{"input_tokens":-1}},"rate_limits":{"primary":{"used_percent":101,"window_minutes":300,"resets_at":2000000060}}}"#))
        XCTAssertNil(log.snapshot().quota)
        XCTAssertNil(log.snapshot().tokens?.input)
    }

    func testOldTurnCompletionCannotFinishNewTurnAndQuietIsNotCompletion() {
        var log = CodexTelemetryAccumulator(fileID: "fixture")
        log.consume(line: event("event_msg", #"{"type":"task_started","turn_id":"first"}"#))
        log.consume(line: event("event_msg", #"{"type":"task_started","turn_id":"second"}"#, seconds: 5))
        log.consume(line: event("event_msg", #"{"type":"task_complete","turn_id":"first"}"#, seconds: 6))
        XCTAssertEqual(log.snapshot().phase(at: now.addingTimeInterval(10)), .running)
        XCTAssertEqual(log.snapshot().phase(at: now.addingTimeInterval(200)), .quiet)
        log.consume(line: event("event_msg", #"{"type":"task_complete","turn_id":"second"}"#, seconds: 210))
        log.consume(line: event("event_msg", #"{"type":"token_count","info":null,"rate_limits":null}"#, seconds: 211))
        XCTAssertEqual(log.snapshot().phase(at: now.addingTimeInterval(212)), .completed)
    }

    func testMalformedAndFutureEventsDoNotPreventLaterActivity() {
        var log = CodexTelemetryAccumulator(fileID: "fixture")
        log.consume(line: Data("{broken".utf8))
        log.consume(line: event("future_record", #"{"new_field":"ignored"}"#))
        log.consume(line: event("event_msg", #"{"type":"task_started","turn_id":"live"}"#, seconds: 1))
        log.consume(line: event("event_msg", #"{"type":"turn_aborted","turn_id":"live"}"#, seconds: 2))
        XCTAssertEqual(log.snapshot().phase(at: now.addingTimeInterval(3)), .stopped)
        XCTAssertEqual(log.malformedLineCount, 1)
    }

    func testMetadataAndActivityNeverRetainPromptReasoningOrCommandOutput() throws {
        var log = CodexTelemetryAccumulator(fileID: "fixture")
        log.consume(line: event("session_meta", #"{"id":"safe-id","cwd":"/tmp/project","originator":"Codex Desktop","base_instructions":"PRIVATE_PROMPT"}"#))
        log.consume(line: event("event_msg", #"{"type":"item_completed","item":{"type":"CommandExecution","id":"cmd","command":"SECRET_COMMAND","aggregated_output":"PRIVATE_OUTPUT","status":"completed","exit_code":0}}"#, seconds: 1))
        log.consume(line: event("response_item", #"{"type":"reasoning","summary":[{"text":"PRIVATE_REASONING"}]}"#, seconds: 2))
        let snapshot = log.snapshot(title: "Project task")
        XCTAssertEqual(snapshot.id, "safe-id")
        XCTAssertEqual(snapshot.title, "Project task")
        XCTAssertEqual(snapshot.activities.first?.kind, .command)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for secret in ["PRIVATE_PROMPT", "SECRET_COMMAND", "PRIVATE_OUTPUT", "PRIVATE_REASONING"] {
            XCTAssertFalse(encoded.contains(secret))
        }
    }

    func testTokenOnlyUpdateDoesNotEraseLastKnownQuota() {
        var log = CodexTelemetryAccumulator(fileID: "fixture")
        log.consume(line: event("event_msg", #"{"type":"token_count","rate_limits":{"primary":{"used_percent":0,"window_minutes":300,"resets_at":2000000060}}}"#))
        log.consume(line: event("event_msg", #"{"type":"token_count","info":{"total_token_usage":{"total_tokens":999}},"rate_limits":null}"#, seconds: 1))
        XCTAssertEqual(log.snapshot().quota?.primary?.remainingPercent(at: now), 100)
        XCTAssertEqual(log.snapshot().quota?.reportedAt, now)
        XCTAssertEqual(log.snapshot().tokens?.total, 999)
    }

    func testOtherLimitBucketCannotOverwriteCodexQuota() {
        var log = CodexTelemetryAccumulator(fileID: "fixture")
        log.consume(line: event("event_msg", #"{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":90,"window_minutes":300,"resets_at":2000000060}}}"#))
        log.consume(line: event("event_msg", #"{"type":"token_count","rate_limits":{"limit_id":"codex_other","primary":{"used_percent":10,"window_minutes":60,"resets_at":2000000060}}}"#, seconds: 1))
        XCTAssertEqual(log.snapshot().quota?.limitID, "codex")
        XCTAssertEqual(log.snapshot().quota?.primary?.usedPercent, 90)
        XCTAssertEqual(log.snapshot().quota?.reportedAt, now)
    }
}
