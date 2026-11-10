import AppKit
import SwiftUI

enum Palette {
    /// The accent the user picked (mint by default); the name is kept from the original design.
    static var mint: Color { Accent.current.color }
    static let surface = Color(white: 0.03)
    static let muted = Color(white: 0.62)
    static let line = Color.white.opacity(0.09)
    // Each agent's brand color, used for its usage bars.
    static let codex = Color(red: 0x49 / 255, green: 0xA3 / 255, blue: 0xB0 / 255)   // #49A3B0
    static let claude = Color(red: 0xCC / 255, green: 0x7C / 255, blue: 0x5E / 255)  // #CC7C5E
    static let gemini = Color(red: 0x47 / 255, green: 0x96 / 255, blue: 0xE3 / 255)  // Gemini blue
    /// Low remaining quota. Red rather than orange so it never reads as Claude's color.
    static let low = Color(red: 1.0, green: 0.27, blue: 0.23)  // system red
    /// A session asks for the user (approval, question).
    static let attention = Color(red: 1.0, green: 0.78, blue: 0.32)
    /// A session finished its work.
    static let done = Color(red: 0.30, green: 0.85, blue: 0.45)
    static func color(for reason: AttentionReason) -> Color {
        switch reason {
        case .finished: done
        case .bell: attention
        case .exited: muted
        case .failed: low
        }
    }
}

/// One motion language for the whole app, tuned to feel like the Dynamic Island: the island
/// itself expands without overshoot; smaller controls keep their existing response.
enum Motion {
    // Let the documentation renderer sample the same curves offline.
    static let renderTimeScale: Double = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHAGENT_SLOW_DEMO"] == "1" { return 32 }
        #endif
        return 1
    }()

    static func timed(_ animation: Animation) -> Animation {
        renderTimeScale == 1 ? animation : animation.speed(1 / renderTimeScale)
    }

    /// Opening, closing and resizing the island.
    static let island = timed(.spring(response: 0.46, dampingFraction: 0.88))
    /// Selections, chips, tabs, counters, bars.
    static let snappy = timed(.spring(response: 0.3, dampingFraction: 0.84))
    /// Content fading in once the island has made room for it.
    static let content = Animation.easeOut(duration: 0.26).delay(0.07)
}

extension View {
    /// Animates `value` changes with `animation`, or not at all when Reduce Motion is on.
    func motion<V: Equatable>(_ animation: Animation, value: V, reduce: Bool) -> some View {
        self.animation(reduce ? nil : animation, value: value)
    }
}

/// A detached continuous capsule, growing into a panel without edge-attached shoulders.
struct IslandShape: Shape {
    var radius: CGFloat = 24
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: radius, style: radius >= rect.height / 2 ? .circular : .continuous).path(in: rect)
    }
}

