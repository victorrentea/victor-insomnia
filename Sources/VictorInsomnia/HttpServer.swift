import Foundation
import Network

/// Headless hooks on `127.0.0.1:55125`, so "why is it still awake?" is one
/// `curl` instead of a lid, a battery and an ear. Same paths the feature had
/// while it lived in Victor Addons (on 55123): only the port moved.
///
///   GET /ping                       → {"ok":true}
///   GET /test/lid-awake/state       → everything the decision is made from
///   GET /test/lid-awake/mode/<m>    → off | interactive | background | always
///   GET /test/lid-awake/flatline    → play the 🫀 flatline, flag untouched
///   GET /test/sleep-chime           → play the sleep tone (blocks ≤ 3 s)
///   GET /test/claude-activity       → which sessions count as working, and which are skipped
///   GET /test/claude-rc             → 🛰️ what the row claims next to what tmux holds
final class HttpServer {
    static let port: UInt16 = 55125

    private let lid: LidAwake
    private let remoteControl: ClaudeRemoteControl
    private let onModeChanged: () -> Void
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "victor-insomnia-http", qos: .utility)

    init(lid: LidAwake, remoteControl: ClaudeRemoteControl, onModeChanged: @escaping () -> Void) {
        self.lid = lid
        self.remoteControl = remoteControl
        self.onModeChanged = onModeChanged
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1",
                                                           port: NWEndpoint.Port(rawValue: Self.port)!)
        guard let listener = try? NWListener(using: params) else {
            insomniaError("HTTP: failed to bind port \(Self.port)")
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: insomniaInfo("HTTP test hooks on 127.0.0.1:\(Self.port)")
            case .failed(let err): insomniaError("HTTP server failed: \(err)")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let path = Self.path(of: raw)
            let (status, body) = self.respond(path)
            let reason = status == 200 ? "OK" : "Not Found"
            var out = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n".utf8)
            out.append(Data(body.utf8))
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    /// `GET /a/b?x=1 HTTP/1.1` → `/a/b`.
    static func path(of request: String) -> String {
        let parts = request.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return "" }
        return String(parts[1].split(separator: "?", maxSplits: 1).first ?? "")
    }

    private func respond(_ path: String) -> (Int, String) {
        switch path {
        case "/ping":
            return (200, "{\"ok\":true}")
        case "/test/lid-awake/state":
            return (200, lid.stateJSON())
        case let p where p.hasPrefix("/test/lid-awake/mode/"):
            guard let mode = LidAwakeMode(rawValue: String(p.dropFirst("/test/lid-awake/mode/".count))) else {
                return (404, "{\"error\":\"unknown mode\"}")
            }
            // Through the same call the menu uses, then the menu repaints:
            // a mode the menu disagrees with is the lie the tick prevents.
            DispatchQueue.main.sync { _ = lid.setMode(mode, source: .http) }
            DispatchQueue.main.async(execute: onModeChanged)
            return (200, lid.stateJSON())
        case "/test/lid-awake/flatline":
            lid.playFlatlineForTest()
            return (200, "{\"ok\":true}")
        case "/test/floor-overlay":
            DispatchQueue.main.async { FloorOverlay.show(battery: LidAwakePolicy.batteryFloorPercent - 1) }
            return (200, "{\"ok\":true}")
        case "/test/sleep-chime":
            SleepChime.sound()
            return (200, "{\"ok\":true}")
        case "/test/claude-activity":
            return (200, Self.claudeActivityJSON())
        case "/test/claude-rc":
            return (200, remoteControl.stateJSON())
        default:
            return (404, "{\"error\":\"not found\"}")
        }
    }

    private static func claudeActivityJSON() -> String {
        let working = ClaudeActivity.workingSessions()
        let helpers = ClaudeActivity.processTable()
            .filter { $0.name == "caffeinate" }
            .map(\.ppid)
            .compactMap { pid -> String? in
                guard let kind = ClaudeActivity.helperKind(of: pid) else { return nil }
                return "\(pid):\(kind)"
            }
        // Remote sessions are named apart from the rest: they are the half
        // with no `caffeinate`, so "working but not here" is the first thing
        // to check when the two disagree.
        let remote = ClaudeActivity.remoteWorkingSessions()
        let remoteOpen = ClaudeActivity.openRemoteSessions()
        // Holding a `caffeinate` but not `busy` — a session waiting for an
        // answer, or CodexBar's usage probe — with the status that excluded it.
        let presence = ClaudeActivity.presenceByPid()
        let notBusy = ClaudeActivity.caffeinatedSessions(
            in: ClaudeActivity.processTable(),
            executablePath: ClaudeActivity.executablePath(of:),
            helperKind: ClaudeActivity.helperKind(of:))
            .filter { !ClaudeActivity.isBusy(presence[$0], now: Date()) }
            .map { "\"\($0):\(presence[$0]?.status ?? "")\"" }
        return "{\"working\":[\(working.map(String.init).joined(separator: ","))],"
            + "\"remote\":[\(remote.map(String.init).joined(separator: ","))],"
            + "\"remote_open\":[\(remoteOpen.map(String.init).joined(separator: ","))],"
            + "\"skipped_not_busy\":[\(notBusy.joined(separator: ","))],"
            + "\"skipped_helpers\":[\(helpers.map { "\"\($0)\"" }.joined(separator: ","))]}"
    }
}
