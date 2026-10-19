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
    /// it holds, then its count (2026-10-16, Victor: *"Claude×1 + /rc×1/3"*,
    /// reversing 2026-10-14's `7×Claude + 1×/rc`): `Claude×7`, and
    /// `Claude×7 + /rc×1/3` because that mode holds both — **`/rc` carries
    /// working of open**, the sessions busy from the phone over every phone
    /// session still alive, idle ones included. A zero drops its `×N` but keeps
    /// the word: `Claude + /rc×1/3`; `/rc` goes bare only with no remote session
    /// open at all, since `×0/3` still says three are there. `nil` counts leave
    /// the bare words.
    static func label(_ mode: LidAwakeMode, counts: ClaudeActivity.WorkingCounts?) -> String {
        labelParts(mode, counts: counts).map(\.text).joined()
    }

    /// The row in pieces, so the digits can be coloured without searching the
    /// string for them: `.count` marks a working count, `.dim` the `×` before
    /// it and the `/open` after it, in gray.
    private enum Part { case plain(String), count(Int), dim(String)
        var text: String {
            switch self {
            case .plain(let s), .dim(let s): return s
            case .count(let n): return "\(n)"
            }
        }
    }

    private static func labelParts(_ mode: LidAwakeMode, counts: ClaudeActivity.WorkingCounts?) -> [Part] {
        guard let counts, mode == .interactive || mode == .background else { return [.plain(label(mode))] }
        var parts: [Part] = [.plain("\(emoji(mode)) Claude")]
        if counts.claude > 0 { parts += [.dim("×"), .count(counts.claude)] }
        guard mode == .background else { return parts }
        parts.append(.plain(" + /rc"))
        let open = max(counts.rcOpen, counts.rc)
        if open > 0 { parts += [.dim("×"), .count(counts.rc), .dim("/\(open)")] }
        return parts
    }

    /// The same row with its working counts in the icon's green (2026-10-13,
    /// Victor: *"the two in the menu name should also be displayed in green,
    /// just as the number"*). The `/rc` one too since 2026-10-16 — it was red —
    /// because the icon now shows one sum and the two add up into it; the `×`
    /// and the `/open` gray.
    static func attributedLabel(_ mode: LidAwakeMode, counts: ClaudeActivity.WorkingCounts?) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let row = NSMutableAttributedString()
        for part in labelParts(mode, counts: counts) {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            switch part {
            case .count: attributes[.foregroundColor] = InsomniaIcon.countGreen
            case .dim: attributes[.foregroundColor] = NSColor.secondaryLabelColor
            case .plain: break
            }
            row.append(NSAttributedString(string: part.text, attributes: attributes))
        }
        return row
    }

    /// The disabled row on top of the menu while the internet gate has let
    /// go (2026-10-14, on a flight: a 🛏 under seven working sessions read as
    /// a contradiction). `nil` while there is no outage to explain.
    /// Short, because the widest row sets the width of the whole menu
    /// (2026-10-14); the rest of the sentence is `offlineTooltip`.
    static func offlineNote(stalledFor: TimeInterval?) -> String? {
        guard let stalledFor else { return nil }
        return "📵 Offline \(Int(stalledFor / 60)) min"
    }

    static let offlineTooltip = "No internet: the working Claude sessions are parked, not working — the Mac may sleep"

    /// The number on the coffee: the sessions working right now that keep
    /// the Mac up, **one sum** (2026-10-16, Victor: *"2 on the coffee, then
    /// Claude×1 + /rc×1"*; until then `claude/rc`, two halves, the remote one
    /// red). The `/rc` sessions count only where they keep the Mac up
    /// (`holdsRemote`: `Claude /rc`) — under `Claude` they count for nothing.
    /// Nothing at all when none works, when the mode is `Off` — the bed says
    /// it alone — or `Always`, whose ⚠️ has no coffee to carry them
    /// (2026-10-19). **No digits while `stalled`** (2026-10-14, on a flight):
    /// past the internet gate's grace the sessions are parked, not working.
    static func iconCounts(_ counts: ClaudeActivity.WorkingCounts?, mode: LidAwakeMode, stalled: Bool = false) -> String {
        guard mode.holdsInteractive, !mode.holdsRegardless, !stalled, let counts else { return "" }
        let total = counts.claude + (mode.holdsRemote ? counts.rc : 0)
        return total > 0 ? "\(total)" : ""
    }

    /// Short on purpose: the widest title sets the width of the whole menu.
    static let remoteControlLabel = "🛰️ Claude RC"
    static let remoteControlTooltip = "Keeps `claude remote-control` up in the detached tmux session \"claude-rc\", "
        + "checked every minute, so the phone can open new Claude sessions on this Mac. Unticking kills it."

    static let floorEmoji = "🪫"
    static let floorLabel = "\(floorEmoji) Sleep under \(LidAwakePolicy.batteryFloorPercent)%"

    /// The 🪫 beside the menu bar icon: the row ticked **and** the battery
    /// actually under the floor (2026-10-19, Victor: *"shouldn't show up unless
    /// I have checked the sleep under twenty [and] the battery is really under
    /// twenty"* — at 49% it was showing just for the tick).
    static func showsFloor(ticked: Bool, underFloor: Bool) -> Bool { ticked && underFloor }

    static let quitLabel = "Quit"
    static let quitHint = "⌘Q"
    static let checkMark = "✓"

    /// Whether a row is ticked — the current mode.
    static func isChecked(_ mode: LidAwakeMode, current: LidAwakeMode) -> Bool { mode == current }

    // MARK: - The right-hand column (2026-10-14)
    //
    // **No `NSMenuItem.state`, no `keyEquivalent`** — the same cure as Victor
    // Effects' ✨ menu, for the same two reasons (Victor: *"make insomnia menu
    // less wide, the same way you did for fx menu"*). One row in `.on` makes
    // `NSMenu` open a check gutter down the left of every row, and one native
    // ⌘Q adds a key-equivalent column of its own (~47 pt, measured in Effects'
    // `MenuBar.titleInsets`) to the right of every title. Both are replaced by
    // a single column drawn inside the titles, right-aligned on one tab stop:
    // ✓ on the current mode and on the floor switch, ⌘Q on Quit.

    /// Smallest gap between the longest title and the column.
    static let columnGap: CGFloat = 14

    static func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
    }

    /// Where the column's right edge goes: just past the longest title.
    static func tabStop(titles: [NSAttributedString]) -> CGFloat {
        let longest = titles.map { $0.size().width }.max() ?? 0
        return (longest + columnGap + max(width(checkMark), width(quitHint))).rounded(.up)
    }

    /// `title`, then a tab, then `mark` right-aligned at `tabStop`. An empty
    /// mark still gets its tab, so every row carries the same stop.
    static func columned(_ title: NSAttributedString, mark: String, tabStop: CGFloat) -> NSAttributedString {
        let row = NSMutableAttributedString(attributedString: title)
        row.append(NSAttributedString(string: "\t" + mark, attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabStop)]
        row.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: row.length))
        return row
    }

    static func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 0)])
    }

    /// The menu bar button's hover text: the mode, what it is doing, and —
    /// one line each — what the digits beside the icon count (2026-10-14,
    /// Victor: the bare *"holding the Mac awake"* left the digits unexplained).
    /// The lines follow `iconCounts`, so a digit the icon hides is not
    /// explained either. The 🪫 beside the icon gets the last line.
    static func tooltip(mode: LidAwakeMode, holding: Bool, stalled: Bool = false,
                        counts: ClaudeActivity.WorkingCounts? = nil, floor: Bool = false) -> String {
        let floorLine = floor ? ["\(floorEmoji) sleeps under \(LidAwakePolicy.batteryFloorPercent)% battery"] : []
        guard holding else {
            let why = stalled ? "no internet, Claude is parked — "
                : mode.holdsInteractive && !mode.holdsRegardless ? "no Claude working — " : ""
            return (["Insomnia: \(name(mode)) — \(why)the Mac may sleep"] + floorLine).joined(separator: "\n")
        }
        let lines = countLines(counts, mode: mode)
        let doing = mode.holdsRegardless ? "holding the Mac awake no matter what"
            : lines.isEmpty ? "holding the Mac awake" : "holding the Mac awake for:"
        return (["Insomnia: \(name(mode)) — \(doing)"] + lines + floorLine).joined(separator: "\n")
    }

    /// The icon's sum in words, one bullet per part of it.
    private static func countLines(_ counts: ClaudeActivity.WorkingCounts?, mode: LidAwakeMode) -> [String] {
        guard let counts, mode.holdsInteractive, !mode.holdsRegardless else { return [] }
        var lines: [String] = []
        if counts.claude > 0 { lines.append("• \(sessions(counts.claude)) working in a terminal") }
        if mode.holdsRemote, counts.rc > 0 {
            lines.append("• \(counts.rc) of \(max(counts.rcOpen, counts.rc)) remote-control (/rc) sessions working")
        }
        return lines
    }

    private static func sessions(_ n: Int) -> String {
        "\(n) Claude session\(n == 1 ? "" : "s")"
    }
}

