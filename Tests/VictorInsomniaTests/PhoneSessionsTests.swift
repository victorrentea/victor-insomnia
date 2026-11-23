import XCTest
@testable import VictorInsomnia

/// 📱 Phone sessions: which presence files make a row, what the row says, and
/// what the Terminal window runs. The move itself (kill + Terminal) was proved
/// live against a throwaway session; see `PhoneSessions`.
final class PhoneSessionsTests: XCTestCase {

    private var root: URL!
    private var sessions: URL { root.appendingPathComponent("sessions") }
    private var projects: URL { root.appendingPathComponent("projects") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func presence(pid: Int32, sessionId: String, bridge: String?, entrypoint: String = "sdk-cli",
                          status: String = "idle", startedAt: Double = 1, cwd: String = "/w") throws {
        var json: [String: Any] = ["pid": pid, "sessionId": sessionId, "cwd": cwd, "entrypoint": entrypoint,
                                   "status": status, "startedAt": startedAt]
        if let bridge { json["bridgeSessionId"] = bridge }
        try JSONSerialization.data(withJSONObject: json)
            .write(to: sessions.appendingPathComponent("\(pid).json"))
    }

    private func transcript(_ sessionId: String, cwd: String = "/w", lines: [String]) throws {
        let dir = projects.appendingPathComponent(ClaudeActivity.projectSlug(cwd: cwd))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent(sessionId + ".jsonl"), atomically: true, encoding: .utf8)
    }

    private func list(remotePids: Set<Int32>) -> [PhoneSession] {
        PhoneSessions.list(sessionsDir: sessions, projects: projects,
                           arguments: { remotePids.contains($0) ? ["claude", "--print", "--sdk-url", "x"] : ["claude", "-p"] },
                           isAlive: { _ in true })
    }

    func testOnlyLiveChildrenOfTheRemoteControlHostAreListedNewestFirst() throws {
        try presence(pid: 1, sessionId: "a", bridge: "session_01A", startedAt: 10)
        try presence(pid: 2, sessionId: "b", bridge: "session_01B", startedAt: 20)
        try presence(pid: 3, sessionId: "c", bridge: "session_01C")                 // Walkie's `claude -p`
        try presence(pid: 4, sessionId: "d", bridge: nil)                           // headless, never on the phone
        try presence(pid: 5, sessionId: "e", bridge: "session_01E", entrypoint: "cli") // a terminal with /rc
        try presence(pid: 6, sessionId: "f", bridge: "session_01F")                 // dead
        let found = PhoneSessions.list(
            sessionsDir: sessions, projects: projects,
            arguments: { [1, 2, 4, 5, 6].contains($0) ? ["claude", "--sdk-url", "u"] : ["claude", "-p"] },
            isAlive: { $0 != 6 })
        XCTAssertEqual(found.map(\.pid), [2, 1])
        XCTAssertEqual(found.first?.bridgeSessionId, "session_01B")
    }

    func testTheRowShowsTheFirstHumanPromptAndTheOwnerIsReadFromTheHead() throws {
        try presence(pid: 1, sessionId: "a", bridge: "session_01A", status: "busy")
        try transcript("a", lines: [
            #"{"type":"session-owner","accountUuid":"acc","organizationUuid":"org","sessionId":"a"}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"meta"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the\nlogin page"}]}}"#,
        ])
        let s = try XCTUnwrap(list(remotePids: [1]).first)
        XCTAssertEqual(s.title, "Fix the login page")
        XCTAssertTrue(s.isBusy)
        XCTAssertEqual(s.ownerAccount, "acc")
        XCTAssertEqual(s.ownerOrganization, "org")
    }

    func testALongPromptIsCutWithAnEllipsis() {
        let head = #"{"type":"user","message":{"role":"user","content":"\#(String(repeating: "x", count: 100))"}}"#
        let title = PhoneSessions.firstPrompt(inHead: head, limit: 20)
        XCTAssertEqual(title?.count, 20)
        XCTAssertEqual(title?.hasSuffix("…"), true)
    }

    func testNoTranscriptYetStillMakesARow() throws {
        try presence(pid: 1, sessionId: "a", bridge: "session_01A")
        XCTAssertEqual(list(remotePids: [1]).first?.title, "(no prompt yet)")
    }

    /// The env var is what keeps it the **same** session on the phone;
    /// `--remote-control` would mint a new one.
    func testTheTerminalReattachesToTheSameSessionInsteadOfMintingANewOne() {
        let s = PhoneSession(pid: 1, sessionId: "uuid-1", bridgeSessionId: "session_01A", cwd: "/w/it's here",
                             status: "idle", title: "t", ownerAccount: "acc", ownerOrganization: nil)
        let script = PhoneSessions.script(for: s)
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh -il\n"))
        XCTAssertTrue(script.contains("CLAUDE_BRIDGE_REATTACH_SESSION='session_01A'"))
        XCTAssertTrue(script.contains("CLAUDE_BRIDGE_REATTACH_OWNER_ACCT='acc'"))
        XCTAssertFalse(script.contains("OWNER_ORG"))
        XCTAssertTrue(script.contains("exec claude --resume 'uuid-1'"))
        XCTAssertFalse(script.contains("--remote-control"))
        XCTAssertTrue(script.contains(#"cd -- '/w/it'\''s here'"#))
    }

    /// The presence file says `session_…`, the child's argv says `cse_…`.
    func testBothPrefixesOfOneSessionShareTheirTail() {
        XCTAssertEqual(PhoneSessions.idTail("session_01GyhjeKBtcgwwYAYzmANCAr"),
                       PhoneSessions.idTail("cse_01GyhjeKBtcgwwYAYzmANCAr"))
    }
}
