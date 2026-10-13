import XCTest
@testable import VictorInsomnia

/// The menu bar icon: 🛏 whenever nothing keeps the Mac awake, ☕ while it is
/// held, coloured by how far the mode goes.
final class InsomniaIconTests: XCTestCase {

    func testNothingHeldIsTheBedWhateverTheMode() {
        // Victor: even with a staying-awake mode picked, no Claude working
        // means the Mac will sleep — and the icon has to say so.
        for mode in LidAwakeMode.allCases {
            XCTAssertEqual(InsomniaIcon.look(mode: mode, holding: false), .bed, "\(mode)")
        }
    }

    func testOffIsTheBedEvenIfTheFlagIsSomehowUp() {
        XCTAssertEqual(InsomniaIcon.look(mode: .off, holding: true), .bed)
    }

    func testTheCupIsPlainOrangeOrRedByMode() {
        XCTAssertEqual(InsomniaIcon.look(mode: .interactive, holding: true), .cup(.plain))
        XCTAssertEqual(InsomniaIcon.look(mode: .background, holding: true), .cup(.orange))
        XCTAssertEqual(InsomniaIcon.look(mode: .always, holding: true), .cup(.red))
    }

    func testOnlyTheColouredCupsAreNotTemplates() {
        // A template image is the one macOS paints white or black with the
        // menu bar — the bed and the plain cup must be, the tinted cups not.
        XCTAssertEqual(InsomniaIcon.bed.image?.isTemplate, true)
        XCTAssertEqual(InsomniaIcon.cup(.plain).image?.isTemplate, true)
        XCTAssertEqual(InsomniaIcon.cup(.orange).image?.isTemplate, false)
        XCTAssertEqual(InsomniaIcon.cup(.red).image?.isTemplate, false)
    }

    func testMenuDigitsAreGreenAndTheRcOneRed() {
        let row = InsomniaMenu.attributedLabel(.background, counts: .init(claude: 12, rc: 0))
        XCTAssertEqual(row.string, "☕ Claude (12) /rc (0)")
        let text = row.string as NSString
        let colour = { (part: String) in
            row.attribute(.foregroundColor, at: text.range(of: part).location, effectiveRange: nil) as? NSColor
        }
        XCTAssertEqual(colour("12"), InsomniaIcon.countGreen)
        XCTAssertEqual(colour("0"), InsomniaIcon.countRed)
        XCTAssertNil(colour("Claude"))
        XCTAssertNil(colour("("))
    }

    func testTheDigitsSitOnTheCupWithoutWideningIt() {
        let cup = InsomniaIcon.cup(.plain)
        XCTAssertEqual(cup.image(digits: "")?.isTemplate, true)
        XCTAssertEqual(cup.image(digits: "2/1")?.isTemplate, false)
        XCTAssertEqual(cup.image(digits: "3")?.size.width, cup.image?.size.width)
    }

    func testTheDigitsAreClaudeSlashRc() {
        let counts = ClaudeActivity.WorkingCounts(claude: 2, rc: 1)
        XCTAssertEqual(InsomniaMenu.iconCounts(counts, mode: .interactive), "2")
        XCTAssertEqual(InsomniaMenu.iconCounts(counts, mode: .always), "2/1")
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 0, rc: 3), mode: .interactive), "")
        XCTAssertEqual(InsomniaMenu.iconCounts(counts, mode: .background), "2/1")
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 0, rc: 3), mode: .always), "/3")
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 4, rc: 0), mode: .background), "4")
    }

    func testNoDigitsWhenNothingWorksOrTheModeIsOff() {
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 0, rc: 0), mode: .interactive), "")
        XCTAssertEqual(InsomniaMenu.iconCounts(nil, mode: .background), "")
        XCTAssertEqual(InsomniaMenu.iconCounts(.init(claude: 2, rc: 1), mode: .off), "")
    }

    func testTheTooltipSaysWhatItIsDoing() {
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .background, holding: true),
                       "Insomnia: Claude /rc — holding the Mac awake")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: false),
                       "Insomnia: Claude — the Mac may sleep")
    }
}
