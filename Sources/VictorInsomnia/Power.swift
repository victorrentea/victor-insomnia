import Foundation
import IOKit.ps

/// On the charger or on battery, and the moment that changes. No battery answering counts as AC — a desktop
/// Mac, where none of this has anything to protect.
enum Power {
    static func isOnAC() -> Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as! [CFTypeRef]
        for src in list {
            if let desc = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
               let state = desc[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSACPowerValue
            }
        }
        return true
    }

    /// Calls `handler` on the main run loop each time the charger goes in
    /// (battery → AC), as macOS reports it — in every mode, ticking or not.
    /// Not at launch: starting on AC is not a plug-in.
    static func onPlugIn(_ handler: @escaping () -> Void) {
        plugInHandler = handler
        wasOnAC = isOnAC()
        guard let source = IOPSNotificationCreateRunLoopSource({ _ in Power.sourcesChanged() }, nil)?
            .takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private static var plugInHandler: (() -> Void)?
    private static var wasOnAC = true

    /// Fires on every power-source change, the percentage included.
    private static func sourcesChanged() {
        let onAC = isOnAC()
        defer { wasOnAC = onAC }
        if LidAwakePolicy.isPlugIn(wasOnAC: wasOnAC, onAC: onAC) { plugInHandler?() }
    }
}
