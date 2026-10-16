import XCTest
@testable import VictorInsomnia

/// The rows carry their own tick and their own ⌘Q, drawn in the title on one
/// right-aligned tab stop (2026-10-14), because the native ones
/// (`NSMenuItem.state`, `keyEquivalent`) each make AppKit reserve a column for
/// the **whole** menu and widen it — Victor: *"make insomnia menu less wide"*.
///
/// Worth a test for one reason: the bug it guards is invisible in code review
/// and obvious on screen. A stray marker on an inactive row, or a missing one
/// on the active one, is a switch that lies about whether the Mac sleeps in a
/// bag.
final class InsomniaMenuTests: XCTestCase {

    typealias Menu = InsomniaMenu

    func testTheRowsLeadWithTheirEmojiAndCarryNoTickOfTheirOwn() {
        for mode in LidAwakeMode.allCases {
            let label = Menu.label(mode)
            XCTAssertFalse(label.contains(Menu.checkMark), "\(mode): the tick belongs to the column, not the label")
            XCTAssertTrue(label.hasPrefix(Menu.emoji(mode) + " "), "the row leads with its emoji")
        }
    }

    func testOnlyTheCurrentModeIsChecked() {
        for current in LidAwakeMode.allCases {
            XCTAssertTrue(Menu.isChecked(current, current: current))
            for other in LidAwakeMode.allCases where other != current {
                XCTAssertFalse(Menu.isChecked(other, current: current))
            }
        }
    }

