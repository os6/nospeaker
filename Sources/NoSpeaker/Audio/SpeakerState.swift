import Foundation
import Darwin
import CoreAudio

// MARK: - Speakers (are they muted? the proof)

/// True when the Mac's default output is muted or at zero volume; nil if it can't tell.
func speakersMuted() -> Bool? {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr else { return nil }
    var known = false
    var muted: UInt32 = 0
    size = 4
    addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    if AudioObjectHasProperty(device, &addr), AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr {
        known = true
        if muted != 0 { return true }
    }
    // Volume: the main element, else the first channel.
    for element in [kAudioObjectPropertyElementMain, 1] {
        var volume: Float32 = 1
        size = 4
        addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        if AudioObjectHasProperty(device, &addr), AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &volume) == noErr {
            return volume < 0.001
        }
    }
    return known ? false : nil
}