private struct PreviewHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct IslandView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabHighlight
    @State private var draggedTab: UUID?
    @State private var surfaceVisible = false
    private var width: CGFloat {
        model.islandWidth
    }
    private var height: CGFloat {
        model.islandHeight
    }
    private var surfaceSize: CGSize {
        if model.phase == .closed {
            // Collapsed, the surface waits where it will grow from: the hovered island, or the
            // center island (the notch itself on a notched display).
            return CGSize(width: model.previewAgent.map { model.agentIslandSize($0).width } ?? model.centerIslandWidth, height: model.notchHeight)
        }
        return CGSize(width: width, height: height)
    }
    var body: some View {
        ZStack(alignment: .top) {
            // Keep the same surface alive in every phase so its bounds interpolate rather
            // than inserting a full-sized background after the content has already changed.
            ZStack {
                IslandShape(radius: model.islandCornerRadius)
                    .fill(.black).opacity(model.phase == .preview ? 0 : 1)
                IslandGlassBackground(radius: model.islandCornerRadius)
                    .opacity(model.phase == .preview ? 1 : 0)
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            .clipShape(IslandShape(radius: model.islandCornerRadius))
            .offset(x: model.phase == .closed ? model.expansionOriginX : 0)
            .opacity(surfaceVisible ? 1 : 0)
            .allowsHitTesting(false)
            if model.phase == .closed {
                Color.clear
            } else {
                VStack(spacing: 0) {
                    // Only the actual camera housing stays clear in the menu-bar header.
                    if model.phase != .preview || model.agentPreviewKind == nil {
                        topRow.modifier(FolderDropTarget(model: model)).padding(.bottom, 10)
                    }
                    if let error = model.lastError {
                        errorBanner(error).padding(.bottom, 10).transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if model.phase == .preview { preview }
                    else if model.showsInlineSettings {
                        SettingsView(model: model, displayChanged: { model.layoutChanged?() })
                    }
                    else { terminalPanel }
                }
                .padding(.horizontal, model.phase == .preview && model.agentPreviewKind != nil ? 12 : 26)
                // Any preview opened from a side island starts below the menu-bar band, clear of the camera.
                .padding(.top, model.phase == .preview && model.previewAgent != nil ? model.notchHeight + 10 : 0)
                .padding(.bottom, model.phase == .terminal ? 8 : 12)
                // The preview is exactly as tall as its content (no dead space below the footer).
                .fixedSize(horizontal: false, vertical: model.phase == .preview)
                .background {
                    if model.phase == .preview {
                        GeometryReader { geo in
                            Color.clear.preference(key: PreviewHeightKey.self, value: geo.size.height)
                        }
                    }
                }
                .onPreferenceChange(PreviewHeightKey.self) { height in
                    guard height > 0 else { return }
                    if let agent = model.agentPreviewKind {
                        if abs(height - (model.agentPreviewHeights[agent] ?? 0)) > 0.5 {
                            model.agentPreviewHeights[agent] = height
                        }
                    } else if abs(height - model.previewContentHeight) > 0.5 { model.previewContentHeight = height }
                }
                .transition(.asymmetric(
                    insertion: .opacity.animation(reduceMotion ? nil : Motion.timed(.easeOut(duration: 0.16).delay(0.12))),
                    removal: .opacity.animation(reduceMotion ? nil : Motion.timed(.easeOut(duration: 0.08)))))
            }
        }
        .id(model.language)
        .frame(width: width, height: height, alignment: .top)
        .clipShape(IslandShape(radius: model.islandCornerRadius))
        .offset(x: model.islandOffsetX)
        .motion(Motion.island, value: surfaceSize, reduce: reduceMotion)
        .motion(Motion.island, value: model.phase, reduce: reduceMotion)
        .motion(Motion.island, value: model.banner, reduce: reduceMotion)
        .motion(Motion.island, value: model.closedLayout, reduce: reduceMotion)
        .motion(Motion.island, value: model.previewContentHeight, reduce: reduceMotion)
        .motion(Motion.island, value: model.agentPreviewHeights, reduce: reduceMotion)
        .motion(Motion.island, value: model.previewAgent, reduce: reduceMotion)
        .motion(Motion.snappy, value: model.lastError, reduce: reduceMotion)
        .padding(.top, IslandMetrics.shadowInset)
        .frame(width: model.panelWidth + 32, height: model.hostHeight + 32, alignment: .top)
        .overlay(alignment: .top) {
            compact.modifier(FolderDropTarget(model: model))
                .padding(.top, IslandMetrics.shadowInset)
                .opacity(model.phase == .terminal ? 0 : 1)
                .motion(Motion.island, value: model.phase, reduce: reduceMotion)
                .allowsHitTesting(model.phase != .terminal)
        }
        .foregroundStyle(.white)
        .tint(model.accent.color)
        .preferredColorScheme(.dark)
        .environment(\.locale, model.language.locale)
        .task(id: model.phase) {
            if model.phase != .closed { surfaceVisible = true; return }
            if !reduceMotion {
                do { try await Task.sleep(for: .seconds(0.46 * Motion.renderTimeScale)) } catch { return }
            }
            guard !Task.isCancelled, model.phase == .closed else { return }
            surfaceVisible = false
        }
    }
    private var compact: some View {
        AgentIslandsView(model: model)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { model.lastError = nil } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
            }
                .buttonStyle(.plain).help(L("닫기", "Dismiss")).accessibilityLabel(L("오류 메시지 닫기", "Dismiss error"))
        }
        .padding(10).background(Color.orange.opacity(0.14)).clipShape(.rect(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }
    /// Header inside the floating panel; no camera-shaped blank strip is needed.
    private var topRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                AppMark(size: 20)
                Text("Agents on Island").font(.headline).lineLimit(1).fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Nothing is drawn under the camera. Screens without a notch keep only a small gap.
            Color.clear.frame(width: model.hasPhysicalNotch ? model.physicalNotchWidth + 16 : 16)
            HStack(spacing: 8) {
                if model.phase == .preview {
                    Text(model.hotkey.label.uppercased()).font(.caption2.monospaced()).foregroundStyle(Palette.muted)
                }
                if model.showsInlineSettings {
                    Button { model.showTerminal?() } label: {
                        Label(L("작업으로 돌아가기", "Back to workspace"), systemImage: "arrow.left")
                            .font(.caption)
                    }.buttonStyle(QuietButton())
                } else {
                    Button { model.showSettings?() } label: { Image(systemName: "gearshape") }
                        .buttonStyle(QuietButton()).help(L("설정", "Settings")).accessibilityLabel(L("설정", "Settings"))
                }
                if model.phase == .terminal {
                    Button { model.collapse?() } label: { Image(systemName: "chevron.up") }.buttonStyle(QuietButton())
                        .help(L("접기 · \(model.hotkey.label)", "Close · \(model.hotkey.label)")).accessibilityLabel(L("노치 접기", "Close notch"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: max(32, model.notchHeight))
        .padding(.top, 6)
    }
    private var preview: some View {
        Group {
            if let agent = model.agentPreviewKind {
                AgentPreview(model: model, kind: agent)
            } else { dashboardPreview }
        }
    }
    private var dashboardPreview: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.previewHeadline)
                        .font(.title3.weight(.semibold))
                    Text(model.previewSubtitle)
                        .font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                Button { model.showTerminal?() } label: {
                    Label(model.visibleSessions.isEmpty ? L("시작하기", "Get Started") : L("터미널 열기", "Open Terminal"), systemImage: "arrow.up.right")
                }.buttonStyle(MintButton())
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(L("프로젝트", "Projects")).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                WorkspaceBar(model: model)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("바로 시작", "Start here")).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                QuickPromptField(model: model)
                HStack(spacing: 8) {
                    ForEach(AgentKind.allCases) { kind in
                        Button { model.launch(kind) } label: {
                            HStack(spacing: 6) {
                                if kind == .shell { Image(systemName: kind.symbol) } else { AgentLogo(kind: kind, size: 13) }
                                Text(kind == .claude ? "Claude" : kind.name)
                                Circle().fill(model.executable(for: kind) == nil ? Palette.muted : Palette.mint).frame(width: 4, height: 4)
                            }
                            .font(.caption.weight(.medium)).frame(maxWidth: .infinity)
                        }.buttonStyle(QuietButton())
                    }
                }
            }
            Divider().overlay(Palette.line)
            RecentActivitiesView(model: model)
            CompactUsageFooter(codex: model.usage, claude: model.claudeUsage, stacked: true)
        }
        .modifier(FolderDropTarget(model: model))
    }
    private var terminalPanel: some View {
        VStack(spacing: 8) {
            // Folders get the full width below the menu bar band.
            WorkspaceBar(model: model)
            tabs
            if let session = model.selected, model.visibleSessions.contains(where: { $0.id == session.id }) {
                    ZStack(alignment: .bottom) {
                        EmbeddedTerminal(session: session, appearance: model.appearance)
                            .id(session.id)
                            .padding(10)
                            .background(model.terminalTheme.backgroundColor)
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line) }
                        if session.ended {
                            HStack {
                                Image(systemName: session.exitCode == 0 ? "checkmark.circle" : "exclamationmark.circle")
                                Text(L("세션 종료", "End Session") + (session.exitCode.map { L(" · 코드 \($0)", " · code \($0)") } ?? ""))
                                Spacer()
                                Button(L("새 세션", "New Session")) { model.launch(session.kind) }.buttonStyle(QuietButton())
                            }.font(.caption).padding(12).background(Palette.surface).clipShape(.rect(cornerRadius: 10)).padding(8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transaction { $0.animation = nil }
            } else {
                launchPad
            }
            CompactUsageFooter(codex: model.usage, claude: model.claudeUsage)
        }
    }
    private var tabs: some View {
        HStack(spacing: 10) {
            Button { model.selectHome() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "house").foregroundStyle(model.selectedID == nil ? Palette.mint : Palette.muted)
                    Text(L("홈", "Home")).fontWeight(.semibold)
                }
                .font(.caption).padding(.horizontal, 10).padding(.vertical, 8)
                .background {
                    if model.selectedID == nil {
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1))
                            .matchedGeometryEffect(id: "selectedTab", in: tabHighlight)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("현재 프로젝트 홈 · ⌘1", "Current project home · ⌘1"))
            .accessibilityAddTraits(model.selectedID == nil ? .isSelected : [])
            if !model.visibleSessions.isEmpty {
                Rectangle().fill(Palette.line).frame(width: 1, height: 18)
            }
            FadingHScroll(target: model.selectedID) {
                HStack(spacing: 6) {
                    ForEach(model.visibleSessions) { session in
                        HStack(spacing: 7) {
                            Button { model.select(session) } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(session.attention.map(Palette.color(for:)) ?? (session.isRunning ? Palette.mint : Palette.muted)).frame(width: 5, height: 5)
                                    if session.kind == .shell {
                                        Image(systemName: "terminal").foregroundStyle(Palette.muted)
                                    } else { AgentLogo(kind: session.kind, size: 12) }
                                    Text(session.displayTitle).fontWeight(.semibold).lineLimit(1)
                                        .truncationMode(.middle).frame(maxWidth: 220)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .simultaneousGesture(TapGesture(count: 2).onEnded { model.renameSession(session) })
                            .help("\(session.kind.name) · \(session.displayTitle)\n\(session.initialDirectory.path)\n" + L("더블클릭하여 이름 변경", "Double-click to rename"))
                            .accessibilityLabel("\(session.kind.name), \(session.displayTitle), \(session.initialDirectory.lastPathComponent)" + (session.ended ? L(", 종료됨", ", ended") : ""))
                            .accessibilityAddTraits(model.selectedID == session.id ? .isSelected : [])
                            Button { model.closeSession(session) } label: {
                                Image(systemName: "xmark").font(.system(size: 9)).frame(width: 16, height: 16).contentShape(Rectangle())
                            }
                                .buttonStyle(.plain).help(L("세션 종료", "End Session")).accessibilityLabel(L("\(session.kind.name) 세션 종료", "End \(session.kind.name) session"))
                        }
                        .font(.caption).padding(.horizontal, 10).padding(.vertical, 8)
                        .background {
                            // One highlight that slides from tab to tab.
                            if model.selectedID == session.id {
                                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1))
                                    .matchedGeometryEffect(id: "selectedTab", in: tabHighlight)
                            }
                        }
                        .id(session.id)
                        .contextMenu {
                            Button(L("이름 변경…", "Rename…")) { model.renameSession(session) }
                            if session.customTitle != nil {
                                Button(L("터미널 제목 사용", "Use Terminal Title")) { model.setSessionName(session, name: nil) }
                            }
                        }
                        .opacity(draggedTab == session.id ? 0.55 : 1)
                        .reorderable(session.id, dragging: $draggedTab) { model.moveSession($0, onto: $1) }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .motion(Motion.snappy, value: model.selectedID, reduce: reduceMotion)
                .motion(Motion.snappy, value: model.visibleSessions.map(\.id), reduce: reduceMotion)
            }
            if model.selectedID != nil { newSessionButtons }
        }.frame(height: 32)
    }
    /// New sessions in the current folder, right beside its tabs; one button folds them away.
    private var newSessionButtons: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : Motion.snappy) { model.showsNewSessionButtons.toggle() }
            } label: {
                Image(systemName: model.showsNewSessionButtons ? "chevron.right" : "plus")
                    .font(.caption.weight(.semibold)).frame(width: 12)
            }
            .buttonStyle(QuietButton())
            .help(model.showsNewSessionButtons ? L("새 세션 버튼 숨기기", "Hide new session buttons") : L("새 세션 버튼 보기", "Show new session buttons"))
            .accessibilityLabel(model.showsNewSessionButtons ? L("새 세션 버튼 숨기기", "Hide new session buttons") : L("새 세션 버튼 보기", "Show new session buttons"))
            if model.showsNewSessionButtons {
                agentButtons.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
    private var agentButtons: some View {
        HStack(spacing: 6) {
            ForEach(AgentKind.allCases) { kind in
                let available = model.executable(for: kind) != nil
                Button { model.launch(kind) } label: {
                    HStack(spacing: 5) {
                        if kind == .shell { Image(systemName: kind.symbol) } else { AgentLogo(kind: kind, size: 12) }
                        Text(kind == .claude ? "Claude" : kind == .gemini ? "Gemini" : kind.name)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(available ? Color.white : Palette.muted)
                }
                .buttonStyle(QuietButton())
                .help(L("새 \(kind.name) 세션", "New \(kind.name) session") + (available ? "" : L(" · 실행 파일을 찾을 수 없음", " · executable not found")))
                .accessibilityLabel(L("새 \(kind.name) 세션", "New \(kind.name) session"))
            }
        }
    }
    private var launchPad: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                TimelineView(.periodic(from: .now, by: 3600)) { timeline in
                    let copy = model.showsTemporaryChats
                        ? (title: "A little room.\nFor a quick thought.", detail: L("프로젝트와 분리된 채팅. 앱 종료 후 복원되지 않습니다.\nCLI 자체 기록과 임시 파일은 남을 수 있습니다.", "A chat outside your projects. Not restored after quitting.\nThe CLI may retain history and temporary files."))
                        : SessionHomeCopy.message(at: timeline.date)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(copy.title).font(.largeTitle.weight(.semibold)).tracking(-0.9)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(copy.detail).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.projectActivityEnabled && !model.showsTemporaryChats {
                    ProjectActivityHeatmap(activity: model.projectActivity, path: model.workspacePath, now: Date(),
                                           importing: model.projectImportRunning, onImport: { model.importPastActivity() })
                        .frame(width: 290) // 12 square cells, 11 gaps, and the card's side padding.
                }
            }
            if !model.showsTemporaryChats {
                RepositoryStatusRow(service: model.repositoryStatus, path: model.workspacePath)
            }
            HStack(spacing: 10) {
                ForEach(AgentKind.allCases) { kind in
                    Button { model.launch(kind) } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                if kind == .shell {
                                    Image(systemName: kind.symbol).font(.title3).foregroundStyle(Palette.mint)
                                        .frame(height: 22) // same row height as the agent logos
                                } else {
                                    AgentLogo(kind: kind, size: 22)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Palette.muted)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.name).font(.headline)
                                Text(model.executable(for: kind) != nil ? L("실행 가능", "Ready to run") : L("경로 설정 필요", "Set path in Settings"))
                                    .font(.caption2).foregroundStyle(Palette.muted)
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface).clipShape(.rect(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line) }
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .task(id: model.workspacePath + "-" + String(model.repositoryStatus.githubEnabled) + "-" + String(model.showsTemporaryChats)) {
            guard !model.showsTemporaryChats else { return }
            let path = model.workspacePath
            repeat {
                await model.repositoryStatus.refresh(path: path)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            } while !Task.isCancelled
        }
    }
}

