import AppKit

/// The ☕ / 🛏 in the menu bar and its menu: the four modes, the battery
/// floor, Quit.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var modeItems: [LidAwakeMode: NSMenuItem] = [:]
    private var floorItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    /// `📵 No internet for N min…`, shown only while the internet gate has
    /// let go, so a 🛏 over working sessions explains itself.
    private let offlineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lid: LidAwake

    init(lid: LidAwake) {
        self.lid = lid
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        offlineItem.isEnabled = false
        offlineItem.isHidden = true
        offlineItem.toolTip = InsomniaMenu.offlineTooltip
        menu.addItem(offlineItem)
        for mode in LidAwakeMode.allCases {
            let item = NSMenuItem(title: InsomniaMenu.label(mode),
                                  action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            menu.addItem(item)
            modeItems[mode] = item
        }
        menu.addItem(.separator())
        floorItem = NSMenuItem(title: InsomniaMenu.floorLabel,
                               action: #selector(toggleFloor), keyEquivalent: "")
        floorItem.target = self
        menu.addItem(floorItem)
        menu.addItem(.separator())
        // No `keyEquivalent`: its column would widen the whole menu. ⌘Q is
        // drawn in the title and claimed in `menuHasKeyEquivalent` instead.
        quitItem = NSMenuItem(title: InsomniaMenu.quitLabel, action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        refresh()
    }

    /// Repaint everything from the truth: the stored mode and the held flag.
    func refresh() {
        let mode = LidAwakeSettings.mode
        let holding = lid.isHolding
        let stall = mode.holdsRegardless ? nil : lid.offlineStall
        let digits = InsomniaMenu.iconCounts(lid.counts, mode: mode, stalled: stall != nil)
        statusItem.button?.image = InsomniaIcon.look(mode: mode, holding: holding).image(digits: digits)
        statusItem.button?.toolTip = InsomniaMenu.tooltip(mode: mode, holding: holding, stalled: stall != nil,
                                                            counts: lid.counts)
        let note = InsomniaMenu.offlineNote(stalledFor: stall)
        offlineItem.title = note ?? ""
        offlineItem.isHidden = note == nil
        layOutRows(counts: lid.counts)
    }

    /// Every row's title, with the ✓ / ⌘Q column on one tab stop measured
    /// from the longest title (see `InsomniaMenu.columned`).
    private func layOutRows(counts: ClaudeActivity.WorkingCounts?) {
        let mode = LidAwakeSettings.mode
        var titles: [(NSMenuItem, NSAttributedString, String)] = LidAwakeMode.allCases.compactMap { each in
            guard let item = modeItems[each] else { return nil }
            return (item, InsomniaMenu.attributedLabel(each, counts: counts),
                    InsomniaMenu.isChecked(each, current: mode) ? InsomniaMenu.checkMark : "")
        }
        titles.append((floorItem, InsomniaMenu.plain(InsomniaMenu.floorLabel),
                       LidAwakeSettings.sleepsUnderFloor ? InsomniaMenu.checkMark : ""))
        titles.append((quitItem, InsomniaMenu.plain(InsomniaMenu.quitLabel), InsomniaMenu.quitHint))
        var widest = titles.map(\.1)
        if !offlineItem.isHidden { widest.append(InsomniaMenu.plain(offlineItem.title)) }
        let stop = InsomniaMenu.tabStop(titles: widest)
        for (item, title, mark) in titles {
            item.attributedTitle = InsomniaMenu.columned(title, mark: mark, tabStop: stop)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        refresh()
        layOutRows(counts: ClaudeActivity.workingCounts())
    }

    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    /// ⌘Q while the menu is open — the only time it could ever fire (a status
    /// item app never becomes key), and so the only time it is claimed.
    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent,
                              target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        guard menuIsOpen,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "q" else { return false }
        target.pointee = self
        action.pointee = #selector(quit)
        return true
    }
    private var menuIsOpen = false

    /// The kernel has the last word: `pmset` can refuse (a missing sudoers
    /// rule), and then `LidAwake` stores `off` — `refresh` shows that, never
    /// the mode that was asked for.
    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let wanted = LidAwakeMode(rawValue: raw) else { return }
        lid.setMode(wanted, source: .menu)
        refresh()
    }

    /// Read by the next tick; nothing to arm or disarm.
    @objc private func toggleFloor() {
        LidAwakeSettings.sleepsUnderFloor.toggle()
        insomniaInfo("LidAwake: sleep under \(LidAwakePolicy.batteryFloorPercent)% "
            + (LidAwakeSettings.sleepsUnderFloor ? "on" : "off — no battery floor"))
        refresh()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
