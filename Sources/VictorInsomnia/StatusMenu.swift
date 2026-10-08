import AppKit

/// The ☕ / 🛏 in the menu bar and its menu: the four modes, the battery
/// floor, Quit.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var modeItems: [LidAwakeMode: NSMenuItem] = [:]
    private var floorItem: NSMenuItem!
    private let lid: LidAwake

    init(lid: LidAwake) {
        self.lid = lid
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
        floorItem = NSMenuItem(title: InsomniaMenu.floorLabel,
                               action: #selector(toggleFloor), keyEquivalent: "")
        floorItem.target = self
        menu.addItem(floorItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Insomnia", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        refresh()
    }

    /// Repaint everything from the truth: the stored mode and the held flag.
    func refresh() {
        let mode = LidAwakeSettings.mode
        let holding = lid.isHolding
        statusItem.button?.image = InsomniaIcon.look(mode: mode, holding: holding).image
        statusItem.button?.toolTip = InsomniaMenu.tooltip(mode: mode, holding: holding)
        for (each, item) in modeItems { item.state = InsomniaMenu.state(each, current: mode) }
        floorItem.state = LidAwakeSettings.sleepsUnderFloor ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        let counts = ClaudeActivity.workingCounts()
        for (mode, item) in modeItems { item.title = InsomniaMenu.label(mode, counts: counts) }
        refresh()
    }

    /// The kernel has the last word: `pmset` can refuse (a missing sudoers
    /// rule), and then `LidAwake` stores `off` — `refresh` shows that, never
    /// the mode that was asked for.
    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let wanted = LidAwakeMode(rawValue: raw) else { return }
        lid.setMode(wanted)
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