struct UsageStrip: View {
    let service: UsageService
    let compact: Bool
    var showsAgent = false
    var body: some View {
        Group {
            if !service.enabled {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis").foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Codex 사용량 연결", "Connect Codex usage")).font(.caption.weight(.semibold))
                        if !compact { Text(L("기존 CLI 로그인으로 남은 한도를 확인합니다.", "Shows remaining limits using your existing CLI sign-in.")).font(.caption2).foregroundStyle(Palette.muted) }
                    }
                    Spacer()
                    Button(L("연결", "Connect")) { service.setEnabled(true) }.buttonStyle(QuietButton())
                }
            } else if let snapshot = service.snapshot {
                UsageWindowsRow(agent: showsAgent ? .codex : nil, tint: Palette.codex, snapshot: snapshot, compact: compact,
                                warning: service.error != nil || snapshot.isStale ? L("마지막 성공한 조회 값입니다. ", "Last successful reading. ") + (service.error ?? L("갱신이 필요합니다.", "Needs a refresh.")) : nil,
                                loading: service.isLoading, readingError: service.error, refresh: { service.refresh() }) {
                    refreshButton
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: service.isLoading ? "arrow.triangle.2.circlepath" : "exclamationmark.circle").foregroundStyle(Palette.muted)
                    Text(service.isLoading ? L("Codex 사용량을 확인하는 중…", "Checking Codex usage…") : service.error ?? L("사용량을 연결하세요", "Connect usage"))
                        .font(.caption).foregroundStyle(Palette.muted).lineLimit(compact ? 1 : 2)
                        .help(service.error ?? "")
                    Spacer()
                    refreshButton
                }
            }
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 6 : 14)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: compact ? 9 : 12))
    }
    private var refreshButton: some View {
        RefreshButton(help: L("Codex 사용량 새로고침", "Refresh Codex usage")) { service.refresh() }.disabled(service.isLoading)
    }
}

