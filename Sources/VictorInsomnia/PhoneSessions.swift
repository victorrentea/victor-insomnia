import AppKit
import Foundation

/// One session the `claude remote-control` host is running for the phone (or
/// claude.ai/code): a headless `claude --print --sdk-url …` child.
struct PhoneSession: Equatable {
    let pid: Int32
    /// The local transcript's id — `~/.claude/projects/<slug>/<sessionId>.jsonl`.
    let sessionId: String
    /// The id the phone and claude.ai know it by (`session_01…`).
    let bridgeSessionId: String
    let cwd: String
    /// `busy` mid-turn, else `idle` / `waiting`.
    let status: String
    /// The first prompt, as the phone's list would show it.
    let title: String
    /// From the transcript's `session-owner` line; handed to the reattach so it
    /// does not have to guess whose session it is.
    let ownerAccount: String?
    let ownerOrganization: String?

    var isBusy: Bool { status == "busy" }
}

/// **📱 Phone sessions**: lists the sessions opened from the phone and moves one
/// into a Terminal window, **still the same session on the phone** (2026-11-23).
///
/// Victor: *"could Insomnia list the remote sessions in a submenu? click one and
/// it becomes an interactive one with /rc in it — to bring to the front sessions
/// started in the background from the phone"*.
///
/// How the move works, measured on CLI 2.1.330 with a throwaway session:
///
/// 1. The phone session's transcript **is local** — the presence file
///    `~/.claude/sessions/<pid>.json` names it (`sessionId`) next to the id the
///    phone knows (`bridgeSessionId`).
/// 2. Stop the headless child (`SIGTERM`). The host does **not** archive the
///    session for that: it stays on the phone, offline.
/// 3. In a Terminal: `CLAUDE_BRIDGE_REATTACH_SESSION=<bridgeSessionId> claude
///    --resume <sessionId>`. The env var turns Remote Control on and
///    **reattaches to that same session** — same URL, same entry on the phone,
///    whole history; a message sent from claude.ai was answered in the terminal.
///
/// **Not `claude --resume … --remote-control`**: that works too, but mints a
/// *new* session on the phone, and the old entry stays behind. Writing into the
/// old one then made the host spawn a fresh headless child **on the same
/// transcript** as the terminal — two writers, a forked conversation.
/// The env var is internal to the CLI (it uses it to hand a session over to a
/// relaunched process); if a release drops it, step 3 falls back to a plain
/// local resume with no /rc — still the conversation, just not on the phone.
enum PhoneSessions {

