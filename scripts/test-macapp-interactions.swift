#!/usr/bin/env swift
// Optional integration test: requires Accessibility access and the running app.
// The motor is never activated: output is set to Speakers before Play is tested.
import AppKit
import ApplicationServices
import Foundation

func require(_ okay: @autoclosure () -> Bool, _ message: String) {
    guard okay() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func property(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(
        element, key as CFString, &result
    ) == .success ? result : nil
}
func field(_ element: AXUIElement, _ key: String) -> String {
    guard let result = property(element, key) else { return "" }
    return String(describing: result)
}
func find(
    _ parent: AXUIElement, role: String, description: String? = nil,
    identifier: String? = nil
) -> AXUIElement? {
    if field(parent, "AXRole") == role &&
        (description == nil || field(parent, "AXDescription") == description) &&
        (identifier == nil || field(parent, "AXIdentifier") == identifier) {
        return parent
    }
    for child in (property(parent, "AXChildren") as? [AXUIElement]) ?? [] {
        if let found = find(
            child, role: role, description: description, identifier: identifier
        ) { return found }
    }
    return nil
}
func center(_ element: AXUIElement) -> CGPoint {
    guard let rawOrigin = property(element, "AXPosition"),
          let rawSize = property(element, "AXSize") else {
        fatalError("Missing AX geometry")
    }
    let origin = rawOrigin as! AXValue
    let size = rawSize as! AXValue
    var point = CGPoint.zero, extent = CGSize.zero
    require(AXValueGetValue(origin, .cgPoint, &point), "AX origin")
    require(AXValueGetValue(size, .cgSize, &extent), "AX size")
    return CGPoint(x: point.x + extent.width / 2,
                   y: point.y + extent.height / 2)
}
func emit(_ type: CGEventType, _ point: CGPoint) {
    let event = CGEvent(
        mouseEventSource: nil, mouseType: type,
        mouseCursorPosition: point, mouseButton: .left
    )!
    event.post(tap: .cghidEventTap)
}
func click(_ location: CGPoint) {
    emit(.mouseMoved, location)
    Thread.sleep(forTimeInterval: 0.06)
    emit(.leftMouseDown, location)
    Thread.sleep(forTimeInterval: 0.07)
    emit(.leftMouseUp, location)
    Thread.sleep(forTimeInterval: 0.3)
}
func drag(_ start: CGPoint, to finish: CGPoint, inspect: (() -> Void)? = nil) {
    emit(.mouseMoved, start)
    Thread.sleep(forTimeInterval: 0.08)
    emit(.leftMouseDown, start)
    for step in 1...16 {
        let ratio = CGFloat(step) / 16
        emit(.leftMouseDragged, CGPoint(
            x: start.x + (finish.x - start.x) * ratio,
            y: start.y + (finish.y - start.y) * ratio
        ))
        Thread.sleep(forTimeInterval: 0.016)
    }
    Thread.sleep(forTimeInterval: 0.2)
    inspect?()
    emit(.leftMouseUp, finish)
    Thread.sleep(forTimeInterval: 0.32)
}

require(AXIsProcessTrusted(), "Enable Accessibility for terminal tests")
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "hu.nospeaker.mac"
}) else {
    fputs("FAIL: Open NoSpeaker.app before running this test\n", stderr)
    exit(1)
}
_ = app.activate(options: [.activateAllWindows])
Thread.sleep(forTimeInterval: 0.3)
let root = AXUIElementCreateApplication(app.processIdentifier)
func control(_ description: String) -> AXUIElement {
    let role = ["Trackpad", "Speakers"].contains(description) ?
        "AXRadioButton" : "AXButton"
    guard let element = find(root, role: role, description: description) else {
        fatalError("Missing button: \(description)")
    }
    return element
}
func statusText(_ fragment: String) -> Bool {
    func text(_ parent: AXUIElement) -> [String] {
        var result = field(parent, "AXRole") == "AXStaticText" ?
            [field(parent, "AXValue")] : []
        for child in (property(parent, "AXChildren") as? [AXUIElement]) ?? [] {
            result.append(contentsOf: text(child))
        }
        return result
    }
    return text(root).contains { $0.contains(fragment) }
}
func speakerPreviewSelected() -> Bool {
    statusText("Preview the motor") ||
        statusText("motor hangjának előnézete")
}

let trackpad = center(control("Trackpad"))
let speakers = center(control("Speakers"))
click(speakers)
require(speakerPreviewSelected(), "Speakers must be selected before Play")

drag(speakers, to: trackpad)
require(!speakerPreviewSelected(), "Dragging left must select Trackpad")
drag(trackpad, to: speakers)
require(speakerPreviewSelected(), "Dragging right must select Speakers")
print("PASS: output switch responds to clicks and bidirectional dragging")

require(find(root, role: "AXMenuButton", identifier: "speechLanguageMenu") != nil,
        "Speech language must use the native macOS Menu")
print("PASS: native macOS speech-language menu is accessible")

let play = center(control("Play"))
let moved = CGPoint(x: play.x + 45, y: play.y + 12)
drag(play, to: moved) {
    let during = center(control("Play"))
    require(abs(during.x - play.x) >= 3,
            "Glass button must elastically follow pointer drag")
}
require(abs(center(control("Play")).x - play.x) < 2,
        "Glass button must return after release")
require(statusText("Ready to play"), "Dragging Play must not start audio")
print("PASS: elastic Glass button drag does not activate playback")

require(speakerPreviewSelected(), "Refusing to start trackpad playback")
click(center(control("Play")))
require(!statusText("Ready to play"), "Clicking Play must start preparation")
click(center(control("Stop")))
let stopDeadline = Date().addingTimeInterval(3)
while !statusText("Ready to play") && Date() < stopDeadline {
    Thread.sleep(forTimeInterval: 0.12)
}
require(statusText("Ready to play"), "Stop must terminate speaker playback")
print("PASS: normal Play click and Stop remain functional (speaker only)")

click(trackpad)
print("PASS: controls restored to Trackpad output without motor playback")
