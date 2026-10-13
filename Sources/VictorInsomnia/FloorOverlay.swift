import AppKit

/// The caption for the battery floor's goodbye (2026-10-13).
///
/// The three Bassos and the flatline say *that* something is going down, not
/// *why*: at 19% on battery, lid open at the desk, Victor heard the dying pulse
/// and had to guess which of the app's sounds it was. The sound stays the
/// message for the bag; this is the same message for whoever is looking at the
/// screen.
///
/// Shown when the sound starts, not when the mode flips: the reason has to be
/// on screen while the sound is still in the ear. A click dismisses it,
/// otherwise it leaves on its own after `visibleFor`. That clock does not run
/// while the Mac sleeps, so a lid shut over it shows the rest of it on wake —
/// which is exactly when "why did it sleep?" gets asked.
@MainActor
enum FloorOverlay {
    static let visibleFor: TimeInterval = 30

    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(battery pct: Int) {
        hide()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let title = label("🪫 Battery \(pct)% — Insomnia stood down", size: 22, weight: .semibold)
        let body = label("Below the \(LidAwakePolicy.batteryFloorPercent)% floor: the Mac is no longer held awake "
                         + "with the lid shut, and the mode is now Off.", size: 14, weight: .regular)
        body.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 2
        background.layer?.borderColor = NSColor.systemRed.cgColor
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 460),
        ])
        background.addGestureRecognizer(NSClickGestureRecognizer(target: Dismiss.shared, action: #selector(Dismiss.click)))

        let size = background.fittingSize
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 40)
        let p = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = background
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isReleasedWhenClosed = false
        p.orderFrontRegardless()
        panel = p

        let work = DispatchWorkItem { hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleFor, execute: work)
    }

    static func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = .labelColor
        l.isSelectable = false
        return l
    }

    private final class Dismiss: NSObject {
        static let shared = Dismiss()
        @objc func click() { MainActor.assumeIsolated { FloorOverlay.hide() } }
    }
}