    /// Every live phone session, newest first.
    static func list(sessionsDir: URL = ClaudeActivity.sessionsDirectory,
                     projects: URL = ClaudeActivity.projectsDirectory,
                     arguments: (Int32) -> [String]? = ClaudeActivity.arguments(of:),
                     isAlive: (Int32) -> Bool = { kill($0, 0) == 0 }) -> [PhoneSession] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir.path) else { return [] }
        let found: [(PhoneSession, Double)] = names.filter { $0.hasSuffix(".json") }.compactMap { name -> (PhoneSession, Double)? in
            guard let data = try? Data(contentsOf: sessionsDir.appendingPathComponent(name)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = (json["pid"] as? NSNumber)?.int32Value,
                  let sessionId = json["sessionId"] as? String,
                  let bridge = json["bridgeSessionId"] as? String, !bridge.isEmpty,
                  let cwd = json["cwd"] as? String,
                  json["entrypoint"] as? String == ClaudeActivity.remoteEntrypoint,
                  isAlive(pid),
                  isRemoteChild(arguments(pid))
            else { return nil }
            let transcript = projects
                .appendingPathComponent(ClaudeActivity.projectSlug(cwd: cwd))
                .appendingPathComponent(sessionId + ".jsonl")
            let head = readHead(of: transcript)
            let owner = head.flatMap { Self.owner(inHead: $0) }
            let session = PhoneSession(pid: pid, sessionId: sessionId, bridgeSessionId: bridge, cwd: cwd,
                                       status: json["status"] as? String ?? "",
                                       title: head.flatMap { Self.firstPrompt(inHead: $0) } ?? "(no prompt yet)",
                                       ownerAccount: owner?.account, ownerOrganization: owner?.organization)
            return (session, (json["startedAt"] as? NSNumber)?.doubleValue ?? 0)
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// A child of the remote-control host, not Walkie Talkie's or any other
    /// `claude -p` (they write `sdk-cli` too) — see `isRemoteControlled`.
    static func isRemoteChild(_ argv: [String]?) -> Bool {
        argv?.contains(ClaudeActivity.remoteControlFlag) ?? false
    }

    // MARK: - Reading the transcript's head

    static let headBytes = 512 * 1024

    static func readHead(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headBytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The first thing a human typed: the first `user` line that is not meta,
    /// not a tool result, not a `<command-…>` / `<local-command-…>` wrapper.
    static func firstPrompt(inHead head: String, limit: Int = 48) -> String? {
        for line in head.split(separator: "\n") where line.contains("\"type\":\"user\"") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  json["type"] as? String == "user",
                  json["isMeta"] as? Bool != true,
                  let message = json["message"] as? [String: Any] else { continue }
            let text: String?
            if let s = message["content"] as? String {
                text = s
            } else if let parts = message["content"] as? [[String: Any]] {
                text = parts.first { $0["type"] as? String == "text" }?["text"] as? String
            } else {
                text = nil
            }
            guard let raw = text else { continue }
            let flat = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if flat.isEmpty || flat.hasPrefix("<") { continue }
            return shorten(flat, to: limit)
        }
        return nil
    }

    static func shorten(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func owner(inHead head: String) -> (account: String?, organization: String?)? {
        for line in head.split(separator: "\n").prefix(5) where line.contains("\"session-owner\"") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            return (json["accountUuid"] as? String, json["organizationUuid"] as? String)
        }
        return nil
    }

    // MARK: - Moving one into a Terminal

    enum TakeOverError: Error, CustomStringConvertible {
        case gone, wouldNotStop, launchFailed(String)
        var description: String {
            switch self {
            case .gone: return "the session is no longer running"
            case .wouldNotStop: return "the background process did not stop"
            case .launchFailed(let why): return "Terminal did not open: \(why)"
            }
        }
    }

    /// Stop the headless child, then reopen the session in Terminal on the same
    /// phone entry. The pid is checked again right before the signal: a pid the
    /// menu showed a minute ago may belong to something else by now.
    static func takeOver(_ session: PhoneSession) throws {
        guard let argv = ClaudeActivity.arguments(of: session.pid), isRemoteChild(argv),
              argv.contains(where: { $0.hasSuffix(idTail(session.bridgeSessionId)) }) else { throw TakeOverError.gone }
        insomniaInfo("PhoneSessions: taking over \(session.bridgeSessionId) (pid \(session.pid)) → Terminal")
        kill(session.pid, SIGTERM)
        guard waitForExit(session.pid, seconds: 5) else {
            kill(session.pid, SIGKILL)
            guard waitForExit(session.pid, seconds: 2) else { throw TakeOverError.wouldNotStop }
            return try openInTerminal(session)
        }
        try openInTerminal(session)
    }

    /// `session_01Abc` and `cse_01Abc` are the same session under two prefixes;
    /// the child's argv carries the `cse_` one.
    static func idTail(_ id: String) -> String {
        id.split(separator: "_", maxSplits: 1).last.map(String.init) ?? id
    }

    static func waitForExit(_ pid: Int32, seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            usleep(100_000)
        }
        return kill(pid, 0) != 0
    }

    static func openInTerminal(_ session: PhoneSession) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("insomnia-phone-\(session.sessionId).command")
        do {
            try script(for: session).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            throw TakeOverError.launchFailed("\(error)")
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", url.path]
        do { try open.run() } catch { throw TakeOverError.launchFailed("\(error)") }
        open.waitUntilExit()
        if open.terminationStatus != 0 { throw TakeOverError.launchFailed("open exited \(open.terminationStatus)") }
    }

    /// What the Terminal window runs. An interactive login zsh, so `claude` is
    /// found the way it is when typed; the script deletes itself first thing.
    static func script(for session: PhoneSession) -> String {
        var env = ["CLAUDE_BRIDGE_REATTACH_SESSION=\(quoted(session.bridgeSessionId))"]
        if let account = session.ownerAccount { env.append("CLAUDE_BRIDGE_REATTACH_OWNER_ACCT=\(quoted(account))") }
        if let org = session.ownerOrganization { env.append("CLAUDE_BRIDGE_REATTACH_OWNER_ORG=\(quoted(org))") }
        return """
        #!/bin/zsh -il
        rm -f -- "$0"
        cd -- \(quoted(session.cwd)) || exit 1
        export \(env.joined(separator: " "))
        exec claude --resume \(quoted(session.sessionId))

        """
    }

    /// Single-quoted for zsh; a `'` inside becomes `'\''`.
    static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
