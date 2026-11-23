import AppKit

/// The 🛏 / ☕ / crossed-out 🛏 (+ 🪫) in the menu bar and its menu: the four modes, 🔌 Awake on AC, the battery
/// floor, the 💓 sounds, the 🛰️ Claude RC watchdog, Quit.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var modeItems: [LidAwakeMode: NSMenuItem] = [:]
    private var awakeOnACItem: NSMenuItem!
    private var floorItem: NSMenuItem!
    private var soundsItem: NSMenuItem!
    private var remoteControlItem: NSMenuItem!
    private var backgroundItem: NSMenuItem!
    private let backgroundMenu = NSMenu()
    private var quitItem: NSMenuItem!
    private let lid: LidAwake
    private let remoteControl: ClaudeRemoteControl

    init(lid: LidAwake, remoteControl: ClaudeRemoteControl) {
        self.lid = lid
        self.remoteControl = remoteControl
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        for mode in LidAwakeMode.allCases {
            let item = NSMenuItem(title: InsomniaMenu.label(mode),
                                  action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            menu.addItem(item)
            modeItems[mode] = item
        }
        menu.addItem(.separator())
        awakeOnACItem = NSMenuItem(title: InsomniaMenu.awakeOnACLabel,
                                   action: #selector(toggleAwakeOnAC), keyEquivalent: "")
        awakeOnACItem.target = self
        awakeOnACItem.toolTip = InsomniaMenu.awakeOnACTooltip
        menu.addItem(awakeOnACItem)
        floorItem = NSMenuItem(title: InsomniaMenu.floorLabel,
                               action: #selector(toggleFloor), keyEquivalent: "")
        floorItem.target = self
        menu.addItem(floorItem)
        soundsItem = NSMenuItem(title: InsomniaMenu.soundsLabel,
                                action: #selector(toggleSounds), keyEquivalent: "")
        soundsItem.target = self
        soundsItem.toolTip = InsomniaMenu.soundsTooltip
        menu.addItem(soundsItem)
        remoteControlItem = NSMenuItem(title: InsomniaMenu.remoteControlLabel,
                                       action: #selector(toggleRemoteControl), keyEquivalent: "")
        remoteControlItem.target = self
        remoteControlItem.toolTip = InsomniaMenu.remoteControlTooltip
        menu.addItem(remoteControlItem)
        backgroundItem = NSMenuItem(title: InsomniaMenu.backgroundSessionsLabel, action: nil, keyEquivalent: "")
        backgroundItem.toolTip = InsomniaMenu.backgroundSessionsTooltip
        backgroundMenu.autoenablesItems = false
        backgroundItem.submenu = backgroundMenu
        menu.addItem(backgroundItem)
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
    /// `counts` overrides the last tick's — the menu passes a fresh read on
    /// open, so the digits on the cup and the ×N in the rows agree.
    func refresh(counts fresh: ClaudeActivity.WorkingCounts? = nil) {
        let mode = LidAwakeSettings.mode
        let holding = lid.isHolding
        let refused = lid.pmsetRefused
        let counts = fresh ?? lid.counts
        let digits = InsomniaMenu.iconCounts(counts, mode: mode, refused: refused)
        let tint = InsomniaMenu.iconTint(counts, mode: mode, refused: refused)
        let floor = InsomniaMenu.showsFloor(ticked: LidAwakeSettings.sleepsUnderFloor, underFloor: lid.underFloor)
        statusItem.button?.image = InsomniaIcon.look(mode: mode).image(digits: digits, tint: tint, floor: floor)
        statusItem.button?.toolTip = InsomniaMenu.tooltip(mode: mode, holding: holding,
                                                            counts: counts, floor: floor, refused: refused,
                                                            heldOnAC: LidAwakeSettings.staysAwakeOnAC && Power.isOnAC())
        layOutRows(counts: counts)
    }

    /// Every row's title, the ✓ in front on one tab stop (see `InsomniaMenu.row`).
    private func layOutRows(counts: ClaudeActivity.WorkingCounts?) {
        let mode = LidAwakeSettings.mode
        var rows: [(NSMenuItem, NSAttributedString, Bool)] = LidAwakeMode.allCases.compactMap { each in
            guard let item = modeItems[each] else { return nil }
            return (item, InsomniaMenu.attributedLabel(each, counts: counts), InsomniaMenu.isChecked(each, current: mode))
        }
        rows.append((awakeOnACItem, InsomniaMenu.plain(InsomniaMenu.awakeOnACLabel), LidAwakeSettings.staysAwakeOnAC))
        rows.append((floorItem, InsomniaMenu.plain(InsomniaMenu.floorLabel), LidAwakeSettings.sleepsUnderFloor))
        rows.append((soundsItem, InsomniaMenu.plain(InsomniaMenu.soundsLabel), LidAwakeSettings.playsSounds))
        rows.append((remoteControlItem, InsomniaMenu.plain(InsomniaMenu.remoteControlLabel),
                     ClaudeRemoteControlSettings.isEnabled))
        if !backgroundItem.isHidden {
            rows.append((backgroundItem, InsomniaMenu.plain(backgroundItem.title), false))
        }
        for (item, title, ticked) in rows {
            item.attributedTitle = InsomniaMenu.row(title, ticked: ticked)
        }
        quitItem.attributedTitle = InsomniaMenu.row(InsomniaMenu.quitTitle, ticked: false)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menuIsOpen = true
        fillBackgroundMenu()
        refresh(counts: ClaudeActivity.workingCounts())
    }

    /// 📡 Background: rebuilt on every open, hidden when there are none.
    private func fillBackgroundMenu() {
        let sessions = BackgroundSessions.list()
        backgroundMenu.removeAllItems()
        backgroundItem.isHidden = sessions.isEmpty
        backgroundItem.title = InsomniaMenu.backgroundSessionsLabel(count: sessions.count)
        for session in sessions {
            let item = NSMenuItem(title: InsomniaMenu.backgroundSessionRow(title: session.title, busy: session.isBusy),
                                  action: #selector(takeOverBackgroundSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = BackgroundSessionBox(session)
            item.toolTip = InsomniaMenu.backgroundSessionTooltip(cwd: session.cwd, busy: session.isBusy)
            backgroundMenu.addItem(item)
        }
    }

    /// Mid-turn, the move cuts the turn short — asked first, never silently.
    @objc private func takeOverBackgroundSession(_ sender: NSMenuItem) {
        guard let session = (sender.representedObject as? BackgroundSessionBox)?.session else { return }
        if session.isBusy {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = InsomniaMenu.backgroundBusyTitle
            alert.informativeText = InsomniaMenu.backgroundBusyText(title: session.title)
            alert.addButton(withTitle: InsomniaMenu.backgroundBusyConfirm)
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try BackgroundSessions.takeOver(session)
            } catch {
                insomniaError("BackgroundSessions: \(session.bridgeSessionId): \(error)")
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = InsomniaMenu.backgroundFailedTitle
                    alert.informativeText = "\(error)"
                    alert.runModal()
                }
            }
        }
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

    /// Lands at once: in `Off` this tick is what starts and stops the watch.
    @objc private func toggleAwakeOnAC() {
        lid.setAwakeOnAC(!LidAwakeSettings.staysAwakeOnAC, source: .menu)
        refresh()
    }

    /// Read by the next tick; nothing to arm or disarm. Unticked, it comes
    /// back by itself at the next plug-in (`restoreFloorOnPlugIn`).
    @objc private func toggleFloor() {
        LidAwakeSettings.sleepsUnderFloor.toggle()
        insomniaInfo("LidAwake: sleep under \(LidAwakePolicy.batteryFloorPercent)% "
            + (LidAwakeSettings.sleepsUnderFloor ? "on"
               : "off until the charger is plugged in"))
        refresh()
    }

    /// Read at the next sound; the lid logic does not change.
    @objc private func toggleSounds() {
        LidAwakeSettings.playsSounds.toggle()
        insomniaInfo("LidAwake: sounds " + (LidAwakeSettings.playsSounds ? "on" : "off"))
        refresh()
    }

    /// Unticking kills the `claude-rc` tmux session once — and with it any
    /// session open from the phone; ticking starts it and watches it.
    @objc private func toggleRemoteControl() {
        remoteControl.setEnabled(!ClaudeRemoteControlSettings.isEnabled)
        refresh()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

/// `representedObject` wants a class.
private final class BackgroundSessionBox: NSObject {
    let session: BackgroundSession
    init(_ session: BackgroundSession) { self.session = session }
}
