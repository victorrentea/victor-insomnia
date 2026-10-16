import Foundation
import Darwin

/// Whether 🛰️ **Claude RC** is armed — the row under the four modes.
///
/// **Default off**: this is a public app, and starting a `claude
/// remote-control` server on somebody's Mac is not something to do unasked.
/// (It was default *on* while it lived in Victor Addons, where it took over a
/// LaunchAgent that was already running it; the maintainer's Mac carries the
/// tick over in `defaults`, see docs/claude-remote-control.md.)
enum ClaudeRemoteControlSettings {
    static let enabledKey = "ClaudeRemoteControl.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

/// What the watcher should do with the `claude-rc` tmux session on this tick.
enum ClaudeRemoteControlAction: Equatable {
    case leaveAlone
    case start
    case kill
}

/// The whole decision of 🛰️ Claude RC in background, lifted out of the timer and
/// the two `tmux` calls that drive it so it can be tested without a tmux server,
/// a Claude login or a minute of waiting.
///
/// It is a two-bit truth table and it is written down anyway, because the
/// asymmetry in it is the feature: **the tick is a one-way watchdog, not a
/// mirror.** Armed and dead → start it; disarmed and alive → kill it. The other
/// two cells do nothing, and in particular a *disarmed* tick does not keep
/// killing: the row means "I don't want the app minding this", so a session
/// started by hand in a terminal afterwards must survive — killing it
/// every minute would make the unticked row more intrusive than the ticked one.
/// It is the toggle's own edge (`setEnabled(false)`) that kills once.
enum ClaudeRemoteControlPolicy {
    static func decide(enabled: Bool, sessionAlive: Bool) -> ClaudeRemoteControlAction {
        switch (enabled, sessionAlive) {
        case (true, false): return .start
        case (false, true): return .kill
        default: return .leaveAlone
        }
    }
}

/// What one look at the running `claude remote-control` server found — the
/// inputs of the stale-server decision, gathered by `ClaudeRemoteControl.probe()`
/// and judged by `ClaudeRemoteControlStaleness.decide`, which never touches
/// tmux, `ps` or the disk.
struct ClaudeRemoteControlProbe: Equatable {
    /// `…/versions/2.1.285` → `2.1.285`; nil when the server's binary could not
    /// be read.
    var serverVersion: String?
    /// nil = unknown (no path to check); false = the file the server was
    /// launched from is gone from disk — proof on its own.
    var serverBinaryExists: Bool?
    /// `readlink ~/.local/bin/claude` → `…/versions/X` → `X`.
    var installedVersion: String?
    /// The pane shows `spawn error: ENOENT` — the symptom itself.
    var paneShowsSpawnENOENT: Bool
    /// `Capacity: N/32` from the pane, nil when the banner is not on screen.
    var capacityInUse: Int?
    /// Direct children of the server process — the phone sessions it spawned
    /// (and anything else it forked, which errs on the side of waiting).
    var childProcesses: Int

    /// The larger of the two witnesses. Either one saying "someone is in
    /// there" is enough to hold the restart.
    var liveSessions: Int { max(capacityInUse ?? 0, childProcesses) }
}

enum ClaudeRemoteControlHeal: Equatable {
    case healthy
    /// Stale, and nothing to lose: kill + start, exactly the toggle's path.
    case restart(reason: String)
    /// Stale, but restarting now would cost something — live phone sessions,
    /// or a restart that happened too recently to try again.
    case wait(reason: String)
}

/// The stale-server half of the watchdog (2026-09-30). `tmux has-session` says
/// the session exists; it cannot say the server inside it still works.
///
/// **What happened.** The server started on 25 Sep on Claude Code 2.1.282 and
/// ran five days. Auto-update installed 2.1.283–2.1.285 and deleted
/// `versions/2.1.282` — and the server spawns every phone session from its *own*
/// version path, so every new session died with `spawn error: ENOENT … posix_spawn
/// '…/versions/2.1.282'` while the pane kept saying `Ready · Capacity: 0/32` and
/// the watchdog kept seeing a live tmux session.
///
/// **Stale** is any of: the server's binary is gone from disk; its version
/// differs from the installed one (the old version *will* be deleted by a later
/// update, so the mismatch is the early warning); the pane shows the ENOENT.
///
/// **A stale server with live sessions is never restarted** — the kill would
/// take the running phone sessions with it. It waits, and the first tick
/// after the last session ends heals it. And a restart is not retried within
/// `cooldown` of the previous one: if a fresh server is stale again at once,
/// restarting it every minute fixes nothing and hides the real fault.
enum ClaudeRemoteControlStaleness {
    static let cooldown: TimeInterval = 10 * 60

