import XCTest
@testable import VictorInsomnia

/// The 😴 rows carry their own tick, because the native one (`NSMenuItem.state`)
/// makes AppKit reserve a check column for the **whole** menu and shifts every
/// other row's text sideways — and this menu is read by the emoji at the start
/// of each row.
///
/// Worth a test for one reason: the bug it guards is invisible in code review
/// and obvious on screen. A stray marker on an inactive row, or a missing one
/// on the active one, is a switch that lies about whether the Mac sleeps in a
/// bag.
final class InsomniaMenuTests: XCTestCase {

    typealias Menu = InsomniaMenu

    func testTheRowsAreTheWordsAloneAndTheTickIsTheNativeOne() {
        // Victor asked for the classic Mac checkmark in this submenu
        // (2026-09-21): no marker in the text at all, the state carries it.
        // Since 2026-10-13 every row leads with its mode's emoji, so the check
        // column shifts all of them alike.
        for mode in LidAwakeMode.allCases {
            let label = Menu.label(mode)
            XCTAssertFalse(label.contains("✅"), "\(mode) must carry no tick of its own")
            XCTAssertTrue(label.hasPrefix(Menu.emoji(mode) + " "), "the row leads with its emoji")
        }
    }

    func testOnlyTheCurrentModeIsChecked() {
        for current in LidAwakeMode.allCases {
            XCTAssertEqual(Menu.state(current, current: current), .on)
            for other in LidAwakeMode.allCases where other != current {
                XCTAssertEqual(Menu.state(other, current: current), .off)
            }
        }
    }



    // MARK: - Working counts (2026-10-08)

    func testTheClaudeRowsCarryTheirWorkingCountsInBrackets() {
        let counts = ClaudeActivity.WorkingCounts(claude: 2, rc: 1)
        XCTAssertEqual(Menu.label(.interactive, counts: counts), "☕ Claude (2)")
        XCTAssertEqual(Menu.label(.background, counts: counts), "☕ Claude (2) /rc (1)")
        XCTAssertEqual(Menu.label(.off, counts: counts), "🛌 Off")
        XCTAssertEqual(Menu.label(.always, counts: counts), "⚠️ Always")
        XCTAssertEqual(Menu.label(.background, counts: nil), "☕ Claude /rc")
        XCTAssertEqual(Menu.label(.interactive, counts: nil), "☕ Claude")
        XCTAssertEqual(Menu.label(.interactive, counts: .init(claude: 0, rc: 4)), "☕ Claude")
        XCTAssertEqual(Menu.label(.background, counts: .init(claude: 0, rc: 1)), "☕ Claude /rc (1)")
        XCTAssertEqual(Menu.label(.background, counts: .init(claude: 2, rc: 0)), "☕ Claude (2) /rc")
    }

    func testTheFloorCheckboxNamesTheFloor() {
        XCTAssertEqual(Menu.floorLabel, "Sleep under 20%")
    }

    /// The rc number is what `Claude /rc` adds on top of `Claude`, so a
    /// session answering both signals is counted once, under `Claude`.
    func testWorkingCountsNeverCountASessionTwice() {
        XCTAssertEqual(ClaudeActivity.workingCounts(interactive: [10, 11], remote: [11, 20]),
                       ClaudeActivity.WorkingCounts(claude: 2, rc: 1))
        XCTAssertEqual(ClaudeActivity.workingCounts(interactive: [], remote: []),
                       ClaudeActivity.WorkingCounts(claude: 0, rc: 0))
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
