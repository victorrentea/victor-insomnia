import Foundation

/// The whole decision of 🔋 Claude prevents sleep, pulled out of
/// the timer that drives it so it can be tested without a lid, a battery, a
/// process table or a beep.
///
/// **Two kinds of "stop", and they are not the same.** Claude going quiet is a
/// *soft* release: the kernel flag comes off, the Mac is allowed to sleep, and
/// the row **stays ticked** because the feature is still watching — the next
/// session to start work re-arms it without Victor touching anything. The
/// battery floor is a *hard* stand-down: the flag comes off and the feature
/// disarms itself, because continuing to watch would mean re-arming at 19%.
enum LidAwakePolicy {

    /// Below this, the flag comes off for good and the Mac is allowed to fall
    /// asleep on its closed lid — the point of the whole exercise is a flight,
    /// and a flight that ends with a flat battery has failed.
    static let batteryFloorPercent = 20

    /// Whether the charge is under the floor; an unreadable battery is not.
    static func isUnderFloor(_ battery: Int?) -> Bool {
        battery.map { $0 < batteryFloorPercent } ?? false
    }

    /// **Unticking "Sleep under 20%" lasts until the charger goes in**
    /// (2026-10-21, Victor: *"the first time you connect the laptop to power,
    /// the Sleep under 20 tick resets to true"*): whatever the battery when it
    /// came off, the first plug-in puts it back, so the next flight never
    /// starts without a floor. Replaces 2026-10-20's "back at 20%", which only
    /// covered an untick under the floor — one made at 19% on the build before
    /// it was still off the next morning at 100%. A plug-in is battery → AC;
    /// already on AC is not one, so an untick at the desk holds until the next.
    static func isPlugIn(wasOnAC: Bool, onAC: Bool) -> Bool { !wasOnAC && onAC }

    enum Action: String, CaseIterable, Equatable {
        /// A Claude is working, the lid is shut and we are on battery: hold the
        /// flag and sound the heartbeat.
        case beat
        /// A Claude is working, but the lid is open or we are on AC. Hold the
        /// flag, stay silent — a pulse every 10 s at the desk would make the
        /// feature unusable, and on AC this is the clamshell case macOS
        /// supports natively anyway.
        case hold
        /// Nothing is working. Clear the flag and let the Mac sleep, but keep
        /// watching: this is the ordinary end of a session, not a fault.
        case release
        /// Nothing is working, we were holding the lid open, and the lid is
        /// shut with nothing else keeping it up — on battery, or on AC with no
        /// external display (`clamshellCausesSleep`) — i.e. this release is
        /// about to `pmset sleepnow`.
        /// Sound the 🫀 Pulse effect's flatline (ends in a long tone), then
        /// release exactly as above. Since 2026-09-23 this no longer needs the
        /// pulse to have been running: Victor shut the lid right as the last
        /// Claude finished, the tick released before a single beat, and the
        /// Mac went down in total silence — "I must hear a long beep before it
        /// sleeps, so I know it is not stuck on heartbeat". The Mac is about
        /// to sleep and the pulse is the only thing that can say so: without
        /// this, the last thing the bag hears is a beat that is simply never
        /// followed by another, which is indistinguishable from the Mac having
        /// died.
        case farewell
        /// The battery floor. Clear the flag *and* untick the row.
        case standDown
    }

