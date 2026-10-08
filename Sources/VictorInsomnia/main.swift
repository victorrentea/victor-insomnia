import AppKit
import Darwin
import Foundation

// --- Logs: /tmp/victor-insomnia.log however we were launched ---
// Under `open` (Login Items, Finder, start.sh) stdout goes to the unified log;
// redirect it so every launch writes the same file.
func redirectLogsIfNeeded() {
    var st = stat()
    let isRegular = fstat(fileno(stderr), &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
    if isRegular { return }
    let fd = open("/tmp/victor-insomnia.log", O_WRONLY | O_APPEND | O_CREAT, 0o644)
    if fd < 0 { return }
    setvbuf(stdout, nil, _IOLBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
    dup2(fd, fileno(stdout))
    dup2(fd, fileno(stderr))
    close(fd)
}
redirectLogsIfNeeded()

// --- One instance: a new launch replaces the old one ---
let pidFilePath = "/tmp/VictorInsomnia.pid"
let myPid = getpid()

func pidIsVictorInsomnia(_ pid: Int32) -> Bool {
    var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
    return String(cString: buf).contains("Victor Insomnia")
}

if let old = (try? String(contentsOfFile: pidFilePath, encoding: .utf8))
        .flatMap({ Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
   old != myPid, pidIsVictorInsomnia(old) {
    insomniaInfo("Stopping previous instance (pid \(old))")
    kill(old, SIGTERM)
    for _ in 0..<20 where kill(old, 0) == 0 { usleep(100_000) }
    if kill(old, 0) == 0 { kill(old, SIGKILL) }
}
try? "\(myPid)".write(toFile: pidFilePath, atomically: true, encoding: .utf8)

// --- The app ---
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lid = LidAwake()
    private var statusMenu: StatusMenu?
    private var http: HttpServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        insomniaInfo("Victor Insomnia starting (built \(BuildInfo.time))")
        SystemAudioActivity.chromeTabAudible = { AddonsChromeAudible.ask() }
        let menu = StatusMenu(lid: lid)
        statusMenu = menu
        lid.onHoldingChanged = { [weak menu] _ in menu?.refresh() }
        // The battery floor stood the feature down: the mode is `off` now.
        lid.onAutoDisabled = { [weak menu] pct in
            insomniaInfo("LidAwake: stood down at \(pct)% — mode is off")
            DispatchQueue.main.async { menu?.refresh() }
        }
        // Re-armed on launch when it was left on, so a restart cannot silently
        // drop the lid guard in the middle of a flight.
        lid.startIfEnabled()
        menu.refresh()
        let server = HttpServer(lid: lid) { [weak menu] in menu?.refresh() }
        server.start()
        http = server
    }

    func applicationWillTerminate(_ notification: Notification) {
        lid.releaseForQuit()
        if (try? String(contentsOfFile: pidFilePath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "\(myPid)" {
            try? FileManager.default.removeItem(atPath: pidFilePath)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
