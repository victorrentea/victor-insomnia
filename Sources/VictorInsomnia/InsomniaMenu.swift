import AppKit

/// The words on the menu rows, pure so they are tested rather than eyeballed.
///
/// `rc` = the sessions opened from the phone over Claude Code remote control.
enum InsomniaMenu {

    /// The mode's bare name, for the tooltip.
    static func name(_ mode: LidAwakeMode) -> String {
        switch mode {
        case .off: return "Off"
        case .interactive: return "Claude"
        case .background: return "Claude /rc"
        case .always: return "Always"
        }
    }

    /// Leads each row (2026-10-13): what the mode does to the Mac at a
    /// glance — sleeps, stays up for Claude, stays up no matter what.
    static func emoji(_ mode: LidAwakeMode) -> String {
        switch mode {
        case .off: return "🛌"
        case .interactive, .background: return "☕"
        case .always: return "⚠️"
        }
    }

    static func label(_ mode: LidAwakeMode) -> String { "\(emoji(mode)) \(name(mode))" }

    /// The rows with the count of sessions **working** right now — the ones
    /// that would actually keep the laptop from sleeping. Each row names what
    /// it holds: `Claude (2)`, and `Claude (2) /rc (1)` because that mode holds
    /// both. `nil` counts leave the bare words.
    static func label(_ mode: LidAwakeMode, counts: ClaudeActivity.WorkingCounts?) -> String {
        guard let counts else { return label(mode) }
        switch mode {
        case .interactive: return "\(emoji(mode)) Claude (\(counts.claude))"
        case .background: return "\(emoji(mode)) Claude (\(counts.claude)) /rc (\(counts.rc))"
        case .off, .always: return label(mode)
        }
    }

    /// The two small digits beside the menu bar icon (2026-10-13, Victor:
    /// *"how many instances of Claude slash how many remote instances"*):
    /// `claude/rc`, the sessions working right now, each half shown only when
    /// it is not zero: `2`, `/1`, `2/1` — the slash marks the remote number.
    /// Nothing at all when no session works, or when the mode is `Off` and
    /// none of them would keep the Mac up anyway — the bed says it alone.
    static func iconCounts(_ counts: ClaudeActivity.WorkingCounts?, mode: LidAwakeMode) -> String {
        guard mode != .off, let counts else { return "" }
        return (counts.claude > 0 ? "\(counts.claude)" : "") + (counts.rc > 0 ? "/\(counts.rc)" : "")
    }

    static let floorLabel = "Sleep under \(LidAwakePolicy.batteryFloorPercent)%"

    /// The classic Mac checkmark on the current mode.
    static func state(_ mode: LidAwakeMode, current: LidAwakeMode) -> NSControl.StateValue {
        mode == current ? .on : .off
    }

    /// The menu bar button's hover text: the mode, and what it is doing.
    static func tooltip(mode: LidAwakeMode, holding: Bool) -> String {
        let doing = holding ? "holding the Mac awake" : "the Mac may sleep"
        return "Insomnia: \(name(mode)) — \(doing)"
    }
}

/// What the menu bar shows, decided from the mode and from whether this app is
/// holding the kernel flag up right now.
///
/// **🛏 whenever nothing is keeping the Mac awake** — Off, but also `Claude`
/// or `Claude /rc` with no session working: the mode says what it is *willing*
/// to stay up for, the icon says what is happening. **☕ while it holds**, and
/// the cup's colour says how far the mode goes: plain (white/black, like every
/// other menu bar icon) for `Claude`, orange for `Claude /rc`, red for
/// `Always`. The bed is never coloured.
enum InsomniaIcon: Equatable {
    case bed
    case cup(Tint)

    enum Tint: Equatable { case plain, orange, red }

    static func look(mode: LidAwakeMode, holding: Bool) -> InsomniaIcon {
        guard holding else { return .bed }
        switch mode {
        case .off: return .bed
        case .interactive: return .cup(.plain)
        case .background: return .cup(.orange)
        case .always: return .cup(.red)
        }
    }

    /// The cup is an SF Symbol; the plain looks are template images, which
    /// macOS paints white or black to match the menu bar.
    var image: NSImage? {
        let color: NSColor
        switch self {
        case .bed: return Self.bedImage
        case .cup(.plain):
            let image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Insomnia")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            image?.isTemplate = true
            return image
        case .cup(.orange): color = .systemOrange
        case .cup(.red): color = .systemRed
        }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Insomnia")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }

    /// **🛏️, drawn** (2026-10-08, Victor: *"the bed should resemble this 🛏️"*).
    /// SF Symbols only has `bed.double`, a front view; the emoji is a single
    /// bed from the side — tall headboard, lower footboard, pillow tipped back
    /// against the head, blanket over the foot end. Monochrome template, so it
    /// is white or black with the menu bar, never coloured. Drawn on a
    /// 20 × 16 grid.
    static let bedImage: NSImage = {
        let image = NSImage(size: NSSize(width: 21, height: 16.8), flipped: false) { r in
            let s = r.width / 20
            func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat = 0) -> NSBezierPath {
                NSBezierPath(roundedRect: NSRect(x: x * s, y: y * s, width: w * s, height: h * s),
                             xRadius: rad * s, yRadius: rad * s)
            }
            NSColor.black.setFill()
            box(1, 0.5, 1.8, 14.5, 0.6).fill()     // headboard
            box(17.2, 0.5, 1.8, 10, 0.6).fill()    // footboard
            box(2.8, 2.2, 14.4, 2.4).fill()        // side rail
            box(2.8, 5.3, 6, 2.6).fill()           // mattress at the head end
            box(9.5, 5.3, 7.7, 3.6, 1).fill()      // blanket
            // The pillow, tipped back against the headboard.
            let pillow = box(3.3, 8.0, 4.6, 2.4, 1.2)
            var tilt = AffineTransform(translationByX: -5.7 * s, byY: -9.6 * s)
            tilt.append(AffineTransform(rotationByDegrees: -14))
            tilt.append(AffineTransform(translationByX: 5.7 * s, byY: 9.6 * s))
            pillow.transform(using: tilt)
            pillow.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Insomnia: the Mac may sleep"
        return image
    }()
}