    /// Why the server is stale, or nil when it is not.
    static func staleReason(_ p: ClaudeRemoteControlProbe) -> String? {
        if p.serverBinaryExists == false {
            return "server binary \(p.serverVersion ?? "?") deleted from disk"
        }
        if p.paneShowsSpawnENOENT {
            return "pane shows spawn error: ENOENT"
        }
        if let s = p.serverVersion, let i = p.installedVersion, s != i {
            return "server on \(s), installed is \(i)"
        }
        return nil
    }

    static func decide(_ p: ClaudeRemoteControlProbe,
                       secondsSinceLastRestart: TimeInterval?) -> ClaudeRemoteControlHeal {
        guard let reason = staleReason(p) else { return .healthy }
        if p.liveSessions > 0 {
            return .wait(reason: "\(reason) — \(p.liveSessions) live session(s), not killing them")
        }
        if let since = secondsSinceLastRestart, since < cooldown {
            return .wait(reason: "\(reason) — restarted under \(Int(cooldown / 60)) min ago, cooling down")
        }
        return .restart(reason: reason)
    }

    // MARK: parsing, pure

    /// `/Users/x/.local/share/claude/versions/2.1.285` → `2.1.285`. Only a path
    /// whose parent directory is `versions` counts, so an npm/nvm `claude` (a
    /// node script) reads as unknown instead of as a bogus version.
    static func version(fromBinaryPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard url.deletingLastPathComponent().lastPathComponent == "versions" else { return nil }
        let v = url.lastPathComponent
        return looksLikeVersion(v) ? v : nil
    }

    static func looksLikeVersion(_ s: String) -> Bool {
        s.range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression) != nil
    }