/// Same look as the Codex strip. Shown only after Claude usage is turned on in Settings.
struct ClaudeUsageStrip: View {
    let service: ClaudeUsageService
    let compact: Bool
    var body: some View {
        Group {
            if let snapshot = service.snapshot {
                UsageWindowsRow(agent: .claude, updatedAt: snapshot.fetchedAt, tint: Palette.claude, snapshot: snapshot, compact: compact,
                                warning: Date().timeIntervalSince(snapshot.fetchedAt) > 3600
                                    ? L("Claude 세션에서 마지막으로 받은 값입니다(\(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))). 새 응답이 오면 갱신됩니다.", "Last value from a Claude session (\(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))). Updates with the next response.") : nil) {
                    RefreshButton(help: ClaudeUsageService.refreshHelp) { service.reload() }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.muted)
                    Text(L("Claude 사용량은 Agents on Island에서 연 Claude 세션의 첫 응답 후 표시됩니다.", "Claude usage appears after the first response in a Claude session opened in Agents on Island."))
                        .font(.caption).foregroundStyle(Palette.muted).lineLimit(compact ? 1 : 2)
                    Spacer()
                    RefreshButton(help: ClaudeUsageService.refreshHelp) { service.reload() }
                }
            }
        }
        .padding(compact ? 10 : 14)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: compact ? 9 : 12))
    }
}

