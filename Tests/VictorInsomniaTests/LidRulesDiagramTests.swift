import XCTest
@testable import VictorInsomnia

/// **`docs/lid-close.puml` is the source of truth** for what happens, and what
/// is heard, when the lid closes and when the battery runs out (Victor,
/// 2026-10-14). These tests are what makes that more than a picture:
///
/// - the names in the diagram's boxes and the policy's enums are the same
///   two sets, so a rule cannot be added, renamed or dropped on one side only;
/// - each path through the diagram is one row of `paths`, run through
///   `LidAwakePolicy.decide` and `soundOnLidClose` / `soundOnTick`.
///
/// A rule changes in the diagram first, then here, then in the policy.
final class LidRulesDiagramTests: XCTestCase {

    private func diagram() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("docs/lid-close.puml"), encoding: .utf8)
    }

    /// `**name**` in the boxes (comments skipped), split into the 🔊 ones and the rest.
    private func names() throws -> (actions: Set<String>, sounds: Set<String>) {
        let boxes = try diagram().split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("'") }
            .joined(separator: "\n")
        let regex = try NSRegularExpression(pattern: "(🔊 )?\\*\\*([A-Za-z]+)\\*\\*")
        var actions = Set<String>(), sounds = Set<String>()
        for m in regex.matches(in: boxes, range: NSRange(boxes.startIndex..., in: boxes)) {
            let name = String(boxes[Range(m.range(at: 2), in: boxes)!])
            if m.range(at: 1).location != NSNotFound { sounds.insert(name) } else { actions.insert(name) }
        }
        // The legend's bold words are prose, not boxes.
        actions.subtract(["on", "already", "flat"])
        return (actions, sounds)
    }

    func testEveryActionInTheDiagramIsInThePolicyAndBack() throws {
        XCTAssertEqual(try names().actions, Set(LidAwakePolicy.Action.allCases.map(\.rawValue)))
    }

    func testEverySoundInTheDiagramIsInThePolicyAndBack() throws {
        XCTAssertEqual(try names().sounds, Set(LidAwakePolicy.Sound.allCases.map(\.rawValue)))
    }

    // MARK: - The paths

    private enum Event { case lidClosed, tick }

    private struct Path {
        let name: String
        let event: Event
        var armed = true
        var always = false
        var working = false
        var onAC = false
        var battery = 80
        var holding = false
        /// External display (`!AppleClamshellCausesSleep`).
        var externalDisplay = false
        /// `SleepDisabled` raised by something other than us.
        var heldBySomeoneElse = false
        /// The lid on the tick (a lid close is always closed).
        var lidClosed = true
        var wasBeating = false
        /// The 🔌 Awake on AC tick.
        var awakeOnAC = false
        let action: LidAwakePolicy.Action
        let sound: LidAwakePolicy.Sound
    }

    /// One row per path through `docs/lid-close.puml`, in the diagram's order.
    private let paths: [Path] = [
        // ── lid closed ──
        Path(name: "close, battery under the floor, a Claude working → flat tone, never the dying pulse",
             event: .lidClosed, working: true, battery: 15, holding: true, action: .standDown, sound: .flatTone),
        Path(name: "close, on battery, a Claude working → three quick beats",
             event: .lidClosed, working: true, holding: true, action: .beat, sound: .threeQuickBeats),
        Path(name: "close, on AC, a Claude working → three quick beats",
             event: .lidClosed, working: true, onAC: true, holding: true, action: .hold, sound: .threeQuickBeats),
        Path(name: "close, Always, nothing working → three quick beats",
             event: .lidClosed, always: true, holding: true, action: .beat, sound: .threeQuickBeats),
        Path(name: "close just as the last Claude finished (we were holding) → flat tone, not the dying pulse",
             event: .lidClosed, holding: true, action: .farewell, sound: .flatTone),
        Path(name: "close, armed, nothing working → flat tone",
             event: .lidClosed, action: .release, sound: .flatTone),
        Path(name: "close, mode Off → flat tone",
             event: .lidClosed, armed: false, action: .release, sound: .flatTone),
        Path(name: "close, mode Off, battery low → flat tone",
             event: .lidClosed, armed: false, battery: 10, action: .release, sound: .flatTone),
        Path(name: "close, mode Off, on AC → flat tone (every lid close sounds)",
             event: .lidClosed, armed: false, onAC: true, action: .release, sound: .flatTone),
        Path(name: "close on AC with an external display → three quick beats (clamshell stays up)",
             event: .lidClosed, armed: false, onAC: true, externalDisplay: true, action: .release, sound: .threeQuickBeats),
        Path(name: "close with SleepDisabled raised by someone else → three quick beats",
             event: .lidClosed, armed: false, heldBySomeoneElse: true, action: .release, sound: .threeQuickBeats),
        Path(name: "close, mode Off, on AC, 🔌 ticked → three quick beats, held",
             event: .lidClosed, armed: false, onAC: true, awakeOnAC: true, action: .hold, sound: .threeQuickBeats),
        Path(name: "close, Claude, nothing working, on AC, 🔌 ticked → three quick beats, held",
             event: .lidClosed, onAC: true, awakeOnAC: true, action: .hold, sound: .threeQuickBeats),
        Path(name: "close, mode Off, on battery, 🔌 ticked → flat tone: the tick is for the charger only",
             event: .lidClosed, armed: false, awakeOnAC: true, action: .release, sound: .flatTone),
        Path(name: "close, mode Off, on battery under the floor, 🔌 ticked → flat tone, nothing to stand down",
             event: .lidClosed, armed: false, battery: 10, awakeOnAC: true, action: .release, sound: .flatTone),

        // ── every 10 s ──
        Path(name: "tick, lid shut, on battery, crosses the floor → dying pulse",
             event: .tick, working: true, battery: 19, holding: true, wasBeating: true, action: .standDown, sound: .dyingPulse),
        Path(name: "tick, lid open, crosses the floor → none, the overlay says it",
             event: .tick, working: true, battery: 19, holding: true, lidClosed: false, action: .standDown, sound: .none),
        Path(name: "tick, lid shut, on battery, still working → heartbeat",
             event: .tick, working: true, holding: true, wasBeating: true, action: .beat, sound: .heartbeat),
        Path(name: "tick, lid shut, on battery, work starts → three quick beats open the run",
             event: .tick, working: true, action: .beat, sound: .threeQuickBeats),
        Path(name: "tick, lid open, working → silent hold",
             event: .tick, working: true, holding: true, lidClosed: false, action: .hold, sound: .none),
        Path(name: "tick, lid shut, on AC, working → silent hold",
             event: .tick, working: true, onAC: true, holding: true, action: .hold, sound: .none),
        Path(name: "tick, lid shut, on battery, the work finishes → dying pulse",
             event: .tick, holding: true, wasBeating: true, action: .farewell, sound: .dyingPulse),
        Path(name: "tick, lid shut, on AC without a display, the work finishes → flat tone",
             event: .tick, onAC: true, holding: true, action: .farewell, sound: .flatTone),
        Path(name: "tick, lid open, the work finishes → silent release",
             event: .tick, holding: true, lidClosed: false, action: .release, sound: .none),
        Path(name: "tick, lid shut on AC with a display, the work finishes → silent release",
             event: .tick, onAC: true, holding: true, externalDisplay: true, action: .release, sound: .none),
        Path(name: "tick, lid shut, on AC, mode Off, 🔌 ticked → silent hold",
             event: .tick, armed: false, onAC: true, holding: true, awakeOnAC: true, action: .hold, sound: .none),
        Path(name: "tick, lid shut, on AC, the work finishes, 🔌 ticked → still a silent hold",
             event: .tick, onAC: true, holding: true, awakeOnAC: true, action: .hold, sound: .none),
        Path(name: "tick, lid shut, mode Off, the charger comes out of a 🔌 hold → dying pulse",
             event: .tick, armed: false, holding: true, awakeOnAC: true, action: .farewell, sound: .dyingPulse),
        Path(name: "tick, lid shut, mode Off, on battery under the floor, 🔌 ticked → release, never a stand-down",
             event: .tick, armed: false, battery: 10, awakeOnAC: true, action: .release, sound: .none),
        Path(name: "tick, lid shut, on battery, a Claude working, 🔌 ticked → heartbeat, as without it",
             event: .tick, working: true, holding: true, wasBeating: true, awakeOnAC: true, action: .beat, sound: .heartbeat),
    ]

    func testEveryPathThroughTheDiagram() {
        for p in paths {
            let lidClosed = p.event == .lidClosed || p.lidClosed
            let action = LidAwakePolicy.decide(
                enabled: p.armed, always: p.always, claudeWorking: p.working,
                lidClosed: lidClosed, onAC: p.onAC, battery: p.battery, holding: p.holding,
                clamshellCausesSleep: !p.externalDisplay, awakeOnAC: p.awakeOnAC)
            XCTAssertEqual(action, p.action, p.name)
            let sound: LidAwakePolicy.Sound
            switch p.event {
            case .lidClosed:
                sound = LidAwakePolicy.soundOnLidClose(
                    action, staysUpAnyway: p.externalDisplay || p.heldBySomeoneElse)
            case .tick:
                sound = LidAwakePolicy.soundOnTick(
                    action, lidClosed: lidClosed, onAC: p.onAC, wasBeating: p.wasBeating)
            }
            XCTAssertEqual(sound, p.sound, p.name)
        }
    }

    /// 🔌 Awake on AC, over every input: on battery it changes no decision,
    /// and on the charger it never lets go.
    func testAwakeOnACDecidesOnlyOnTheCharger() {
        for armed in [false, true] { for always in [false, true] { for working in [false, true] {
            for lid in [false, true] { for holding in [false, true] { for battery in [10, 80] {
                func decide(onAC: Bool, tick: Bool) -> LidAwakePolicy.Action {
                    LidAwakePolicy.decide(enabled: armed, always: always, claudeWorking: working, lidClosed: lid,
                                          onAC: onAC, battery: battery, holding: holding,
                                          clamshellCausesSleep: true, awakeOnAC: tick)
                }
                let state = "armed:\(armed) always:\(always) working:\(working) lid:\(lid) holding:\(holding) \(battery)%"
                XCTAssertEqual(decide(onAC: true, tick: true), .hold, state)
                // Off never held anything on battery, so there the tick only
                // adds the goodbye for a hold of its own; armed, nothing moves.
                if armed { XCTAssertEqual(decide(onAC: false, tick: true), decide(onAC: false, tick: false), state) }
                else { XCTAssertEqual(decide(onAC: false, tick: true), holding && lid ? .farewell : .release, state) }
            } } }
        } } }
    }

    /// Victor's rule, stated over every input rather than the rows above:
    /// a lid close never plays the dying pulse, whatever the state.
    func testALidCloseNeverPlaysTheDyingPulse() {
        for action in LidAwakePolicy.Action.allCases {
            for staysUp in [false, true] {
                XCTAssertNotEqual(LidAwakePolicy.soundOnLidClose(action, staysUpAnyway: staysUp), .dyingPulse)
                XCTAssertNotEqual(LidAwakePolicy.soundOnLidClose(action, staysUpAnyway: staysUp), .none,
                                  "every lid close makes a sound: \(action)")
            }
        }
    }

    /// …and the dying pulse only ever plays on battery with the lid shut.
    func testTheDyingPulseOnlyOnBatteryWithTheLidShut() {
        for action in LidAwakePolicy.Action.allCases {
            for lid in [false, true] {
                for ac in [false, true] {
                    for beating in [false, true]
                    where LidAwakePolicy.soundOnTick(action, lidClosed: lid, onAC: ac, wasBeating: beating) == .dyingPulse {
                        XCTAssertTrue(lid && !ac, "\(action) lid:\(lid) ac:\(ac)")
                    }
                }
            }
        }
    }
}