    /// The last `Capacity: N/32` on screen.
    static func capacityInUse(pane: String) -> Int? {
        let re = try! NSRegularExpression(pattern: #"Capacity:\s*(\d+)\s*/\s*\d+"#)
        let ns = pane as NSString
        guard let m = re.matches(in: pane, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }

    static func showsSpawnENOENT(pane: String) -> Bool {
        pane.contains("spawn error: ENOENT")
    }
}

/// 🛰️ Keeps `claude remote-control` — the persistent server the phone opens new
/// sessions against — alive in a detached tmux session, and gives it the off
/// switch it never had.
///
/// **Why an app and not launchd.** Until 22 Sep 2026 a LaunchAgent ran the
/// script at login plus a `StartInterval` re-check every 5 minutes. That
/// watchdog had no way to be told *no*: killing the tmux session bought at
/// most five minutes of quiet before launchd put it back. A menu row is an off
/// switch, and a row that ticks is also the only place the state is visible.
/// It lived in Victor Addons until 2026-10-16 and moved here, next to the
/// `/rc` count it feeds: Insomnia is what holds the Mac up for those sessions.
///
/// **The script holds the command**, `claude-rc.sh` — the distinction that
/// cost a fortnight once: `claude remote-control` (the *server*, 32 sessions,
/// the phone can create new ones) versus `claude --remote-control <name>` (the
/// *flag*, one existing session exposed), plus `--permission-mode auto`
/// instead of a blanket bypass, and the `ComputerName` prefix. The app ships
/// one (`scripts/claude-rc.sh`); `~/.victor-insomnia/claude-rc.sh` wins over
/// it, the same override the sounds have.
///
/// **A real PTY is why tmux is still in the picture.** Remote Control needs one,
/// and neither launchd nor an `NSTask` gives it one, so the detached session is
/// not incidental — it is the only reason this works at all. It also means the
/// server survives the rebuild loop (`pkill` + `open`): a tmux server
/// double-forks away from whoever spawned it, so restarting this app does not
/// take Remote Control down with it. The arming tick is what covers the case
/// where it *was* already down.
final class ClaudeRemoteControl {

    /// The maintainer's number: "poll once a minute". Generous leeway on top —
    /// this is a watchdog, not a stopwatch, and letting the scheduler coalesce a
    /// once-a-minute `tmux has-session` is free.
    static let pollInterval: TimeInterval = 60

    static let sessionName = "claude-rc"

    private let queue = DispatchQueue(label: "ro.victorrentea.claude-rc-watch")
    private var timer: DispatchSourceTimer?
    /// Only for logging: the transitions are worth a line, sixty restatements an
    /// hour of "still up" are not.
    private var lastLoggedAlive: Bool?
    /// Same, for the stale-server verdict: log when it changes, not every tick.
    private var lastLoggedHeal: ClaudeRemoteControlHeal?
    /// Why the last self-heal restart happened, and when — `/test/claude-rc`
    /// shows the first, the cooldown reads the second. Touched only on `queue`.
    private var lastRestartReason: String?
    private var lastRestartAt: Date?

    // MARK: - Lifecycle

    /// Called once at launch — and it is the *whole* answer to "after the app
    /// restarts I expect Remote Control back". The evaluation runs immediately
    /// rather than a minute from now, so a session that died while the app was
    /// being rebuilt is back up by the time the menu bar icon appears.
    func startIfEnabled() {
        setEnabled(ClaudeRemoteControlSettings.isEnabled, announce: false)
    }

    func setEnabled(_ enabled: Bool, announce: Bool = true) {
        ClaudeRemoteControlSettings.isEnabled = enabled
        guard enabled else {
            stopPolling()
            // The one place a kill happens. The tick never kills — see the policy.
            queue.async { [weak self] in
                guard let self else { return }
                if self.isSessionAlive() {
                    self.killSession()
                    if announce { insomniaInfo("🛰️ Claude RC stopped — the phone can't open sessions until you tick it back") }
                } else if announce {
                    insomniaInfo("🛰️ Claude RC was not running — nothing to stop")
                }
            }
            return
        }
        startPolling()
        queue.async { [weak self] in self?.evaluate(reason: "armed") }
        if announce { insomniaInfo("🛰️ Claude RC armed — checked every \(Int(Self.pollInterval))s") }
    }

    private func startPolling() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.pollInterval,
                   repeating: Self.pollInterval,
                   leeway: .seconds(10))
        t.setEventHandler { [weak self] in self?.evaluate(reason: "poll") }
        t.resume()
        timer = t
    }

    private func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - The tick

    private func evaluate(reason: String) {
        let alive = isSessionAlive()
        if lastLoggedAlive != alive {
            lastLoggedAlive = alive
            insomniaInfo("🛰️ claude-rc \(alive ? "up" : "down") (\(reason))")
        }
        switch ClaudeRemoteControlPolicy.decide(enabled: ClaudeRemoteControlSettings.isEnabled,
                                                sessionAlive: alive) {
        case .leaveAlone:
            if alive && ClaudeRemoteControlSettings.isEnabled { healIfStale(reason: reason) }
        case .kill:
            killSession()
        case .start:
            startSession(reason: reason)
        }
    }

