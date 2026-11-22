import Foundation
import Darwin

// MARK: - Touch (for "play it")

struct Contact { var down = false; var x: Float = 0; var y: Float = 0; var size: Float = 0 }
var touchLock = os_unfair_lock()
var currentContact = Contact()
var contact: Contact {
    os_unfair_lock_lock(&touchLock); defer { os_unfair_lock_unlock(&touchLock) }
    return currentContact
}
let touchCallback: FrameCallback = { _, data, count, _, _ in
    var best = Contact()
    if let data, count > 0 {
        for i in 0..<Int(count) {
            let rec = data.advanced(by: i * 96)
            let state = rec.load(fromByteOffset: 20, as: Int32.self)
            guard (3...5).contains(state) else { continue }
            best = Contact(down: true, x: rec.load(fromByteOffset: 32, as: Float.self),
                           y: rec.load(fromByteOffset: 36, as: Float.self), size: rec.load(fromByteOffset: 48, as: Float.self))
        }
    }
    os_unfair_lock_lock(&touchLock); currentContact = best; os_unfair_lock_unlock(&touchLock)
    return 0
}
/// Only the trackpad whose motor we opened.
func touchDevices() -> [UnsafeMutableRawPointer] {
    guard let deviceList, let getID else { return [] }
    return (0..<CFArrayGetCount(deviceList)).compactMap { i -> UnsafeMutableRawPointer? in
        guard let raw = CFArrayGetValueAtIndex(deviceList, i) else { return nil }
        let dev = UnsafeMutableRawPointer(mutating: raw)
        var id: UInt64 = 0
        return getID(dev, &id) == 0 && id == motorDeviceID ? dev : nil
    }
}
let unregisterCallback = resolveMultitouchSymbol("MTUnregisterContactFrameCallback", RegisterCallback.self)
func startTouch() -> Bool {
    guard let registerCallback, let deviceStart else { return false }
    let devs = touchDevices()
    let quiet = !terminalTaken
    if quiet { silenceOthers() }
    for d in devs { registerCallback(d, touchCallback); deviceStart(d, 0) }
    if quiet { usleep(200_000); unsilence() }
    return !devs.isEmpty
}
func stopTouch() {
    for d in touchDevices() {
        unregisterCallback?(d, touchCallback)
        deviceStop?(d)
    }
}
