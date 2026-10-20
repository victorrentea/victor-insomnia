import XCTest
@testable import VictorInsomnia

/// The menu bar icon: the mode picked in the menu — 🛏 Off, ☕ Claude
/// (plain) and Claude /rc (orange), ⚠️ Always — plus 🪫 with the floor ticked.
final class InsomniaIconTests: XCTestCase {

    /// 2026-10-19, Victor: "the bed icon should only be displayed if I
    /// selected Off… claude or claude /rc or always → a coffee cup… or a
    /// little warning if Always".
    func testTheIconIsTheModePicked() {
        XCTAssertEqual(InsomniaIcon.look(mode: .off), .bed)
        XCTAssertEqual(InsomniaIcon.look(mode: .interactive), .cup(.plain))
        XCTAssertEqual(InsomniaIcon.look(mode: .background), .cup(.orange))
        XCTAssertEqual(InsomniaIcon.look(mode: .always), .warning)
    }

    func testOnlyThePlainLooksAreTemplates() {
        // A template image is the one macOS paints white or black with the
        // menu bar — the bed and the plain cup must be, the coloured ones not.
        XCTAssertEqual(InsomniaIcon.bed.image?.isTemplate, true)
        XCTAssertEqual(InsomniaIcon.cup(.plain).image?.isTemplate, true)
        XCTAssertEqual(InsomniaIcon.cup(.orange).image?.isTemplate, false)
        XCTAssertEqual(InsomniaIcon.warning.image?.isTemplate, false)
    }

    /// 2026-10-19, Victor: "if <20 sleeps is selected ⇒ the menu bar icon
    /// should show the drained battery icon from the menu item".
    func testTheFloorPutsTheBatteryBesideTheIcon() throws {
        for look in [InsomniaIcon.bed, .cup(.plain), .cup(.orange), .warning] {
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
                       "the ⚠️ has no coffee to carry them")
    }

    /// 2026-10-20, Victor: `📵 Offline 13 min`, `Claude×2` in the menu and a
    /// bare cup — "they are working. They should show up on top of the coffee
    /// cup". Past the internet gate's grace they stay, gray: parked, not held.
    func testOfflineTheDigitsStayButGray() {
        let counts = ClaudeActivity.WorkingCounts(claude: 7, rc: 1)
        XCTAssertEqual(InsomniaMenu.iconCounts(counts, mode: .background), "8")
        XCTAssertEqual(InsomniaMenu.iconTint(counts, mode: .background, stalled: true), .parked)
        XCTAssertEqual(InsomniaMenu.iconTint(.init(claude: 0, rc: 2), mode: .background, stalled: true), .parked)
        XCTAssertEqual(InsomniaMenu.iconTint(counts, mode: .background, stalled: false), .working)
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .background, holding: false, stalled: true),
                       "Insomnia: Claude /rc — no internet, Claude is parked — the Mac may sleep")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: false, stalled: true, counts: .init(claude: 2, rc: 0)),
                       "Insomnia: Claude — no internet, Claude is parked — the Mac may sleep\n"
                       + "• 2 Claude sessions working in a terminal")
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

    /// Every lid opening on a plane used to buy five fresh minutes of holding.
    func testAWakeAfterAnOfflineSleepGetsOnlyAMinute() {
        let now = Date()
        XCTAssertEqual(InternetWatch.clockAfterWake(wentToSleepOffline: false, now: now), now)
        let offline = InternetWatch.clockAfterWake(wentToSleepOffline: true, now: now)
        XCTAssertEqual(LidAwakePolicy.offlineGrace - now.timeIntervalSince(offline), 60, accuracy: 0.001)
    }

    func testTheTooltipSaysWhatItIsDoing() {
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .background, holding: true),
                       "Insomnia: Claude /rc — holding the Mac awake")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: false),
                       "Insomnia: Claude — no Claude working — the Mac may sleep")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .off, holding: false),
                       "Insomnia: Off — the Mac may sleep")
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
                       "Insomnia: Always — holding the Mac awake no matter what")
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
