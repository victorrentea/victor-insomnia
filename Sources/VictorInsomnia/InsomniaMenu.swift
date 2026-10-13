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
    /// **The remote half only where remote sessions keep the Mac up**
    /// (`holdsRemote`: `Claude /rc`, `Always`; Victor, same day: *"display
    /// the remote sessions if and only if remote control is supposed to keep
    /// the laptop alive"*) — under `Claude` they count for nothing.
    static func iconCounts(_ counts: ClaudeActivity.WorkingCounts?, mode: LidAwakeMode) -> String {
        guard mode.holdsInteractive, let counts else { return "" }
        let rc = mode.holdsRemote ? counts.rc : 0
        return (counts.claude > 0 ? "\(counts.claude)" : "") + (rc > 0 ? "/\(rc)" : "")
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

    /// **The digits sit centred on the icon** (2026-10-13, Victor: *"not next
    /// to the coffee, but over it… a different colour… a border so you can
    /// still read it"*, then *"3 or 3/1 or /1 should stay centred on the
    /// coffee… bordered by one pixel, black"*; a top-right badge came first;
    /// then *"barely visible… as high as it can… increase the contrast"*):
    /// 11pt heavy lime under a thick black outline, nudged left onto the
    /// cup's body, off the handle; then *"the coffee cup a bit below and the
    /// three a bit higher"*, then *"a bit lower, so it fits the black area of
    /// the coffee"*: the glyph is centred on the cup's hollow top — the
    /// coffee — with the cup at the bottom of an icon 4pt taller than it, so
    /// the digit has room above the rim. Lime — none of the cups is
    /// green, so it never melts into an orange or red one — over a black
    /// outline that keeps it legible on a light menu bar too. Picked from
    /// yellow / green / teal / white / blue rendered on all three cups, dark
    /// and light. A template image can't carry a coloured badge, so the
    /// badged plain looks paint themselves white or black from the appearance
    /// they are drawn in; the image is redrawn when that changes.
    func image(digits: String) -> NSImage? {
        guard !digits.isEmpty, let base = image else { return image }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .heavy)
        let outline = NSAttributedString(string: digits, attributes: [
            .font: font, .strokeColor: NSColor.black, .strokeWidth: 28.0, .foregroundColor: NSColor.clear,
        ])
        let body = NSAttributedString(string: digits, attributes: [.font: font, .foregroundColor: Self.lime])
        let text = body.size()
        let width = max(base.size.width, text.width + 2)
        let height = base.size.height + 4
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let spot = NSRect(x: (width - base.size.width) / 2, y: 0,
                              width: base.size.width, height: base.size.height)
            if base.isTemplate {
                let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                Self.tinted(base, dark ? .white : .black).draw(in: spot)
            } else {
                base.draw(in: spot)
            }
            // Glyph centre on the coffee: the cup symbol's hollow top, measured
            // at x 10.25, y 12 of its 21 × 16.
            let at = NSPoint(x: spot.minX + 10.25 * base.size.width / 21 - text.width / 2,
                             y: 12 * base.size.height / 16 - font.capHeight / 2 + font.descender)
            outline.draw(at: at)
            body.draw(at: at)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "\(base.accessibilityDescription ?? "Insomnia"), \(digits) working"
        return image
    }

    private static let lime = NSColor(srgbRed: 0.2, green: 1, blue: 0.2, alpha: 1)

    private static func tinted(_ template: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: template.size, flipped: false) { r in
            template.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
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