/// What the menu bar shows: the **mode picked in the menu**, not whether
/// anything is being held right now (2026-10-19, Victor: *"the bed icon should
/// only be displayed if I selected Off… claude or claude /rc or always → a
/// coffee cup, with or without any numbers on it, or a little warning if
/// Always"*). Until then a staying-awake mode with no session working showed
/// the bed too; now the digits on the cup, or their absence, say whether
/// anything is working, and the tooltip says whether the Mac may sleep.
///
/// 🛏 for `Off`, never coloured. ☕ for `Claude` (plain, white/black like
/// every other menu bar icon) and `Claude /rc` (orange). ⚠️ for `Always`, the
/// menu row's own emoji. With **Sleep under 20%** ticked the menu row's 🪫
/// sits to the right of whichever it is (`image(digits:floor:)`).
enum InsomniaIcon: Equatable {
    case bed
    case cup(Tint)
    case warning

    enum Tint: Equatable { case plain, orange }

    static func look(mode: LidAwakeMode) -> InsomniaIcon {
        switch mode {
        case .off: return .bed
        case .interactive: return .cup(.plain)
        case .background: return .cup(.orange)
        case .always: return .warning
        }
    }

    /// The cup is an SF Symbol; the plain looks are template images, which
    /// macOS paints white or black to match the menu bar. The warning is the
    /// emoji, in its own colours.
    var image: NSImage? {
        switch self {
        case .bed: return Self.bedImage
        case .warning: return Self.warningImage
        case .cup(.plain):
            let image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Insomnia")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            image?.isTemplate = true
            return image
        case .cup(.orange):
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                .applying(.init(paletteColors: [.systemOrange]))
            let image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Insomnia")?
                .withSymbolConfiguration(config)
            image?.isTemplate = false
            return image
        }
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
    /// Lime because none of the cups is green.
    ///
    /// The outline is the digits drawn black 16 times around a 1.3pt circle,
    /// not a text stroke: a stroke that thick grows miter spikes off the
    /// corners of `2` and `/`. A template image can't carry a coloured badge,
    /// so the badged plain looks paint themselves white or black from the
    /// appearance they are drawn in; the image is redrawn when that changes.
    ///
    /// `floor` adds the 🪫 to the right, on the same baseline as the glyph
    /// (2026-10-19, Victor: *"if <20 sleeps is selected ⇒ the menu bar icon
    /// should show the drained battery icon from the menu item"*).
    func image(digits: String, floor: Bool = false) -> NSImage? {
        guard let base = image else { return nil }
        guard !digits.isEmpty || floor else { return base }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .heavy)
        let shadow = NSAttributedString(string: digits, attributes: [.font: font, .foregroundColor: NSColor.black])
        let body = NSAttributedString(string: digits, attributes: [.font: font, .foregroundColor: Self.lime])
        let text = digits.isEmpty ? .zero : body.size()
        let glyphWidth = max(base.size.width, digits.isEmpty ? 0 : text.width + 3)
        let mark = floor ? Self.floorImage : nil
        let width = glyphWidth + (mark.map { Self.floorGap + $0.size.width } ?? 0)
        let height = max(base.size.height + (digits.isEmpty ? 0 : 7), mark?.size.height ?? 0)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let spot = NSRect(x: (glyphWidth - base.size.width) / 2, y: 0,
                              width: base.size.width, height: base.size.height)
            if base.isTemplate {
                let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                Self.tinted(base, dark ? .white : .black).draw(in: spot)
            } else {
                base.draw(in: spot)
            }
            if let mark {
                mark.draw(in: NSRect(origin: NSPoint(x: glyphWidth + Self.floorGap, y: 0), size: mark.size))
            }
            guard !digits.isEmpty else { return true }
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
        image.accessibilityDescription = [base.accessibilityDescription ?? "Insomnia",
                                          digits.isEmpty ? nil : "\(digits) working",
                                          floor ? "sleeps under \(LidAwakePolicy.batteryFloorPercent)%" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        return image
    }

    static let floorGap: CGFloat = 2

    /// The menu rows' emoji, drawn as images: ⚠️ in the cup's place, 🪫 beside it.
    static let warningImage = emojiImage("⚠️", size: 13.5, description: "Insomnia: always awake")
    static let floorImage = emojiImage(InsomniaMenu.floorEmoji, size: 13, description: "battery floor")

    /// An emoji's glyph, cropped to its ink — the text's line box carries
    /// padding above and below that would push it off the bar's centre.
    private static func emojiImage(_ emoji: String, size: CGFloat, description: String) -> NSImage {
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let ink = text.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
        let image = NSImage(size: ink.size, flipped: false) { _ in
            text.draw(at: NSPoint(x: -ink.minX, y: -ink.minY))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = description
        return image
    }

    private static let lime = NSColor(srgbRed: 0.2, green: 1, blue: 0.2, alpha: 1)

    /// The counts' green in the menu rows, the icon's convention carried over:
    /// the icon's lime on a dark menu, a darker green on a light one, where
    /// lime would vanish into the white.
    static let countGreen = NSColor(name: "InsomniaCountGreen") { look in
        look.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? lime : NSColor(srgbRed: 0, green: 0.55, blue: 0, alpha: 1)
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
