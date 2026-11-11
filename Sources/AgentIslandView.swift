import SwiftUI

/// Each CLI owns its own surface. The camera gap and side alignment containers stay transparent.
struct AgentIslandsView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let bounds = CGRect(x: 0, y: 0, width: model.closedWidth, height: model.closedHeight)
        let frames = model.presentedAgentIslandFrames(in: bounds)
        let center = model.centerIslandFrame(in: bounds)
        ZStack(alignment: .topLeading) {
            if !model.hasPhysicalNotch {
                let width = model.centeredAgentKind != nil && model.phase == .closed ? model.closedWidth : center.width
                Capsule().fill(.black)
                    .frame(width: width, height: model.notchHeight)
                    .position(x: bounds.midX, y: model.notchHeight / 2)
                    .allowsHitTesting(false)
                    .motion(Motion.island, value: width, reduce: reduceMotion)
                    .opacity(model.optionConcealed ? 0 : 1)
                    .animation(reduceMotion ? nil : Motion.timed(.easeInOut(duration: 0.14).delay(model.optionConcealed ? 0.36 : 0)), value: model.optionConcealed)
            }
            ForEach(model.closedIslandKinds) { kind in
                let frame = frames.first { $0.kind == kind }!.frame
                let expanded = model.phase == .preview && (model.previewAgent == kind || model.centeredAgentKind == kind)
                AgentIslandPill(model: model, kind: kind, size: frame.size)
                    .position(x: model.optionConcealed ? bounds.midX : frame.midX, y: bounds.height - frame.midY)
                    .motion(Motion.island, value: frame, reduce: reduceMotion)
                    .animation(reduceMotion ? nil : Motion.timed(.spring(response: 0.34, dampingFraction: 0.9).delay(model.optionConcealed ? 0 : 0.12)), value: model.optionConcealed)
                    .animation(reduceMotion ? nil : Motion.timed(.easeOut(duration: 0.08).delay(model.optionConcealed ? 0.28 : 0.1))) { content in
                        content.opacity(model.optionConcealed ? 0 : 1)
                    }
                    .opacity(expanded ? 0 : 1)
                    .animation(reduceMotion ? nil : Motion.timed(.easeOut(duration: 0.1)), value: expanded)
                    .allowsHitTesting(!expanded)
            }
            // The original center remains a separate control over the shared surface.
            Button { model.openPriorityOrTerminal() } label: {
                Color.clear
                    .frame(width: center.width, height: center.height)
                    .contentShape(IslandShape(radius: model.hasPhysicalNotch ? 0 : center.height / 2))
            }
            .buttonStyle(.plain)
            .position(x: bounds.midX, y: model.notchHeight / 2)
            .help(L("작업 화면 열기", "Open workspace"))
            .accessibilityLabel(L("작업 화면 열기", "Open workspace"))
            .allowsHitTesting(!model.optionConcealed)
            .accessibilityHidden(model.optionConcealed)
        }
        .frame(width: bounds.width, height: bounds.height)
        .motion(Motion.island, value: model.centeredAgentKind, reduce: reduceMotion)
    }
}

private struct AgentIslandPill: View {
    let model: AppModel
    let kind: AgentKind
    let size: CGSize
    private var working: [TerminalSession] { model.notchShowsWorking ? model.workingNotchSessions.filter { $0.kind == kind } : [] }
    private var quota: IdleUsage? { model.quietNotchShowsUsage ? model.idleUsages.first { $0.agent == kind } : nil }
    private var notice: NotchBanner? { model.banner?.kind == kind ? model.banner : nil }
    private var usesCenterSurface: Bool { model.centeredAgentKind == kind && notice == nil }
    var body: some View {
        Button { model.openAgentIsland(kind) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let since = working.compactMap(\.workingSince).min() {
                        AgentLogo(kind: kind, size: 14)
                        if usesCenterSurface { Spacer(minLength: model.centerIslandWidth) }
                        HStack(spacing: 6) {
                            NotchStatusView(status: .working(since: since))
                            if model.notchShowsWorkCount, working.count > 1 {
                                Text("\(working.count)").font(.caption2.monospacedDigit())
                            }
                        }
                    } else if let quota {
                        UsageBadge(usage: quota, showsNumber: !usesCenterSurface)
                        if usesCenterSurface {
                            Spacer(minLength: model.centerIslandWidth)
                            UsageBadge.percent(quota)
                        }
                    } else {
                        AgentLogo(kind: kind, size: 16)
                            .overlay(alignment: .topTrailing) {
                                if model.lastError != nil { Circle().fill(.orange).frame(width: 4, height: 4) }
                            }
                    }
                }.frame(maxWidth: .infinity, alignment: notice == nil ? .center : .leading)
                if let notice {
                    Text(notice.reason.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(notice.folder).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: size.width, height: size.height)
            .background {
                if !usesCenterSurface {
                    IslandShape(radius: notice == nil ? size.height / 2 : 18).fill(.black)
                }
            }
            .overlay {
                if !usesCenterSurface {
                    RoundedRectangle(cornerRadius: notice == nil ? size.height / 2 : 18, style: .continuous).stroke(Palette.line, lineWidth: 0.5)
                }
            }
            .contentShape(.rect(cornerRadius: notice == nil ? size.height / 2 : 18))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
        .help(kind.name + L(" 열기", " · Open"))
        .accessibilityLabel(kind.name + L(" 아일랜드 열기", " · Open agent island"))
    }
}

struct IslandGlassBackground: View {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black)
            } else if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular.tint(.black.opacity(0.22)), in: .rect(cornerRadius: radius))
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.22),
                        .init(color: .black.opacity(0.9), location: 0.48),
                        .init(color: .black.opacity(0.56), location: 1)
                    ], startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay {
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.04), location: 0.25),
                        .init(color: .white.opacity(0.24), location: 0.75),
                        .init(color: .white.opacity(0.10), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A provider island expands into its own sessions and quota, rather than the whole dashboard.
struct AgentPreview: View {
    let model: AppModel
    let kind: AgentKind
    private var sessions: [TerminalSession] { model.sessions.filter { !$0.ended && $0.kind == kind } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentLogo(kind: kind, size: 18)
                Text(kind.name).font(.headline)
                Spacer()
                Button { model.openAgentIsland(kind) } label: {
                    Image(systemName: "arrow.up.right").frame(width: 24, height: 24)
                }.buttonStyle(.plain).accessibilityLabel(kind.name + L(" 열기", " · Open"))
            }
            if sessions.isEmpty {
                Text(L("실행 중인 세션이 없습니다.", "No active sessions.")).foregroundStyle(Palette.muted).font(.subheadline)
            } else {
                ForEach(sessions.prefix(3)) { session in
                    Button { model.openSession(id: session.id) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(session.isWorking ? Palette.mint : Palette.muted).frame(width: 6, height: 6)
                            Text(session.displayTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption)
                        }.padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            AgentUsageDetails(model: model, kind: kind)
            RecentActivitiesView(model: model, agent: kind, limit: 2)
        }
    }
}