    /// Alive is not the same as working — see `ClaudeRemoteControlStaleness`.
    /// Runs only when armed and the session exists; restarts through the very
    /// kill + start the toggle uses.
    private func healIfStale(reason tick: String) {
        let probe = probe()
        let since = lastRestartAt.map { Date().timeIntervalSince($0) }
        let verdict = ClaudeRemoteControlStaleness.decide(probe, secondsSinceLastRestart: since)
        let changed = verdict != lastLoggedHeal
        lastLoggedHeal = verdict
        let versions = "server \(probe.serverVersion ?? "?"), installed \(probe.installedVersion ?? "?")"
        switch verdict {
        case .healthy:
            if changed { insomniaInfo("🛰️ claude-rc healthy (\(versions), \(probe.liveSessions) live)") }
        case .wait(let why):
            guard changed else { return }
            // ENOENT means no phone session can start right now — say it loudly.
            if probe.paneShowsSpawnENOENT || probe.serverBinaryExists == false {
                insomniaError("🛰️ claude-rc STALE, cannot spawn sessions — waiting: \(why)")
            } else {
                insomniaInfo("🛰️ claude-rc stale, waiting: \(why)")
            }
        case .restart(let why):
            insomniaInfo("🛰️ claude-rc stale → restarting (\(tick)): \(why); \(versions)")
            lastRestartReason = "\(Self.timestamp()) \(why)"
            lastRestartAt = Date()
            killSession()
            startSession(reason: "self-heal: \(why)")
            lastLoggedHeal = nil
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: - Probing the server

    /// `~/.local/bin/claude` is the native installer's symlink to
    /// `~/.local/share/claude/versions/X` — the version a fresh start would get.
    static func installedVersion() -> String? {
        let link = "\(NSHomeDirectory())/.local/bin/claude"
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link) else { return nil }
        return ClaudeRemoteControlStaleness.version(fromBinaryPath: dest)
    }

    /// The kernel's idea of the executable (`proc_pidpath`) — for a claude
    /// launched through the symlink that is `…/versions/X`. `ps -o comm=` says
    /// only `claude` (it prints argv[0]), so it cannot be used.
    static func executablePath(pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// `p_comm`, the executable's file name as the kernel recorded it at exec —
    /// `2.1.285` for the native claude. The fallback when the path is unreadable.
    static func processName(pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let n = proc_name(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    static func childPIDs(of pid: pid_t) -> [pid_t] {
        let out = runCapturing("/usr/bin/pgrep", ["-P", "\(pid)"]) ?? ""
        return out.split(whereSeparator: \.isNewline).compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The server pid: the pane's own process (`claude-rc.sh` execs all the
    /// way down), or — should that ever change — its first child that is a
    /// versioned claude.
    static func serverPID(panePID: pid_t) -> pid_t {
        func isClaude(_ p: pid_t) -> Bool {
            executablePath(pid: p).flatMap(ClaudeRemoteControlStaleness.version(fromBinaryPath:)) != nil
                || processName(pid: p).map(ClaudeRemoteControlStaleness.looksLikeVersion) == true
        }
        if isClaude(panePID) { return panePID }
        return childPIDs(of: panePID).first(where: isClaude) ?? panePID
    }

    func probe() -> ClaudeRemoteControlProbe {
        var probe = ClaudeRemoteControlProbe(serverVersion: nil, serverBinaryExists: nil,
                                             installedVersion: Self.installedVersion(),
                                             paneShowsSpawnENOENT: false, capacityInUse: nil,
                                             childProcesses: 0)
        guard let tmux = Self.tmuxPath() else { return probe }
        // -J joins wrapped lines: the pane is 80 columns and the ENOENT line is not.
        if let pane = Self.runCapturing(tmux, ["capture-pane", "-p", "-J", "-t", Self.sessionName]) {
            probe.paneShowsSpawnENOENT = ClaudeRemoteControlStaleness.showsSpawnENOENT(pane: pane)
            probe.capacityInUse = ClaudeRemoteControlStaleness.capacityInUse(pane: pane)
        }
        guard let out = Self.runCapturing(tmux, ["list-panes", "-t", Self.sessionName, "-F", "#{pane_pid}"]),
              let panePID = out.split(whereSeparator: \.isNewline).first.flatMap({ pid_t($0) })
        else { return probe }
        let server = Self.serverPID(panePID: panePID)
        if let path = Self.executablePath(pid: server),
           let v = ClaudeRemoteControlStaleness.version(fromBinaryPath: path) {
            probe.serverVersion = v
            probe.serverBinaryExists = FileManager.default.fileExists(atPath: path)
        } else if let name = Self.processName(pid: server), ClaudeRemoteControlStaleness.looksLikeVersion(name) {
            probe.serverVersion = name
            probe.serverBinaryExists = FileManager.default.fileExists(
                atPath: "\(NSHomeDirectory())/.local/share/claude/versions/\(name)")
        }
        probe.childProcesses = Self.childPIDs(of: server).count
        return probe
    }

    /// Run, wait, return stdout (nil on a non-zero exit — except `pgrep`, whose
    /// exit 1 just means "no children" and still yields an empty string).
    static func runCapturing(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus == 0 { return out }
        return path.hasSuffix("pgrep") && p.terminationStatus == 1 ? "" : nil
    }

    // MARK: - tmux

    /// `tmux` is looked up by path rather than trusted to `PATH`: under launchd
    /// this process has `/usr/bin:/bin:/usr/sbin:/sbin` and Homebrew is not in
    /// it, so a bare `tmux` would simply never be found — silently, once a
    /// minute, forever.
    static func tmuxPath() -> String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func isSessionAlive() -> Bool {
        guard let tmux = Self.tmuxPath() else { return false }
        return run(tmux, ["has-session", "-t", Self.sessionName]) == 0
    }

    private func killSession() {
        guard let tmux = Self.tmuxPath() else { return }
        let status = run(tmux, ["kill-session", "-t", Self.sessionName])
        insomniaInfo("🛰️ claude-rc killed (tmux exit \(status))")
        lastLoggedAlive = false
    }

    private func startSession(reason: String) {
        guard let script = Self.findScript() else {
            insomniaError("🛰️ claude-rc.sh not found — Remote Control cannot be started")
            return
        }
        let status = run("/bin/zsh", [script])
        if status == 0 {
            insomniaInfo("🛰️ claude-rc started (\(reason), \(script))")
            lastLoggedAlive = true
        } else {
            insomniaError("🛰️ claude-rc.sh exited \(status) — Remote Control did not start")
        }
    }

    /// Resolve `claude-rc.sh`: the user's own (`~/.victor-insomnia/claude-rc.sh`,
    /// or `$VICTOR_INSOMNIA_CLAUDE_RC`) first, then the copy inside the app.
    static func findScript() -> String? {
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["VICTOR_INSOMNIA_CLAUDE_RC"], !env.isEmpty {
            candidates.append(env)
        }
        candidates.append("\(NSHomeDirectory())/.victor-insomnia/claude-rc.sh")
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("claude-rc.sh").path {
            candidates.append(bundled)
        }
        return candidates
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Run and wait. Every call here is a millisecond of tmux bookkeeping —
    /// `has-session` asks the server a question, and `new-session -d` returns as
    /// soon as the detached session exists — so waiting keeps the state machine
    /// honest without ever blocking for long. It is on `queue`, never main.
    ///
    /// **`ANTHROPIC_API_KEY` is stripped from the child**, the Swift spelling of
    /// `env -u ANTHROPIC_API_KEY`: an exported key shadows the subscription the
    /// server is logged in with, and a key out of credit fails its auth.
    /// Anything this process happens to have inherited must not reach it.
    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            insomniaError("🛰️ could not run \(path): \(error)")
            return -1
        }
    }

    // MARK: - Proof

    /// Backs `GET /test/claude-rc` — what the row claims, and what tmux says,
    /// side by side. The two disagreeing is the only failure this feature has.
    func stateJSON() -> String {
        let tmux = Self.tmuxPath().map { "\"\($0)\"" } ?? "null"
        let script = Self.findScript().map { "\"\($0)\"" } ?? "null"
        let alive = isSessionAlive()
        let probe = probe()
        let stale = alive && ClaudeRemoteControlStaleness.staleReason(probe) != nil
        let restartReason = queue.sync { lastRestartReason }
        func str(_ v: String?) -> String {
            guard let v else { return "null" }
            let esc = v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(esc)\""
        }
        return "{\"enabled\":\(ClaudeRemoteControlSettings.isEnabled),"
            + "\"session\":\"\(Self.sessionName)\","
            + "\"alive\":\(alive),"
            + "\"watching\":\(timer != nil),"
            + "\"serverVersion\":\(str(probe.serverVersion)),"
            + "\"installedVersion\":\(str(probe.installedVersion)),"
            + "\"serverBinaryExists\":\(probe.serverBinaryExists.map { "\($0)" } ?? "null"),"
            + "\"paneSpawnENOENT\":\(probe.paneShowsSpawnENOENT),"
            + "\"liveSessions\":\(probe.liveSessions),"
            + "\"stale\":\(stale),"
            + "\"staleReason\":\(str(alive ? ClaudeRemoteControlStaleness.staleReason(probe) : nil)),"
            + "\"lastRestartReason\":\(str(restartReason)),"
            + "\"tmux\":\(tmux),"
            + "\"script\":\(script)}"
    }
}
