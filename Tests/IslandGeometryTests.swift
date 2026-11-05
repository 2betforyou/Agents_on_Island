import AppKit
import Testing
@testable import NotchAgent

struct IslandGeometryTests {
    @Test("Each agent has a separate frame and the camera gap never receives clicks")
    @MainActor func separateAgentFrames() throws {
        let suite = "NotchAgent.SeparateIslands." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = UsageSnapshot(windows: [UsageWindow(id: "primary", usedPercent: 28, durationMinutes: 300, resetsAt: nil)], fetchedAt: Date())
        let usage = UsageService(snapshot: snapshot)
        usage.enabled = true
        let model = AppModel(defaults: defaults, usage: usage)
        model.claudeUsage.enabled = false
        model.physicalNotchWidth = 185
        let codexOnly = model.agentIslandFrames(in: CGRect(x: 0, y: 0, width: model.closedWidth, height: model.closedHeight))
        let codex = try #require(codexOnly.first { $0.kind == .codex })
        #expect(codex.frame.minX >= model.closedWidth / 2 + 185 / 2)
        #expect(codex.frame.width == model.agentIslandSize(.codex).width)
        #expect(codex.frame.width < 76)
        #expect(!codex.frame.contains(CGPoint(x: model.closedWidth / 2, y: model.closedHeight / 2)))
        let directory = URL(fileURLWithPath: "/tmp")
        let claude = TerminalSession(kind: .claude, directory: directory, executable: "/bin/echo", fontSize: 13)
        let other = TerminalSession(kind: .codex, directory: directory, executable: "/bin/echo", fontSize: 13)
        model.sessions = [other, claude]
        model.openAgentIsland(.claude)
        #expect(model.selectedID == claude.id)
        model.openAgentIsland(.codex)
        #expect(model.selectedID == other.id)
        model.previewAgent = .claude
        model.phase = .preview
        #expect(model.islandWidth < 400)
        #expect(model.islandOffsetX < 0)
        model.previewAgent = .codex
        #expect(model.islandOffsetX > 0)
        model.previewAgent = nil
        #expect(model.islandOffsetX == 0)
    }
    @Test("Hovering one island pushes its neighbor aside; the mock center stays put")
    @MainActor func neighborsMakeRoom() throws {
        let suite = "NotchAgent.PushIslands." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = UsageSnapshot(windows: [UsageWindow(id: "primary", usedPercent: 28, durationMinutes: 300, resetsAt: nil)], fetchedAt: Date())
        let usage = UsageService(snapshot: snapshot)
        usage.enabled = true
        let model = AppModel(defaults: defaults, usage: usage)
        model.claudeUsage.enabled = false
        model.hasPhysicalNotch = false // the narrow mock center: an expanded island overlaps its neighbor
        let claude = TerminalSession(kind: .claude, directory: URL(fileURLWithPath: "/tmp"), executable: "/bin/zsh", fontSize: 13)
        claude.start(); defer { claude.stop() }
        claude.recordOutput(at: Date()); _ = claude.tick(now: Date(), visible: false)
        model.sessions = [claude]
        let rect = CGRect(x: 0, y: 0, width: model.closedWidth, height: model.closedHeight)
        let resting = try #require(model.agentIslandFrames(in: rect).first { $0.kind == .codex }).frame
        let camera = model.mockCameraFrame(in: rect)

        model.previewAgent = .claude
        model.phase = .preview
        let expandedRight = rect.midX + model.islandOffsetX + model.islandWidth / 2
        let pushed = try #require(model.presentedAgentIslandFrames(in: rect).first { $0.kind == .codex }).frame
        #expect(expandedRight > resting.minX, "without a push the panel would cover Codex")
        #expect(pushed.minX >= expandedRight + 8 - 0.5, "Codex clears the expanded panel")
        #expect(pushed.size == resting.size && pushed.minY == resting.minY, "it slides sideways only")
        #expect(model.mockCameraFrame(in: rect) == camera, "the center never moves")

        model.phase = .closed
        let back = try #require(model.presentedAgentIslandFrames(in: rect).first { $0.kind == .codex }).frame
        #expect(back == resting, "collapsing returns it to its place")
    }
    @Test("On a notched display the notch itself is the center island")
    @MainActor func notchIsTheCenter() throws {
        let suite = "NotchAgent.NotchCenter." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.usage.enabled = false; model.claudeUsage.enabled = false
        model.hasPhysicalNotch = true; model.physicalNotchWidth = 185
        let rect = CGRect(x: 0, y: 0, width: model.closedWidth, height: model.closedHeight)
        let center = model.centerIslandFrame(in: rect)
        #expect(center.width == 185 && center.midX == rect.midX, "covers the camera notch")
        #expect(model.closedIslandKinds == [.shell], "no extra island is added for notched displays")
        for island in model.agentIslandFrames(in: rect) { #expect(!island.frame.intersects(center)) }
        model.previewAgent = .claude // hovered earlier
        model.openPriorityOrTerminal()
        #expect(model.previewAgent == nil, "opening from the center grows from the center")
        model.hasPhysicalNotch = false
        #expect(model.centerIslandFrame(in: rect) == model.mockCameraFrame(in: rect), "elsewhere, the mock capsule")
    }
    @Test("The expanded panel fits connected displays while its anchor stays in the menu bar")
    @MainActor func connectedDisplays() {
        for screen in NSScreen.screens {
            let size = TerminalSize.standard.fitted(to: screen.frame.size)
            let rect = IslandGeometry.surfaceFrame(screen: screen.frame, visible: screen.visibleFrame,
                                                   safeAreaTop: screen.safeAreaInsets.top, size: size)
            #expect(rect.maxY <= screen.frame.maxY)
            #expect(rect.maxY >= screen.visibleFrame.maxY)
            #expect(rect.minY >= screen.visibleFrame.minY)
            #expect(rect.minX >= screen.frame.minX)
            #expect(rect.maxX <= screen.frame.maxX)
        }
    }
    @Test("Small islands are vertically centered in the menu bar", arguments: [0.0, 38.0, 52.0])
    func safeTop(cutout: Double) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 60, width: 1512, height: 898) // menu bar 24pt
        let rect = IslandGeometry.surfaceFrame(screen: screen, visible: visible, safeAreaTop: cutout,
                                               size: CGSize(width: 76, height: 28))
        let menuHeight: CGFloat = max(30, CGFloat(cutout), screen.maxY - visible.maxY)
        let expectedY: CGFloat = screen.maxY - (menuHeight - 28) / 2
        #expect(abs(rect.maxY - expectedY) < 0.001)
        #expect(abs(rect.midY - (screen.maxY - menuHeight / 2)) < 0.001)
        #expect(rect.size == CGSize(width: 76, height: 28))
        #expect(rect.midX == screen.midX)
        #expect(rect.minY >= visible.minY)
    }
    @Test("Auto-hidden menu bars retain a stable top-center anchor")
    func hiddenMenuBar() {
        let screen = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let rect = IslandGeometry.surfaceFrame(screen: screen, visible: screen, safeAreaTop: 38,
                                               size: CGSize(width: 212, height: 36))
        #expect(rect.maxY == 1175)
        #expect(rect.midX == -960)
    }
    @Test("Host shadow padding and the visible surface have the same anchor")
    func hostAndSurfaceAgree() {
        let screen = CGRect(x: 100, y: -1080, width: 1920, height: 1080)
        let visible = screen.insetBy(dx: 0, dy: 24)
        let size = CGSize(width: 940, height: 620)
        let host = IslandGeometry.hostFrame(screen: screen, visible: visible, safeAreaTop: 0, content: size)
        let surface = IslandGeometry.surfaceFrame(screen: screen, visible: visible, safeAreaTop: 0, size: size)
        #expect(host.insetBy(dx: 16, dy: 16) == surface)
        #expect(host.size == CGSize(width: 972, height: 652))
    }
    @Test("Rounded transparent corners and the menu-bar gap are not clickable")
    @MainActor func hitArea() {
        let rect = CGRect(x: 100, y: 200, width: 212, height: 36)
        let path = IslandShape(radius: 18).path(in: rect)
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
        #expect(!path.contains(CGPoint(x: rect.minX + 1, y: rect.maxY - 1)))
        #expect(!path.contains(CGPoint(x: rect.midX, y: rect.maxY + 4)))
    }
    @Test("Only the transparent camera gap depends on camera width")
    @MainActor func cameraIndependentSize() {
        let usage = UsageService()
        usage.enabled = false
        let suite = "NotchAgent.Floating." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, usage: usage)
        model.claudeUsage.enabled = false
        model.physicalNotchWidth = 185; model.compactWidth = 285
        let notched = model.closedWidth
        let pill = model.agentIslandSize(.shell)
        model.hasPhysicalNotch = false; model.physicalNotchWidth = 0; model.compactWidth = 210
        #expect(notched - model.closedWidth == 107)
        #expect(model.mockCameraFrame(in: CGRect(x: 0, y: 0, width: model.closedWidth, height: model.closedHeight)).width / model.notchHeight == 2.5)
        #expect(model.agentIslandSize(.shell) == pill)
        #expect(model.closedHeight == 28)
        #expect(model.islandCornerRadius == 14)
        model.phase = .terminal
        #expect(model.islandWidth == model.panelWidth)
        #expect(model.islandHeight == model.panelHeight)
    }
}
