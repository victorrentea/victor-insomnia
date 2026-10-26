import XCTest
@testable import VictorInsomnia

/// The menu bar icon: the mode picked in the menu — 🛏 Off, ☕ Claude
/// (plain) and Claude /rc (orange), the bed crossed out for Always — plus 🪫 with the floor ticked.
final class InsomniaIconTests: XCTestCase {

    /// 2026-10-19, Victor: "the bed icon should only be displayed if I
    /// selected Off… claude or claude /rc or always → a coffee cup… or a
    /// little warning if Always".
    func testTheIconIsTheModePicked() {
        XCTAssertEqual(InsomniaIcon.look(mode: .off), .bed)
        XCTAssertEqual(InsomniaIcon.look(mode: .interactive), .cup(.plain))
        XCTAssertEqual(InsomniaIcon.look(mode: .background), .cup(.orange))
        XCTAssertEqual(InsomniaIcon.look(mode: .always), .sleepless,
                       "2026-10-20, Victor: a bed crossed out, a small warning on top")
    }

    func testOnlyThePlainLooksAreTemplates() {
        // A template image is the one macOS paints white or black with the
        // menu bar — the bed and the plain cup must be, the coloured ones not.
        XCTAssertEqual(InsomniaIcon.bed.image?.isTemplate, true)
        XCTAssertEqual(InsomniaIcon.cup(.plain).image?.isTemplate, true)
        XCTAssertEqual(InsomniaIcon.cup(.orange).image?.isTemplate, false)
        XCTAssertEqual(InsomniaIcon.sleepless.image?.isTemplate, false)
    }

    /// 2026-10-19, Victor: "if <20 sleeps is selected ⇒ the menu bar icon
    /// should show the drained battery icon from the menu item".
    func testTheFloorPutsTheBatteryBesideTheIcon() throws {
        for look in [InsomniaIcon.bed, .cup(.plain), .cup(.orange), .sleepless] {
            let alone = try XCTUnwrap(look.image(digits: ""))
            let floored = try XCTUnwrap(look.image(digits: "", floor: true))
            XCTAssertEqual(floored.size.width, alone.size.width + InsomniaIcon.floorGap + InsomniaIcon.floorImage.size.width, "\(look)")
            XCTAssertFalse(floored.isTemplate, "a coloured 🪫 can't ride a template")
        }
        XCTAssertEqual(InsomniaIcon.bed.image(digits: "")?.isTemplate, true, "no floor, the bed stays a template")
    }

    /// 2026-10-19, Victor: the 🪫 only once the battery is really under 20%.
    func testTheBatteryShowsOnlyWhenTickedAndUnderTheFloor() {
        XCTAssertTrue(InsomniaMenu.showsFloor(ticked: true, underFloor: LidAwakePolicy.isUnderFloor(19)))
        XCTAssertFalse(InsomniaMenu.showsFloor(ticked: true, underFloor: LidAwakePolicy.isUnderFloor(20)))
        XCTAssertFalse(InsomniaMenu.showsFloor(ticked: true, underFloor: LidAwakePolicy.isUnderFloor(49)))
        XCTAssertFalse(InsomniaMenu.showsFloor(ticked: true, underFloor: LidAwakePolicy.isUnderFloor(nil)))
        XCTAssertFalse(InsomniaMenu.showsFloor(ticked: false, underFloor: LidAwakePolicy.isUnderFloor(5)))
    }

    func testTheDigitsSitOnTheCupWithoutWideningIt() {
        let cup = InsomniaIcon.cup(.plain)
        XCTAssertEqual(cup.image(digits: "")?.isTemplate, true)
        XCTAssertEqual(cup.image(digits: "2")?.isTemplate, false)
        XCTAssertEqual(cup.image(digits: "3")?.size.width, cup.image?.size.width)
    }

