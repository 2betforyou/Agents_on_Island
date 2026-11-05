import XCTest
@testable import NotchAgent

final class SessionRestoreTests: XCTestCase {
    func testOnlyFirstAgentTabPerFolderResumes() {
        let saved = [SavedSession(kind: .claude, path: "/p/a"), SavedSession(kind: .claude, path: "/p/a/"),
                     SavedSession(kind: .claude, path: "/p/b"), SavedSession(kind: .codex, path: "/p/a"),
                     SavedSession(kind: .shell, path: "/p/a"), SavedSession(kind: .gemini, path: "/p/a")]
        XCTAssertEqual(SessionRestore.plan(saved).map(\.resume), [true, false, true, true, false, false])
        XCTAssertEqual(SessionRestore.resumeArguments(for: .claude), ["--continue"])
        XCTAssertEqual(SessionRestore.resumeArguments(for: .codex), ["resume", "--last"])
    }

    @MainActor func testClaudeIdIsKeptOnlyOnceAConversationExists() throws {
        let session = TerminalSession(kind: .claude, directory: URL(fileURLWithPath: "/tmp"), executable: "/bin/echo", fontSize: 13)
        let id = UUID().uuidString.lowercased()
        session.receive(nil, conversation: id, now: Date()) // SessionStart: nothing written yet
        XCTAssertNil(session.conversationID, "an untouched session has nothing to resume")
        session.receive(.started, conversation: id, now: Date())
        XCTAssertEqual(session.conversationID, id)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeProjects-" + UUID().uuidString)
        let project = root.appendingPathComponent("-Users-me-app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(SessionRestore.claudeConversationExists(id, root: root))
        try Data().write(to: project.appendingPathComponent(id + ".jsonl"))
        XCTAssertTrue(SessionRestore.claudeConversationExists(id, root: root))
        XCTAssertFalse(SessionRestore.claudeConversationExists("../../etc/passwd", root: root), "only real ids")
    }

    @MainActor func testOpenTabsComeBackUnstartedAndEndedOnesDoNot() throws {
        let d = UserDefaults.standard
        let keys = ["savedSessions", "restoreSessions", "startRestoredSessions", "workspace", "workspaces"]
        let saved = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { d.set(v, forKey: k) } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentRestore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = Workspaces.normalize(dir.path)

        let before = AppModel()
        before.restoreSessions = true
        before.workspaces = [SavedWorkspace(path: path)]
        before.activateWorkspace(path)
        before.launch(.shell); before.launch(.shell)
        let finished = try XCTUnwrap(before.sessions.last)
        finished.start(); finished.stop()          // the user ended this one
        before.saveSessions()
        TerminalSession.stopAll(before.sessions)

        d.set(false, forKey: "startRestoredSessions")
        let after = AppModel()
        after.workspaces = [SavedWorkspace(path: path)]
        after.activateWorkspace(path)
        after.restoreSavedSessions()
        XCTAssertEqual(after.sessions.count, 1)
        XCTAssertEqual(after.sessions.first?.kind, .shell)
        XCTAssertEqual(after.sessions.first.map { Workspaces.normalize($0.initialDirectory.path) }, path)
        XCTAssertEqual(after.sessions.first?.started, false, "option off: restored tabs start only when opened")
        XCTAssertEqual(after.runningCount, 0)
        XCTAssertEqual(after.selectedID, after.sessions.first?.id)

        // With the default, restored tabs start at launch instead.
        d.set(true, forKey: "startRestoredSessions")
        let started = AppModel()
        started.workspaces = [SavedWorkspace(path: path)]
        started.activateWorkspace(path)
        started.restoreSavedSessions()
        defer { TerminalSession.stopAll(started.sessions) }
        XCTAssertEqual(started.sessions.count, 1)
        XCTAssertEqual(started.sessions.first?.started, true, "restored tabs start right away by default")
        XCTAssertEqual(started.runningCount, 1)

        after.restoreSessions = false
        XCTAssertNil(d.data(forKey: "savedSessions"), "turning it off forgets saved tabs")
    }
}
