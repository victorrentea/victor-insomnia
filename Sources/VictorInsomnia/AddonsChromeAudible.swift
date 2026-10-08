import Foundation

/// "Is any Chrome tab audible?" — asked of Victor Addons, which owns the Chrome
/// extension's socket (`GET 127.0.0.1:55123/chrome/audible`).
///
/// Chrome holds an output stream open whether or not a tab is playing, so
/// without this answer Chrome always counts as music and the lid-shut volume
/// boost is refused. Addons not running, or slow, is `nil` — the old cautious
/// answer, Chrome counts as playing. Never waits more than a third of a second.
enum AddonsChromeAudible {
    static let url = URL(string: "http://127.0.0.1:55123/chrome/audible")!

    static func ask() -> Bool? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.3
        let done = DispatchSemaphore(value: 0)
        var answer: Bool?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { done.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            answer = json["audible"] as? Bool
        }.resume()
        _ = done.wait(timeout: .now() + 0.4)
        return answer
    }
}