/// Terminal footer when Claude usage is on: every agent on one line.
struct CombinedUsageStrip: View {
    let codex: UsageService
    let claude: ClaudeUsageService
    var body: some View {
        HStack(spacing: 18) {
            codexSegment
            Rectangle().fill(Palette.line).frame(width: 1, height: 14)
            claudeSegment
            Spacer(minLength: 0)
            RefreshButton(help: L("Codex 사용량을 다시 조회합니다. ", "Re-queries Codex usage. ") + ClaudeUsageService.refreshHelp) { codex.refresh(); claude.reload() }
                .disabled(codex.isLoading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: 9))
    }
    @ViewBuilder private var codexSegment: some View {
        if let snapshot = codex.snapshot, codex.enabled {
            UsageWindowsRow(agent: .codex, tint: Palette.codex, snapshot: snapshot, compact: true,
                            warning: codex.error != nil || snapshot.isStale ? L("마지막 성공한 조회 값입니다. ", "Last successful reading. ") + (codex.error ?? L("갱신이 필요합니다.", "Needs a refresh.")) : nil,
                            loading: codex.isLoading, readingError: codex.error, refresh: { codex.refresh() }, fills: false) { EmptyView() }
        } else {
            HStack(spacing: 8) {
                AgentBadge(kind: .codex, stacked: false)
                if !codex.enabled {
                    Button(L("연결", "Connect")) { codex.setEnabled(true) }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.codex)
                } else {
                    Text(codex.isLoading ? L("확인하는 중…", "Checking…") : codex.error ?? L("사용량 없음", "No usage"))
                        .font(.caption).foregroundStyle(Palette.muted).lineLimit(1).help(codex.error ?? "")
                }
            }
        }
    }
    @ViewBuilder private var claudeSegment: some View {
        if let snapshot = claude.snapshot {
            UsageWindowsRow(agent: .claude, tint: Palette.claude, snapshot: snapshot, compact: true,
                            warning: Date().timeIntervalSince(snapshot.fetchedAt) > 3600
                                ? L("Claude 세션에서 마지막으로 받은 값입니다. 새 응답이 오면 갱신됩니다.", "Last value from a Claude session. Updates with the next response.") : nil,
                            refresh: { claude.reload() }, fills: false) { EmptyView() }
        } else {
            HStack(spacing: 8) {
                AgentBadge(kind: .claude, stacked: false)
                Text(L("첫 응답 후 표시", "After first reply")).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    .help(L("Agents on Island에서 연 Claude 세션이 첫 응답을 받으면 표시됩니다 (Pro/Max).", "Shown once a Claude session opened in Agents on Island gets its first response (Pro/Max)."))
            }
        }
    }
}

