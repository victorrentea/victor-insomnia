import Foundation
import IOKit.ps

/// On the charger or on battery. No battery answering counts as AC — a desktop
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
}
