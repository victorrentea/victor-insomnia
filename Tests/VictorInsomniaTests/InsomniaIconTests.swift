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

    func testTheTooltipSaysWhatItIsDoing() {
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .background, holding: true),
                       "Insomnia: Claude /rc — holding the Mac awake")
        XCTAssertEqual(InsomniaMenu.tooltip(mode: .interactive, holding: false),
                       "Insomnia: Claude — the Mac may sleep")
    }
}