/// The original Codex quota row, shared so Claude looks identical.
struct UsageWindowsRow<Trailing: View>: View {
    let agent: AgentKind?
    var updatedAt: Date? = nil
    let tint: Color
    let snapshot: UsageSnapshot
    let compact: Bool
    let warning: String?
    var loading = false
    var readingError: String? = nil
    var refresh: (() -> Void)? = nil
    var fills = true
    @ViewBuilder let trailing: () -> Trailing
    var body: some View {
        HStack(spacing: compact ? 22 : 16) {
            VStack(alignment: .leading, spacing: 3) {
                if let agent { AgentBadge(kind: agent, stacked: !compact, updatedAt: updatedAt) }
                UsageReadingStatus(agent: agent ?? .codex, snapshot: snapshot, loading: loading, error: readingError, refresh: refresh)
            }
            ForEach(snapshot.windows) { window in
                if compact {
                    HStack(spacing: 7) {
                        Text(window.title).foregroundStyle(Palette.muted)
                        Text(L("\(Int(window.remaining))% 남음", "\(Int(window.remaining))% left")).foregroundStyle(window.remaining <= 20 ? Palette.low : tint)
                            .contentTransition(.numericText(value: window.remaining)).animation(Motion.snappy, value: window.remaining)
                    }.font(.caption.monospacedDigit())
                        .help(window.resetLabel())
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(window.title).foregroundStyle(Palette.muted)
                            Spacer()
                            Text(L("\(Int(window.remaining))% 남음", "\(Int(window.remaining))% left")).monospacedDigit().fontWeight(.semibold)
                                .contentTransition(.numericText(value: window.remaining)).animation(Motion.snappy, value: window.remaining)
                        }.font(.caption)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(window.remaining <= 20 ? Palette.low : tint)
                                    .frame(width: geo.size.width * window.remaining / 100)
                                    .animation(Motion.snappy, value: window.remaining)
                            }
                        }.frame(height: 4)
                        Text(window.resetLabel()).font(.caption2).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity)
                }
            }
            if compact && fills { Spacer(minLength: 0) }
            if let warning {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange).help(warning)
            }
            trailing()
        }
    }
}

/// Preview footer. The folder name opens the same folder chips as the terminal header, so
/// switching folders looks and behaves identically in both places.
struct PreviewFolderFooter: View {
    @Bindable var model: AppModel
    @State private var choosing: Bool
    init(model: AppModel, choosing: Bool = false) {
        self.model = model
        _choosing = State(initialValue: choosing)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if choosing {
                HStack(spacing: 6) {
                    WorkspaceBar(model: model)
                    Button { set(false) } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                        .buttonStyle(QuietButton())
                        .help(L("닫기", "Close")).accessibilityLabel(L("폴더 선택 닫기", "Close folder picker"))
                }
                .font(.subheadline)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                HStack {
                    Button { set(true) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text(model.workspaceName).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("작업 폴더 전환", "Switch folder"))
                    .accessibilityLabel(L("작업 폴더 \(model.workspaceName), 전환", "Folder \(model.workspaceName), switch"))
                    Spacer()
                    Text(L("클릭해서 열기 · \(model.hotkey.label)", "Click to open · \(model.hotkey.label)"))
                }
                .font(.caption2).foregroundStyle(Palette.muted)
                .transition(.opacity)
            }
        }
        // Picking a folder switches it and folds the chips back into the folder name.
        .onChange(of: model.workspacePath) { _, _ in set(false) }
    }
    private func set(_ value: Bool) {
        withAnimation(reduceMotion ? nil : Motion.snappy) { choosing = value }
    }
}

/// Work folders, Orca-sidebar style but inline: switch folders, see which ones have agents
/// running, add and manage folders. The active chip looks like the original folder button.
struct WorkspaceBar: View {
    @Bindable var model: AppModel
    @Namespace private var chipHighlight
    @State private var draggedFolder: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let labels = Workspaces.labels(model.workspaces)
        FadingHScroll(target: model.showsTemporaryChats ? "__temporary__" : model.workspacePath) {
            HStack(spacing: 4) {
                if model.showsTemporaryChats || model.sessions.contains(where: \.isTemporary) {
                    Button { model.selectTemporaryChats() } label: {
                        Label(L("임시 채팅", "Temporary chats"), systemImage: "clock")
                    }
                    .buttonStyle(WorkspaceChipStyle(active: model.showsTemporaryChats, highlight: chipHighlight))
                    .id("__temporary__")
                }
                ForEach(model.workspaces) { workspace in
                    chip(workspace, label: labels[workspace.path] ?? workspace.name).id(workspace.path)
                        .opacity(draggedFolder == workspace.path ? 0.55 : 1)
                        .reorderable(workspace.path, dragging: $draggedFolder) { model.moveWorkspace($0, onto: $1) }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                Button { model.addWorkspace() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(QuietButton()).help(L("작업 폴더 추가", "Add folder")).accessibilityLabel(L("작업 폴더 추가", "Add folder"))
                    .padding(.leading, 2)
            }
            .motion(Motion.snappy, value: model.workspacePath, reduce: reduceMotion)
            .motion(Motion.snappy, value: model.workspaces, reduce: reduceMotion)
        }
    }
    private func chip(_ workspace: SavedWorkspace, label: String) -> some View {
        let active = workspace.path == model.workspacePath && !model.showsTemporaryChats
        let running = model.runningCount(in: workspace.path)
        let exists = workspace.exists
        let branch = Workspaces.gitBranch(at: workspace.path)
        return Button { model.activateWorkspace(workspace.path) } label: {
            HStack(spacing: 6) {
                Image(systemName: !exists ? "questionmark.folder" : Worktree.isLinked(workspace.path) ? "arrow.triangle.branch" : "folder")
                Text(label).lineLimit(1)
                if let reason = model.attention(in: workspace.path) {
                    Circle().fill(Palette.color(for: reason)).frame(width: 6, height: 6).accessibilityHidden(true)
                }
                if running > 0 {
                    Text("\(running)").font(.caption2.monospacedDigit().weight(.bold))
                        .contentTransition(.numericText(value: Double(running)))
                        .foregroundStyle(.black).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Palette.mint))
                }
            }
            .foregroundStyle(active ? Color.white : exists ? Palette.muted : Color.orange)
        }
        .buttonStyle(WorkspaceChipStyle(active: active, highlight: chipHighlight))
        .help(workspace.path + (branch.map { " · " + $0 } ?? "") + (exists ? "" : L(" · 폴더를 찾을 수 없음", " · folder not found")))
        .accessibilityLabel(L("작업 폴더 \(label)", "Folder \(label)") + (running > 0 ? L(", 실행 중인 세션 \(running)개", ", \(sessionCount(running, "running"))") : "") + (exists ? "" : L(", 폴더 없음", ", missing")))
        .accessibilityAddTraits(active ? .isSelected : [])
        .contextMenu {
            ForEach(AgentKind.allCases) { kind in
                Button { model.activateWorkspace(workspace.path); model.launch(kind) } label: {
                    Label { Text(L("여기서 새 \(kind.name) 세션", "New \(kind.name) Session Here")) } icon: { AgentLogo.menuIcon(kind) }
                }
            }
            Divider()
            Button(L("Finder에서 보기", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace.path)]) }
                .disabled(!exists)
            Button(L("경로 복사", "Copy Path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(workspace.path, forType: .string)
            }
            if exists, Worktree.isLinked(workspace.path) {
                Divider()
                Button(L("worktree 제거…", "Remove Worktree…")) { model.removeWorktree(workspace.path) }
            } else if exists, Worktree.isRepository(workspace.path) {
                Divider()
                Button(L("새 worktree 만들기…", "New Worktree…")) { model.createWorktree(from: workspace.path) }
            }
            Divider()
            Button(L("목록에서 제거", "Remove from List")) { model.removeWorkspace(workspace.path) }
                .disabled(model.workspaces.count < 2)
        }
    }
}