    /// - Parameter battery: percentage, or `nil` when it could not be read.
    ///   An unreadable battery is deliberately **not** a stand-down: the reader
    ///   failing is not evidence the charge is low, and taking the machine down
    ///   mid-flight on a missing number would be the worse of the two mistakes.
    /// - Parameter holding: whether we were holding the lid open as of the
    ///   previous tick. It is the only reason `.farewell` and `.release` differ:
    ///   the flatline marks the one transition that ends in `pmset sleepnow`,
    ///   and once the flag is down the next tick must not play it again.
    ///   Defaulting it to `false` keeps every caller that does not care on the
    ///   plain release.
    /// - Parameter clamshellCausesSleep: `AppleClamshellCausesSleep` — whether
    ///   macOS itself would sleep on this shut lid, i.e. no external display
    ///   is driving it in clamshell mode. On AC it is the difference between a
    ///   desk (the release changes nothing, stay silent) and a charger in a
    ///   bag (the release sleeps the Mac, so it is announced — 2026-09-23).
    ///   Defaulting to `false` keeps the AC callers on the silent release.
    /// - Parameter floorEnabled: the "Sleep under 20%" checkbox. `false` means
    ///   no stand-down at any charge; defaulting it keeps the floor.
    static func decide(
        enabled: Bool,
        always: Bool = false,
        claudeWorking: Bool,
        lidClosed: Bool,
        onAC: Bool,
        battery: Int?,
        holding: Bool = false,
        clamshellCausesSleep: Bool = false,
        floorEnabled: Bool = true,
        floor: Int = batteryFloorPercent
    ) -> Action {
        guard enabled else { return .release }

        // The floor is checked first, before anything can decide to hold or to
        // beat, so the tick that stands down does not also sound like a healthy
        // pulse. It does not apply on AC: at 4% and plugged in the number is
        // going up, and cutting the flag there would sleep the Mac for nothing.
        // "Sleep under 20%" unticked (2026-10-07) takes the floor away
        // entirely: the flag then rides the battery down to macOS's own
        // emergency sleep.
        if floorEnabled, !onAC, let battery, battery < floor { return .standDown }

        // The last Claude finished. If we were holding a shut lid on battery,
        // this release sleeps the Mac, so it is announced before it happens;
        // otherwise nothing is going down and the flag just comes off. Note this is
        // reached only while armed, so a deliberate disarm never sounds — the
        // flatline is for the sleep nobody asked for, not the one that was
        // clicked.
        //
        // **The network is not asked** (2026-10-20, Victor: *"the insomnia
        // behaviour shouldn't have anything to do with the internet
        // connection"* — that belongs to VicNet). A session waiting for the
        // network is still a working one; from 2026-09-15 to 10-20 it stopped
        // counting after 5 min offline. The battery floor is what catches a
        // bagged Mac that waits all night.
        let releaseSleeps = lidClosed && (!onAC || clamshellCausesSleep)
        // `always` holds whatever is (not) running.
        guard always || claudeWorking else { return (holding && releaseSleeps) ? .farewell : .release }

        return (lidClosed && !onAC) ? .beat : .hold
    }

    // MARK: - What is heard — docs/lid-close.puml

    /// The 🔊 boxes of **`docs/lid-close.puml`, the source of truth** for what
    /// the lid and the battery floor sound like (Victor, 2026-10-14). Every
    /// case is named in the diagram and every name there is a case here —
    /// `LidRulesDiagramTests` fails the build on a mismatch, so a rule is
    /// changed in the diagram first.
    ///
    /// The rule behind it: **the dying pulse only when the Mac is on battery,
    /// the lid is already shut, and then the work finishes or the battery
    /// crosses the floor**. A lid close that ends in sleep — no work, work
    /// that just finished, a battery already low, the mode off, on AC — plays
    /// only the flatline's long tone, *"to remind me nothing survived"*,
    /// without freaking out the room with a dying heart.
    enum Sound: String, CaseIterable, Equatable {
        /// Three lub-dubs back to back: the lid came down and the Mac stays up.
        case threeQuickBeats
        /// One lub-dub per tick: lid shut, on battery, still working.
        case heartbeat
        /// The whole 🫀 flatline — two last beats, then the long tone; after
        /// three Bassos when it is the battery floor.
        case dyingPulse
        /// Only the flatline's long tone (`SleepChime`): "the Mac is asleep".
        case flatTone
        /// Nothing: the lid is open, or nothing changed.
        case none
    }

    /// The lid just came down — the diagram's left branch. `action` is what
    /// `decide` answered for this same moment (`.release` while disarmed).
    ///
    /// - Parameter staysUpAnyway: the Mac would stay up without our flag — an
    ///   external display (`!AppleClamshellCausesSleep`) or a `SleepDisabled`
    ///   somebody else raised.
    static func soundOnLidClose(_ action: Action, staysUpAnyway: Bool) -> Sound {
        switch action {
        case .beat, .hold: return .threeQuickBeats
        case .release, .farewell, .standDown: return staysUpAnyway ? .threeQuickBeats : .flatTone
        }
    }

    /// The 10-second tick — the diagram's right branch.
    ///
    /// - Parameter wasBeating: the pulse was already running, so this beat is
    ///   one lub-dub rather than the three that open a run (work started
    ///   under a shut lid).
    static func soundOnTick(_ action: Action, lidClosed: Bool, onAC: Bool, wasBeating: Bool) -> Sound {
        switch action {
        case .beat: return wasBeating ? .heartbeat : .threeQuickBeats
        case .hold, .release: return .none
        // Lid open at the floor: `FloorOverlay` says it, the speaker does not
        // (2026-10-14) — a dying pulse at the desk is noise.
        // `.farewell` is a shut lid about to sleep. On AC (no external
        // display) the Mac is not dying, it is going to sleep: the tone alone.
        // (`decide` never sends the floor on AC nor a farewell with the lid
        // open; spelling them out keeps the rule true over every input.)
        case .standDown, .farewell:
            guard lidClosed else { return .none }
            return onAC ? .flatTone : .dyingPulse
        }
    }
}