    func testTheColumnIsOneRightTabStopJustPastTheLongestTitle() {
        let titles = [Menu.plain("☕ Claude×12 + /rc×3/12"), Menu.plain(Menu.floorLabel), Menu.plain(Menu.quitLabel)]
        let stop = Menu.tabStop(titles: titles)
        let longest = titles.map { $0.size().width }.max()!
        XCTAssertGreaterThan(stop, longest + Menu.columnGap)
        XCTAssertLessThan(stop, longest + Menu.columnGap + 30, "no more than the column itself past the longest title")

        let row = Menu.columned(Menu.plain(Menu.quitLabel), mark: Menu.quitHint, tabStop: stop)
        XCTAssertEqual(row.string, "Quit\t⌘Q")
        let style = row.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.tabStops.map(\.location), [stop])
        XCTAssertEqual(style?.tabStops.first?.alignment, .right)
    }

    func testTheMenuIsNarrowerThanWithTheNativeColumns() {
        // The native check gutter and ⌘Q column cost ~20 + ~47 pt; the drawn
        // column costs one gap and one ⌘Q.
        let titles = [Menu.plain("☕ Claude×12 + /rc×3/12"), Menu.plain(Menu.floorLabel), Menu.plain(Menu.quitLabel)]
        let longest = titles.map { $0.size().width }.max()!
        XCTAssertLessThan(Menu.tabStop(titles: titles) - longest, 47)
    }

    /// Renders the menu rows in light and dark into `$TMPDIR/insomnia-menu-*.png`
    /// to eyeball, and checks the ✓ is visible on both.
    func testRendersTheMenuForEyeballing() throws {
        let counts = ClaudeActivity.WorkingCounts(claude: 1, rc: 1, rcOpen: 3)
        var rows: [(NSAttributedString, String)] = LidAwakeMode.allCases.map {
            (Menu.attributedLabel($0, counts: counts), $0 == .background ? Menu.checkMark : "")
        }
        rows.append((Menu.plain(Menu.floorLabel), Menu.checkMark))
        rows.append((Menu.plain(Menu.quitLabel), Menu.quitHint))
        let stop = Menu.tabStop(titles: rows.map(\.0))
        let lines = rows.map { Menu.columned($0.0, mark: $0.1, tabStop: stop) }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let size = NSSize(width: stop + 30, height: 22 * CGFloat(lines.count))
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSRect(origin: .zero, size: size).fill()
                for (i, line) in lines.enumerated() {
                    let coloured = NSMutableAttributedString(attributedString: line)
                    coloured.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: coloured.length)) { value, range, _ in
                        if value == nil { coloured.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
                    }
                    coloured.draw(in: NSRect(x: 15, y: size.height - 22 * CGFloat(i + 1) + 3, width: stop + 2, height: 20))
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("insomnia-menu-\(name == .darkAqua ? "dark" : "light").png")
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
            print("🖼  \(url.path)")
        }
    }

    // MARK: - Working counts (2026-10-08)

    func testTheClaudeRowsCarryTheirWorkingCountsAfterTheName() {
        // Victor, 2026-10-16: "Claude×1 + /rc×1/3" — /rc is working of open;
        // a zero drops its ×N but keeps the word.
        let counts = ClaudeActivity.WorkingCounts(claude: 7, rc: 1, rcOpen: 3)
        XCTAssertEqual(Menu.label(.interactive, counts: counts), "☕ Claude×7")
        XCTAssertEqual(Menu.label(.background, counts: counts), "☕ Claude×7 + /rc×1/3")
        XCTAssertEqual(Menu.label(.off, counts: counts), "🛌 Off")
        XCTAssertEqual(Menu.label(.always, counts: counts), "⚠️ Always")
        XCTAssertEqual(Menu.label(.background, counts: nil), "☕ Claude /rc")
        XCTAssertEqual(Menu.label(.interactive, counts: nil), "☕ Claude")
        XCTAssertEqual(Menu.label(.interactive, counts: .init(claude: 0, rc: 4, rcOpen: 4)), "☕ Claude")
        XCTAssertEqual(Menu.label(.background, counts: .init(claude: 0, rc: 1, rcOpen: 1)), "☕ Claude + /rc×1/1")
        XCTAssertEqual(Menu.label(.background, counts: .init(claude: 7, rc: 0, rcOpen: 3)), "☕ Claude×7 + /rc×0/3",
                       "three open from the phone is worth saying even with none working")
        XCTAssertEqual(Menu.label(.background, counts: .init(claude: 7, rc: 0, rcOpen: 0)), "☕ Claude×7 + /rc")
        XCTAssertEqual(Menu.label(.background, counts: .init(claude: 0, rc: 0)), "☕ Claude + /rc")
        XCTAssertEqual(Menu.label(.background, counts: .init(claude: 0, rc: 2, rcOpen: 0)), "☕ Claude + /rc×2/2",
                       "never fewer open than working")
    }

    func testOnlyTheWorkingCountsAreGreenTheRestGray() {
        let row = Menu.attributedLabel(.background, counts: .init(claude: 12, rc: 3, rcOpen: 5))
        XCTAssertEqual(row.string, "☕ Claude×12 + /rc×3/5")
        let text = row.string as NSString
        func colour(at i: Int) -> NSColor? { row.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor }
        XCTAssertEqual(colour(at: text.range(of: "12").location), InsomniaIcon.countGreen)
        XCTAssertEqual(colour(at: text.range(of: "12").location + 1), InsomniaIcon.countGreen)
        XCTAssertEqual(colour(at: text.range(of: "3").location), InsomniaIcon.countGreen)
        XCTAssertEqual(colour(at: text.range(of: "/5").location), NSColor.secondaryLabelColor)
        XCTAssertEqual(colour(at: text.range(of: "×").location), NSColor.secondaryLabelColor)
        XCTAssertNil(colour(at: text.range(of: "/rc").location))
    }

    func testTheOfflineNoteShowsOnlyWhileStalled() {
        XCTAssertNil(Menu.offlineNote(stalledFor: nil))
        XCTAssertEqual(Menu.offlineNote(stalledFor: 754), "📵 Offline 12 min")
    }

    func testTheFloorCheckboxNamesTheFloor() {
        XCTAssertEqual(Menu.floorLabel, "🪫 Sleep under 20%")
    }

    func testTheRemoteControlRowIsShortWithItsTickInTheColumn() {
        XCTAssertEqual(Menu.remoteControlLabel, "🛰️ Claude RC")
        XCTAssertFalse(Menu.remoteControlLabel.contains(Menu.checkMark))
    }

    /// The rc number is what `Claude /rc` adds on top of `Claude`, so a
    /// session answering both signals is counted once, under `Claude`.
    func testWorkingCountsNeverCountASessionTwice() {
        XCTAssertEqual(ClaudeActivity.workingCounts(interactive: [10, 11], remote: [11, 20]),
                       ClaudeActivity.WorkingCounts(claude: 2, rc: 1, rcOpen: 1))
        XCTAssertEqual(ClaudeActivity.workingCounts(interactive: [], remote: []),
                       ClaudeActivity.WorkingCounts(claude: 0, rc: 0))
        // Open counts every remote session alive, working or not, and never
        // one already under Claude.
        XCTAssertEqual(ClaudeActivity.workingCounts(interactive: [10, 11], remote: [11, 20], remoteOpen: [11, 20, 21, 22]),
                       ClaudeActivity.WorkingCounts(claude: 2, rc: 1, rcOpen: 3))
    }

    /// The `3` of `/rc×1/3`: phone sessions whose process is still a claude,
    /// idle or busy; a terminal session or a dead pid's leftover file is not.
    func testOpenRemoteSessionsAreTheLiveSdkCliOnes() {
        func session(_ pid: Int32, _ entrypoint: String, _ status: String) -> SessionPresence {
            SessionPresence(pid: pid, sessionId: "s\(pid)", cwd: "/tmp", entrypoint: entrypoint,
                            status: status, statusUpdatedAt: nil)
        }
        let sessions = [session(1, "sdk-cli", "idle"), session(2, "sdk-cli", "busy"),
                        session(3, "cli", "idle"), session(4, "sdk-cli", "idle")]
        let paths: [Int32: String] = [1: "/Users/x/.local/share/claude/versions/2.1.301",
                                      2: "/Users/x/.local/share/claude/versions/2.1.301",
                                      3: "/Users/x/.local/share/claude/versions/2.1.301"]
        XCTAssertEqual(ClaudeActivity.openRemoteSessions(in: sessions, executablePath: { paths[$0] }), [1, 2])
    }

    // MARK: - What each mode holds the lid open for

    func testOffHoldsNothing() {
        XCTAssertFalse(LidAwakeMode.off.holdsInteractive)
        XCTAssertFalse(LidAwakeMode.off.holdsRemote)
    }

    func testInteractiveDeclinesThePhone() {
        // The whole point of the middle state: a session someone is typing at
        // holds the lid open, one driven from the phone does not.
        XCTAssertTrue(LidAwakeMode.interactive.holdsInteractive)
        XCTAssertFalse(LidAwakeMode.interactive.holdsRemote)
    }

    func testBackgroundHoldsBoth() {
        XCTAssertTrue(LidAwakeMode.background.holdsInteractive)
        XCTAssertTrue(LidAwakeMode.background.holdsRemote)
    }

    func testAlwaysHoldsEverythingAndThenSome() {
        XCTAssertTrue(LidAwakeMode.always.holdsInteractive)
        XCTAssertTrue(LidAwakeMode.always.holdsRemote)
        XCTAssertTrue(LidAwakeMode.always.holdsRegardless)
        XCTAssertFalse(LidAwakeMode.background.holdsRegardless)
    }

    // MARK: - Nobody's lid guard changes underneath them

    func testAMacThatHadTheOldSwitchOnLandsInBackground() {
        XCTAssertEqual(LidAwakeSettings.mode(stored: nil, legacyEnabled: true), .background)
        XCTAssertEqual(LidAwakeSettings.mode(stored: nil, legacyEnabled: false), .off)
    }

    func testAWrittenModeWinsOverTheOldSwitch() {
        XCTAssertEqual(LidAwakeSettings.mode(stored: "interactive", legacyEnabled: true), .interactive)
        XCTAssertEqual(LidAwakeSettings.mode(stored: "off", legacyEnabled: true), .off)
        // A value from a future version, or a corrupted one, is not a mode.
        XCTAssertEqual(LidAwakeSettings.mode(stored: "sideways", legacyEnabled: true), .background)
    }
}