/// Ask an agent straight from the preview. The preview never takes keyboard focus on hover;
/// clicking this field does, and Enter starts the agent with the text in the current folder.
struct QuickPromptField: View {
    @Bindable var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool
    private let agents: [AgentKind] = [.codex, .claude, .gemini]
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(agents, id: \.self) { kind in
                    Button { model.quickAgent = kind } label: {
                        AgentLogo(kind: kind, size: 13)
                            .padding(6)
                            .background(model.quickAgent == kind ? Color.white.opacity(0.1) : .clear)
                            .clipShape(.rect(cornerRadius: 6))
                            .opacity(model.executable(for: kind) == nil ? 0.35 : 1)
                            // The whole square is clickable, not just the logo's thin strokes.
                            .contentShape(.rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(kind.name + (model.executable(for: kind) == nil ? L(" · 실행 파일을 찾을 수 없음", " · executable not found") : ""))
                    .accessibilityLabel(kind.name).accessibilityAddTraits(model.quickAgent == kind ? .isSelected : [])
                }
            }
            Rectangle().fill(Palette.line).frame(width: 1, height: 16)
            Button { model.quickChatIsTemporary.toggle() } label: {
                Label(L("임시", "Temp"), systemImage: "clock")
                    .font(.caption).foregroundStyle(model.quickChatIsTemporary ? Palette.mint : Palette.muted)
                    .padding(5).background(model.quickChatIsTemporary ? Color.white.opacity(0.08) : .clear)
                    .clipShape(.rect(cornerRadius: 6))
            }.buttonStyle(.plain)
                .accessibilityAddTraits(model.quickChatIsTemporary ? .isSelected : [])
                .help(L("프로젝트와 분리된 임시 폴더에서 시작. 앱 복원·활동 보관 제외. CLI 자체 기록은 남을 수 있습니다.", "Start in a separate temporary folder. Not restored or saved in app activity. The CLI may retain its own history."))
            ZStack(alignment: .leading) {
                TextField("", text: $text, prompt: Text(L("\(model.quickAgent.name)에게 바로 요청…", "Ask \(model.quickAgent.name)…")).foregroundStyle(Palette.muted))
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand { text = ""; model.cancelQuickPrompt() }
                    .allowsHitTesting(model.quickPromptActive)
                if !model.quickPromptActive {
                    // The preview panel cannot take focus by itself; the first click asks for it.
                    Color.clear.contentShape(Rectangle()).onTapGesture { model.beginQuickPrompt?() }
                }
            }
            Image(systemName: "return").font(.caption).foregroundStyle(text.isEmpty ? Palette.muted : Palette.mint)
        }
        .font(.subheadline)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? Palette.mint.opacity(0.5) : Palette.line) }
        .onChange(of: model.quickPromptActive) { _, active in focused = active; if !active { text = "" } }
        .accessibilityElement(children: .contain)
    }
    private func submit() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        if model.submitQuickPrompt(prompt) { text = "" }
    }
}

