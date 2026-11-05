import SwiftUI
import Charts

struct AgentUsageDetails: View {
    let model: AppModel
    let kind: AgentKind
    private var snapshot: UsageSnapshot? { kind == .claude ? model.claudeUsage.snapshot : model.usage.snapshot }
    private var color: Color { kind == .claude ? Palette.claude : .white }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("사용량", "Usage")).font(.caption.weight(.semibold))
                    if let plan = snapshot?.plan { Text(plan.capitalized).font(.caption).foregroundStyle(Palette.muted) }
                    Spacer()
                    UsageReadingStatus(agent: kind, snapshot: snapshot,
                                       loading: kind == .codex && model.usage.isLoading,
                                       error: kind == .codex ? model.usage.error : nil,
                                       refresh: { refresh() }, iconOnly: true)
                    RefreshButton(help: L("사용량 갱신", "Refresh usage")) { refresh() }
                }
                if let snapshot {
                    ForEach(snapshot.windows.sorted { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }) { window in
                        VStack(spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(window.title).font(.caption.weight(.medium))
                                Text("\(Int(window.remaining))% " + L("남음", "left")).font(.caption.monospacedDigit().weight(.semibold))
                                Spacer(minLength: 4)
                                Text(window.resetLabel(now: context.date)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            GeometryReader { geometry in
                                Capsule().fill(.white.opacity(0.1))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(window.remaining <= 20 ? Palette.low : color)
                                            .frame(width: geometry.size.width * window.remaining / 100)
                                    }
                            }.frame(height: 4).accessibilityHidden(true)
                        }
                    }
                } else {
                    Text(kind == .claude ? L("첫 응답 후 한도가 표시됩니다.", "Limits appear after the first reply.") : L("한도 정보가 아직 없습니다.", "No limit reading yet."))
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                if let summary = model.tokenHistory.summaries[kind] {
                    if summary.meteredRecords > 0 {
                        HStack {
                            tokenStat(L("오늘 토큰", "Tokens today"), value: summary.today)
                            Spacer()
                            tokenStat(L("30일 토큰", "30-day tokens"), value: summary.total)
                        }
                        Chart(summary.days) { day in
                            BarMark(x: .value(L("날짜", "Day"), day.date, unit: .day), y: .value(L("토큰", "Tokens"), day.tokens))
                                .foregroundStyle(color.opacity(0.7)).cornerRadius(1)
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 38)
                        .accessibilityLabel(L("최근 30일의 일별 로컬 토큰 사용량", "Daily local token usage over 30 days"))
                        Text(summary.skippedFiles > 0 ? L("로컬 기록 일부 · 읽지 못한 파일 \(summary.skippedFiles)개", "Partial local history · \(summary.skippedFiles) unread files") : L("이 Mac의 CLI 기록 · 비용 데이터 미제공", "CLI history on this Mac · cost data unavailable"))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    } else {
                        Text(L("아직 읽을 수 있는 로컬 토큰 기록이 없습니다.", "No readable local token history yet."))
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .task(id: kind) { await model.tokenHistory.load(kind) }
    }
    private func tokenStat(_ title: String, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.muted)
            Text(model.language.compactNumber(value))
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }
    private func refresh() {
        if kind == .claude { model.claudeUsage.reload() } else { model.usage.refresh() }
    }
}
