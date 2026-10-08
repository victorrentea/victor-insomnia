import Foundation

/// Where the two recordings live — the 💓 heartbeat (`13_heartbeat.mp3`) and
/// the 🫀 flatline (`15_flatline.mp3`).
///
/// **Not in this repo.** They are not ours to publish, so they are read from
/// `~/.victor-insomnia/sounds/` (a folder or a symlink to one), or from
/// `$VICTOR_INSOMNIA_SOUNDS` when set. A Mac with neither still gets every
/// signal: `LidAwake` and `SleepChime` fall back to macOS's own system sounds
/// (`Pop` twice for a beat, `Submarine` for the long tone).
enum InsomniaSounds {
    static var dir: URL {
        if let env = ProcessInfo.processInfo.environment["VICTOR_INSOMNIA_SOUNDS"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".victor-insomnia/sounds")
    }

    static func url(for filename: String) -> URL? {
        let url = dir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