    /// 2026-10-16, Victor: "2 on the coffee, then Claude×1 + /rc×1/3" —
    /// one sum, the /rc part only where the mode holds the Mac up for it.
    func testTheDigitsAreOneSum() {
        let counts = ClaudeActivity.WorkingCounts(claude: 2, rc: 1, rcOpen: 3)
        XCTAssertEqual(InsomniaMenu.iconCounts(counts, mode: .interactive), "2")
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 0, rc: 3), mode: .interactive), "")
        XCTAssertEqual(InsomniaMenu.iconCounts(counts, mode: .background), "3")
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 4, rc: 0, rcOpen: 5), mode: .background), "4",
                       "open but idle /rc sessions are not on the coffee")
    }

    func testNoDigitsWhenNothingWorksOrTheModeIsOffOrAlways() {
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 0, rc: 0), mode: .interactive), "")
        XCTAssertEqual(InsomniaMenu.iconCounts(nil, mode: .background), "")
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 2, rc: 1), mode: .off), "")
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 2, rc: 1), mode: .always), "",
                       "the crossed-out bed has no coffee to carry them")
    }

    /// 2026-10-20, Victor: "/rc sessions in red font … over the coffee if
    /// ever left only with /rc active". Lime once a terminal one is in the sum.
    func testTheDigitsAreRedWhenOnlyRemoteSessionsWork() {
        XCTAssertEqual(InsomniaMenu.iconTint(.init(claude: 0, rc: 2, rcOpen: 3), mode: .background), .remote)
        XCTAssertEqual(InsomniaMenu.iconTint(.init(claude: 1, rc: 2, rcOpen: 3), mode: .background), .working)
        XCTAssertEqual(InsomniaMenu.iconTint(.init(claude: 1, rc: 0), mode: .background), .working)
        XCTAssertEqual(InsomniaMenu.iconTint(.init(claude: 0, rc: 2), mode: .interactive), .working,
                       "under Claude the /rc ones are not on the coffee at all")
    }

    func testTheTooltipSaysWhatItIsDoing() {
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .background, holding: true),
                       "Insomnia: Claude /rc — holding the Mac awake")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: false),
                       "Insomnia: Claude — no Claude working — the Mac may sleep")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .off, holding: false),
                       "Insomnia: Sleep on Lid Close — the Mac may sleep")
    }

    /// 2026-10-14, Victor: hovering the digits should say what they count.
    func testTheTooltipExplainsTheDigits() {
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .background, holding: true, counts: .init(claude: 2, rc: 1, rcOpen: 3)),
                       "Insomnia: Claude /rc — holding the Mac awake for:\n"
                       + "• 2 Claude sessions working in a terminal\n"
                       + "• 1 of 3 remote-control (/rc) sessions working")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: true, counts: .init(claude: 1, rc: 3)),
                       "Insomnia: Claude — holding the Mac awake for:\n"
                       + "• 1 Claude session working in a terminal")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .always, holding: true, counts: .init(claude: 0, rc: 1)),
                       "Insomnia: Never sleep — holding the Mac awake no matter what")
    }

    /// 2026-10-26: macOS 26.7.1 wiped the sudoers rule; the cup still showed
    /// a lime count and the tooltip blamed "no Claude working".
    func testARefusedPmsetIsShoutedNotBlamedOnIdleSessions() {
        let counts = ClaudeActivity.WorkingCounts(claude: 2, rc: 0)
        XCTAssertEqual(InsomniaMenu.iconCounts(counts, mode: .interactive, refused: true), "!")
        XCTAssertEqual(InsomniaMenu.iconTint(counts, mode: .interactive, refused: true), .remote)
        XCTAssertEqual(InsomniaMenu.iconCounts(counts, mode: .off, refused: true), "")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: false, counts: counts, refused: true),
                       "Insomnia: Claude — ⚠️ CANNOT hold the Mac awake: pmset was refused\n"
                       + "the sudoers rule is missing (a macOS update wipes it) — run ./install-sudoers.sh")
    }

    func testTheTooltipExplainsTheBattery() {
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: false, floor: true),
                       "Insomnia: Claude — no Claude working — the Mac may sleep\n"
                       + "🪫 sleeps under 20% battery")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: true, counts: .init(claude: 1, rc: 0), floor: true),
                       "Insomnia: Claude — holding the Mac awake for:\n"
                       + "• 1 Claude session working in a terminal\n"
                       + "🪫 sleeps under 20% battery")
    }
}
