import Foundation

/// Where the two recordings live — the 💓 heartbeat (`13_heartbeat.mp3`) and
/// the 🫀 flatline (`15_flatline.mp3`).
///
/// Read from `~/.victor-insomnia/sounds/` (a folder or a symlink to one), or
/// from `$VICTOR_INSOMNIA_SOUNDS` when set — the maintainer's own recordings,
/// which are not ours to publish. **Otherwise the app's own copies**
/// (2026-10-14): `sounds/` in this repo, synthesized for it (own work, CC0) to
/// the same timings the code was tuned on — the beat window at 0.50 s, the
/// flatline's tone from 3.34 s — and copied into `Contents/Resources/sounds`
/// by `build-app.sh`. Only a dev build with neither falls back to macOS's
/// system sounds (`Pop` twice for a beat, `Submarine` for the long tone).
enum InsomniaSounds {
    static var dir: URL {
        if let env = ProcessInfo.processInfo.environment["VICTOR_INSOMNIA_SOUNDS"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".victor-insomnia/sounds")
    }

    static var bundledDir: URL? { Bundle.main.resourceURL?.appendingPathComponent("sounds") }

    static func url(for filename: String) -> URL? {
        for folder in [dir, bundledDir].compactMap({ $0 }) {
            let url = folder.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
