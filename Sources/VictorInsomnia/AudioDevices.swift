import CoreAudio
import Foundation

/// The few CoreAudio lookups the lid-shut sounds need: which device is the
/// Mac's own speaker, and what it is called. Found by transport rather than by
/// name — "MacBook Pro Speakers" is a localised string, and the built-in output
/// is the only device that answers `kAudioDeviceTransportTypeBuiltIn`.
enum AudioDevices {

    /// The built-in output by id — what `LidAwake` pins its pulse to.
    static func builtInOutputID() -> AudioDeviceID? {
        outputDeviceIDs().first { transportType($0) == kAudioDeviceTransportTypeBuiltIn }
    }

    static func deviceName(_ devID: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var nameSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(devID, &addr, 0, nil, &nameSize) == noErr else { return "?" }
        var n: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(devID, &addr, 0, nil, &nameSize, &n) == noErr else { return "?" }
        return (n?.takeRetainedValue() as String?) ?? "?"
    }

    /// CoreAudio's persistent UID for a device — the string `AVAudioPlayer.currentDevice`
    /// and `NSSound.playbackDeviceIdentifier` take.
    static func deviceUID(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uid: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    /// Every device with at least one output channel, in CoreAudio's order.
    private static func outputDeviceIDs() -> [AudioDeviceID] {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutputChannels)
    }

    private static func hasOutputChannels(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr else { return 0 }
        return transport
    }
}