/// Right wing of the closed notch. One item, chosen by `NotchStatus.resolve`.
struct NotchStatusView: View {
    let status: NotchStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            switch status {
            case .attention(let reason):
                Image(systemName: Self.symbol(for: reason))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.color(for: reason))
                    .symbolEffect(.bounce, value: reason)
                    .phaseAnimator(reason == .bell && !reduceMotion ? [1.0, 0.55] : [1.0]) { content, opacity in
                        content.opacity(opacity) // a request "breathes" until it is seen
                    } animation: { _ in .easeInOut(duration: 1.1) }
                    .accessibilityLabel(reason.message)
            case .working(let since):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if context.date.timeIntervalSince(since) < NotchStatus.clockAfter {
                        WorkingDots()
                    } else {
                        Text(NotchStatus.elapsed(since: since, now: context.date))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityLabel(L("작업 중", "Working"))
            case .lowQuota(let agent, let remaining):
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.2)
                    Circle().trim(from: 0, to: remaining / 100).stroke(Palette.low, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 13, height: 13)
                .help(L("\(agent.name) 한도 \(Int(remaining))% 남음", "\(agent.name) limit: \(Int(remaining))% left"))
                .accessibilityLabel(L("\(agent.name) 한도 \(Int(remaining))% 남음", "\(agent.name) limit: \(Int(remaining))% left"))
            case .sessions:
                Circle().fill(Palette.muted).frame(width: 6, height: 6).accessibilityLabel(L("대기 중", "Idle"))
            case .empty:
                Color.clear
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .animation(Motion.snappy, value: status)
    }
    static func symbol(for reason: AttentionReason) -> String {
        switch reason {
        case .bell: "bell.fill"
        case .finished: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .exited: "stop.circle.fill"
        }
    }
}

/// Idle island: weekly quota left in the ring, 5-hour quota left as a number.
/// Low remaining quota turns red, matching the preview and workspace footer.
struct UsageBadge: View {
    let usage: IdleUsage
    let showsNumber: Bool
    private static func color(_ window: UsageWindow, normal: Color) -> Color {
        window.remaining <= NotchStatus.lowQuotaThreshold ? Palette.low : normal
    }
    private static func remainingLabel(_ window: UsageWindow) -> String {
        window.title + L(" \(Int(window.remaining))% 남음", " \(Int(window.remaining))% left")
    }
    static func percent(_ usage: IdleUsage) -> some View {
        Text("\(Int(usage.session.remaining))%").font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(color(usage.session, normal: .white))
            .contentTransition(.numericText(value: usage.session.remaining))
            .help(usage.agent.name + " · " + remainingLabel(usage.session) + " · " + usage.session.resetLabel())
    }
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 2)
                Circle().trim(from: 0, to: usage.weekly.remaining / 100)
                    .stroke(Self.color(usage.weekly, normal: Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.snappy, value: usage.weekly.remaining)
                SessionIcon(kind: usage.agent, size: 11)
            }
            .frame(width: 21, height: 21)
            .help(usage.agent.name + " · " + Self.remainingLabel(usage.weekly) + " · " + usage.weekly.resetLabel())
            if showsNumber { Self.percent(usage) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usage.agent.name + ", " + Self.remainingLabel(usage.session) + ", " + Self.remainingLabel(usage.weekly))
    }
}

/// "•••" flowing left to right while an agent works.
struct WorkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let step = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle().fill(Color.white.opacity(index == step ? 1 : 0.35)).frame(width: 4, height: 4)
                }
            }
        }
    }
}

/// The agent's mark; Terminal sessions use the terminal symbol.
struct SessionIcon: View {
    let kind: AgentKind
    var size: CGFloat = 14
    var body: some View {
        Group {
            if kind == .shell {
                Image(systemName: "terminal").font(.system(size: size * 0.8, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
            } else { AgentLogo(kind: kind, size: size) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A session among several: its icon inside a ring whose color says its state. Working spins
/// a white arc (so it never reads as "done" green); a request breathes; quiet has no ring.
struct RingedSessionIcon: View {
    let kind: AgentKind
    let badge: NotchBadge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    var body: some View {
        ZStack {
            switch badge {
            case .quiet: EmptyView()
            case .working:
                Circle().trim(from: 0, to: 0.3)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            case .done: Circle().stroke(Palette.done, lineWidth: 2)
            case .waiting:
                Circle().stroke(Palette.attention, lineWidth: 2)
                    .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { content, opacity in content.opacity(opacity) }
                        animation: { _ in .easeInOut(duration: 1.1) }
            case .error: Circle().stroke(Palette.low, lineWidth: 2)
            }
            SessionIcon(kind: kind, size: 12).opacity(badge == .quiet ? 0.5 : 1)
        }
        .frame(width: 22, height: 22)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct WorkspaceChipStyle: ButtonStyle {
    let active: Bool
    let highlight: Namespace.ID
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 9).padding(.vertical, 7)
            .background {
                // The active chip's background slides to the newly chosen folder.
                if active {
                    RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.055))
                        .matchedGeometryEffect(id: "activeFolder", in: highlight)
                }
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(configuration.isPressed ? 0.09 : 0)))
            .contentShape(Rectangle())
    }
}

/// Refresh icon that turns once per press, so a refresh with unchanged numbers still reads as done.
struct RefreshButton: View {
    let help: String
    let action: () -> Void
    @State private var turns = 0.0
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.5)) { turns += 1 }
            action()
        } label: {
            Image(systemName: "arrow.clockwise").font(.caption).rotationEffect(.degrees(turns * 360))
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(L("사용량 새로고침", "Refresh usage"))
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 9).padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.055))
            .clipShape(.rect(cornerRadius: 7))
    }
}
struct MintButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(.black).background(Palette.mint.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(.rect(cornerRadius: 10))
    }
}
