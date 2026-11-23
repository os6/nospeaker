import AppKit
import SwiftUI

/// Use macOS's actual segmented control, as Calendar does. No custom
/// thumb geometry, blur layers, manual dragging or synthetic magnification.
struct NativeOutputSelector: NSViewRepresentable {
    @Binding var selection: SoundOutput
    let isDisabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ["Trackpad", "Speakers"],
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.segmentStyle = .automatic
        control.controlSize = .large
        control.setWidth(100, forSegment: 0)
        control.setWidth(100, forSegment: 1)
        control.setAccessibilityIdentifier("audioOutputSelector")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.isEnabled = !isDisabled
        control.selectedSegment = selection == .trackpad ? 0 : 1
        control.selectedSegmentBezelColor = StudioStyle.accentNS(
            for: colorScheme
        )
        control.setLabel(
            String(localized: "Trackpad", locale: locale), forSegment: 0
        )
        control.setLabel(
            String(localized: "Speakers", locale: locale), forSegment: 1
        )
    }

    final class Coordinator: NSObject {
        var selection: Binding<SoundOutput>

        init(selection: Binding<SoundOutput>) {
            self.selection = selection
        }

        @objc func changed(_ control: NSSegmentedControl) {
            selection.wrappedValue = control.selectedSegment == 0 ?
                .trackpad : .speakers
        }
    }
}
