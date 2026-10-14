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
    /// it holds, as a multiplication (2026-10-14, Victor: *"7×Claude +
    /// 1×/rc"*): `7×Claude`, and `7×Claude + 1×/rc` because that mode holds
    /// both. A zero drops its `N×` but keeps the word (*"if no rc is on, skip
    /// the 1x but still show /rc"*): `7×Claude + /rc`, `Claude + 1×/rc`.
    /// `nil` counts leave the bare words.
    static func label(_ mode: LidAwakeMode, counts: ClaudeActivity.WorkingCounts?) -> String {
        labelParts(mode, counts: counts).map(\.text).joined()
    }

    /// The row in pieces, so the digits can be coloured without searching the
    /// string for them: `.claude` / `.rc` mark the two counts.
    private enum Part { case plain(String), claude(Int), rc(Int)
        var text: String {
            switch self {
            case .plain(let s): return s
            case .claude(let n), .rc(let n): return "\(n)"
            }
        }
    }

    private static func labelParts(_ mode: LidAwakeMode, counts: ClaudeActivity.WorkingCounts?) -> [Part] {
        guard let counts, mode == .interactive || mode == .background else { return [.plain(label(mode))] }
        var parts: [Part] = [.plain("\(emoji(mode)) ")]
        if counts.claude > 0 { parts += [.claude(counts.claude), .plain("×")] }
        parts.append(.plain("Claude"))
        guard mode == .background else { return parts }
        parts.append(.plain(" + "))
        if counts.rc > 0 { parts += [.rc(counts.rc), .plain("×")] }
        parts.append(.plain("/rc"))
        return parts
    }

    /// The same row with its counts in the icon's colours (2026-10-13,
    /// Victor: *"the two in the menu name should also be displayed in green,
    /// just as the number"*): the digits only, the local count green, the
    /// `/rc` count red.
    static func attributedLabel(_ mode: LidAwakeMode, counts: ClaudeActivity.WorkingCounts?) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let row = NSMutableAttributedString()
        for part in labelParts(mode, counts: counts) {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            switch part {
            case .claude: attributes[.foregroundColor] = InsomniaIcon.countGreen
            case .rc: attributes[.foregroundColor] = InsomniaIcon.countRed
            case .plain: break
            }
            row.append(NSAttributedString(string: part.text, attributes: attributes))
        }
        return row
    }

    /// The disabled row on top of the menu while the internet gate has let
    /// go (2026-10-14, on a flight: a 🛏 under seven working sessions read as
    /// a contradiction). `nil` while there is no outage to explain.
    static func offlineNote(stalledFor: TimeInterval?) -> String? {
        guard let stalledFor else { return nil }
        return "📵 No internet for \(Int(stalledFor / 60)) min — Claude is parked, the Mac may sleep"
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
    /// **No digits while `stalled`** (2026-10-14, on a flight: *"7 claude
    /// instances were awake but icon said bed"*): past the internet gate's
    /// grace the sessions are parked, not working, and the bed is right —
    /// digits on it would say the opposite.
    static func iconCounts(_ counts: ClaudeActivity.WorkingCounts?, mode: LidAwakeMode, stalled: Bool = false) -> String {
        guard mode.holdsInteractive, !stalled, let counts else { return "" }
        let rc = mode.holdsRemote ? counts.rc : 0
        return (counts.claude > 0 ? "\(counts.claude)" : "") + (rc > 0 ? "/\(rc)" : "")
    }

    static let floorLabel = "Sleep under \(LidAwakePolicy.batteryFloorPercent)%"

    /// The classic Mac checkmark on the current mode.
    static func state(_ mode: LidAwakeMode, current: LidAwakeMode) -> NSControl.StateValue {
        mode == current ? .on : .off
    }

    /// The menu bar button's hover text: the mode, and what it is doing.
    static func tooltip(mode: LidAwakeMode, holding: Bool, stalled: Bool = false) -> String {
        let doing = holding ? "holding the Mac awake"
            : stalled ? "no internet, Claude is parked — the Mac may sleep" : "the Mac may sleep"
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

    /// **The digits sit on the coffee** (2026-10-13, Victor, in turns: *"not
    /// next to the coffee, but over it… a different colour… a border so you
    /// can still read it"* → *"centred on the coffee"* → *"barely visible…
    /// increase the contrast"* → *"raise a bit the digit, lower a bit the
    /// cup… they should not disturb the bottom part"*). 11pt heavy lime with
    /// a black outline, its glyph centred 16.5pt up the cup — over the cup's
    /// dark top, the coffee, and the menu bar's black above it, clear of the
    /// cup's body — with the cup at the bottom of an icon 7pt taller than it.
    /// Placed by eye from renders of 2, 3, 4 and 2/1 at four heights.
    /// Lime because none of the cups is green; the `/rc` half, slash
    /// included, in red (`countRed`).
    ///
    /// The outline is the digits drawn black 16 times around a 1.3pt circle,
    /// not a text stroke: a stroke that thick grows miter spikes off the
    /// corners of `2` and `/`. A template image can't carry a coloured badge,
    /// so the badged plain looks paint themselves white or black from the
    /// appearance they are drawn in; the image is redrawn when that changes.
    func image(digits: String) -> NSImage? {
        guard !digits.isEmpty, let base = image else { return image }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .heavy)
        let shadow = NSAttributedString(string: digits, attributes: [.font: font, .foregroundColor: NSColor.black])
        let body = NSMutableAttributedString(string: digits, attributes: [.font: font, .foregroundColor: Self.lime])
        let slash = (digits as NSString).range(of: "/")
        if slash.location != NSNotFound {
            body.addAttribute(.foregroundColor, value: Self.brightRed,
                              range: NSRange(location: slash.location, length: body.length - slash.location))
        }
        let text = body.size()
        let width = max(base.size.width, text.width + 3)
        let height = base.size.height + 7
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let spot = NSRect(x: (width - base.size.width) / 2, y: 0,
                              width: base.size.width, height: base.size.height)
            if base.isTemplate {
                let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                Self.tinted(base, dark ? .white : .black).draw(in: spot)
            } else {
                base.draw(in: spot)
            }
            // Centred over the coffee: the cup symbol's hollow top is at
            // x 10.25 of its 21pt width.
            let at = NSPoint(x: spot.minX + 10.25 * base.size.width / 21 - text.width / 2,
                             y: 16.5 * base.size.height / 16 - font.capHeight / 2 + font.descender)
            for step in 0..<16 {
                let angle = CGFloat(step) * .pi / 8
                shadow.draw(at: NSPoint(x: at.x + 1.3 * cos(angle), y: at.y + 1.3 * sin(angle)))
            }
            body.draw(at: at)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "\(base.accessibilityDescription ?? "Insomnia"), \(digits) working"
        return image
    }

    private static let lime = NSColor(srgbRed: 0.2, green: 1, blue: 0.2, alpha: 1)
    private static let brightRed = NSColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1)

    /// The counts' green in the menu rows, the icon's convention carried over:
    /// the icon's lime on a dark menu, a darker green on a light one, where
    /// lime would vanish into the white.
    static let countGreen = NSColor(name: "InsomniaCountGreen") { look in
        look.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? lime : NSColor(srgbRed: 0, green: 0.55, blue: 0, alpha: 1)
    }

    /// The remote count's red, icon and menu alike (2026-10-13, Victor: *"the
    /// rc should be in red"*): green is the sessions at the keyboard, red the
    /// ones from the phone. Darker on a light menu, like the green.
    static let countRed = NSColor(name: "InsomniaCountRed") { look in
        look.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? brightRed : NSColor(srgbRed: 0.8, green: 0, blue: 0, alpha: 1)
    }

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
