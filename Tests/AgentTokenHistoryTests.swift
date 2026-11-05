import Foundation
import Testing
@testable import NotchAgent

struct AgentTokenHistoryTests {
    @Test("Codex cumulative counters become daily deltas and copied logs do not double count")
    func codexDeltas() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = [
            #"{"type":"session_meta","payload":{"id":"same-session"}}"#,
            #"{"timestamp":"2026-10-01T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}"#,
            #"{"timestamp":"2026-11-05T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":160}}}}"#,
            #"{"timestamp":"2026-11-05T12:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":160}}}}"#
        ].joined(separator: "\n")
        try lines.write(to: root.appendingPathComponent("one.jsonl"), atomically: true, encoding: .utf8)
        try lines.write(to: root.appendingPathComponent("copy.jsonl"), atomically: true, encoding: .utf8)
        let now = ISO8601DateFormatter().date(from: "2026-11-05T13:00:00Z")!
        let summary = AgentTokenHistory.scan(kind: .codex, root: root, now: now)
        #expect(summary.total == 60)
        #expect(summary.today == 60)
        #expect(summary.days.count == 30)
    }
    @Test("Claude streaming records count a message once, including cache input")
    func claudeMessages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = [
            #"{"timestamp":"2026-11-05T12:00:00Z","type":"assistant","sessionId":"s","message":{"id":"m","usage":{"input_tokens":10,"output_tokens":2,"cache_read_input_tokens":20,"cache_creation_input_tokens":5}}}"#,
            #"{"timestamp":"2026-11-05T12:00:01Z","type":"assistant","sessionId":"s","message":{"id":"m","usage":{"input_tokens":10,"output_tokens":8,"cache_read_input_tokens":20,"cache_creation_input_tokens":5}}}"#,
            #"{"type":"user","message":{"content":"private text must never become metrics"}}"#
        ].joined(separator: "\n")
        try lines.write(to: root.appendingPathComponent("one.jsonl"), atomically: true, encoding: .utf8)
        let now = ISO8601DateFormatter().date(from: "2026-11-05T13:00:00Z")!
        #expect(AgentTokenHistory.scan(kind: .claude, root: root, now: now).total == 43)
    }
    @Test("A missing CLI directory produces no fabricated readings")
    func missingDirectory() {
        let result = AgentTokenHistory.scan(kind: .codex, root: URL(fileURLWithPath: "/tmp/" + UUID().uuidString))
        #expect(result.filesRead == 0)
        #expect(result.total == 0)
    }
}
