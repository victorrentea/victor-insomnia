import AppKit

/// The words on the menu rows, pure so they are tested rather than eyeballed.
///
/// `rc` = the sessions opened from the phone over Claude Code remote control.
enum InsomniaMenu {

    static func label(_ mode: LidAwakeMode) -> String {
        switch mode {
        case .off: return "Off"
        case .interactive: return "Claude"
        case .background: return "Claude /rc"
        case .always: return "Always"
        }
    }

    /// The rows with the count of sessions **working** right now — the ones
    /// that would actually keep the laptop from sleeping. Each row names what
    /// it holds: `Claude (2)`, and `Claude (2) /rc (1)` because that mode holds
    /// both. `nil` counts leave the bare words.
    static func label(_ mode: LidAwakeMode, counts: ClaudeActivity.WorkingCounts?) -> String {
        guard let counts else { return label(mode) }
        switch mode {
        case .interactive: return "Claude (\(counts.claude))"
        case .background: return "Claude (\(counts.claude)) /rc (\(counts.rc))"
        case .off, .always: return label(mode)
        }
    }

    static let floorLabel = "Sleep under \(LidAwakePolicy.batteryFloorPercent)%"

    /// The classic Mac checkmark on the current mode.
    static func state(_ mode: LidAwakeMode, current: LidAwakeMode) -> NSControl.StateValue {
        mode == current ? .on : .off
    }

    /// The menu bar button's hover text: the mode, and what it is doing.
    static func tooltip(mode: LidAwakeMode, holding: Bool) -> String {
        let doing = holding ? "holding the Mac awake" : "the Mac may sleep"
        return "Insomnia: \(label(mode)) — \(doing)"
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

    /// SF Symbols, so the plain ones are template images that macOS paints
    /// white or black to match the menu bar.
    var image: NSImage? {
        let name: String
        let color: NSColor?
        switch self {
        case .bed: name = "bed.double.fill"; color = nil
        case .cup(.plain): name = "cup.and.saucer.fill"; color = nil
        case .cup(.orange): name = "cup.and.saucer.fill"; color = .systemOrange
        case .cup(.red): name = "cup.and.saucer.fill"; color = .systemRed
        }
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let color { config = config.applying(.init(paletteColors: [color])) }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Insomnia")?
            .withSymbolConfiguration(config)
        image?.isTemplate = color == nil
        return image
    }
}
