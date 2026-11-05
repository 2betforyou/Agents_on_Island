import Foundation
import Observation

struct AgentTokenDay: Identifiable, Sendable {
    let date: Date
    let tokens: Int64
    var id: Date { date }
}
struct AgentTokenSummary: Sendable {
    let days: [AgentTokenDay]
    let filesRead: Int
    let skippedFiles: Int
    let meteredRecords: Int
    var total: Int64 { days.reduce(0) { $0 + $1.tokens } }
    var today: Int64 { days.last?.tokens ?? 0 }
}

/// Local CLI token counters only. Conversation text is neither retained nor sent anywhere.
enum AgentTokenHistory {
    static func scan(kind: AgentKind, root: URL? = nil, now: Date = Date()) -> AgentTokenSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        let base = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(kind == .claude ? ".claude/projects" : ".codex/sessions")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        var daily: [Date: Int64] = [:]
        var messages: [String: (Date, Int64)] = [:]
        var seen: Set<String> = []
        var filesRead = 0, skipped = 0, metered = 0
        let urls = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        for file in urls?.compactMap({ $0 as? URL }) ?? [] {
            if Task<Never, Never>.isCancelled { break }
            guard file.pathExtension == "jsonl" else { continue }
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if let modified = values?.contentModificationDate, modified < start { continue }
            guard (values?.fileSize ?? 0) <= 128 * 1024 * 1024,
                  let handle = try? FileHandle(forReadingFrom: file) else { skipped += 1; continue }
            defer { try? handle.close() }
            filesRead += 1
            var session = file.path, previous: Int64 = 0
            var pending = Data()
            func consume(_ line: Data) {
                guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
                if record["type"] as? String == "session_meta", let payload = record["payload"] as? [String: Any] {
                    session = payload["id"] as? String ?? session
                    return
                }
                guard let stamp = record["timestamp"] as? String,
                      let date = formatter.date(from: stamp) ?? fallback.date(from: stamp) else { return }
                if kind == .claude {
                    guard record["type"] as? String == "assistant",
                          let message = record["message"] as? [String: Any],
                          let id = message["id"] as? String, let usage = message["usage"] as? [String: Any] else { return }
                    let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].reduce(Int64.zero) {
                        $0 + max(0, (usage[$1] as? NSNumber)?.int64Value ?? 0)
                    }
                    metered += 1
                    let key = "\(record["sessionId"] as? String ?? session):\(id)"
                    if tokens > (messages[key]?.1 ?? -1) { messages[key] = (date, tokens) }
                } else {
                    guard record["type"] as? String == "event_msg",
                          let payload = record["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                          let info = payload["info"] as? [String: Any],
                          let usage = info["total_token_usage"] as? [String: Any],
                          let total = (usage["total_tokens"] as? NSNumber)?.int64Value, total >= 0 else { return }
                    metered += 1
                    let delta = total >= previous ? total - previous : total
                    previous = total
                    guard date >= start, date <= now, seen.insert("\(session):\(stamp):\(total)").inserted else { return }
                    daily[calendar.startOfDay(for: date), default: 0] += delta
                }
            }
            do {
                while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    pending.append(chunk)
                    while let end = pending.firstIndex(of: 10) {
                        consume(pending.subdata(in: pending.startIndex..<end))
                        pending.removeSubrange(pending.startIndex...end)
                    }
                }
                if !pending.isEmpty { consume(pending) }
            } catch { skipped += 1 }
        }
        for (date, tokens) in messages.values where date >= start && date <= now {
            daily[calendar.startOfDay(for: date), default: 0] += tokens
        }
        let days = (0..<30).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return AgentTokenDay(date: date, tokens: daily[date] ?? 0)
        }
        return AgentTokenSummary(days: days, filesRead: filesRead, skippedFiles: skipped, meteredRecords: metered)
    }
}

@MainActor @Observable
final class AgentTokenHistoryService {
    private(set) var summaries: [AgentKind: AgentTokenSummary] = [:]
    private var fetched: [AgentKind: Date] = [:]
    private var loading: Set<AgentKind> = []
    @ObservationIgnored private let scan: @Sendable (AgentKind) -> AgentTokenSummary
    /// `scan` is replaceable so screenshots and tests never read the real CLI logs.
    init(scan: @escaping @Sendable (AgentKind) -> AgentTokenSummary = { AgentTokenHistory.scan(kind: $0) }) {
        self.scan = scan
    }
    func load(_ kind: AgentKind) async {
        guard kind == .claude || kind == .codex, !loading.contains(kind),
              Date().timeIntervalSince(fetched[kind] ?? .distantPast) > 300 else { return }
        loading.insert(kind)
        let scan = self.scan
        let result = await Task.detached(priority: .utility) { scan(kind) }.value
        summaries[kind] = result
        fetched[kind] = Date()
        loading.remove(kind)
    }
}
