import AppKit
import SwiftUI

func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

verify(InterfaceTheme.system.preferredColorScheme == nil,
       "System must not store a hardcoded light or dark override")
verify(InterfaceTheme.light.preferredColorScheme == .light &&
       InterfaceTheme.dark.preferredColorScheme == .dark,
       "Explicit color scheme preferences must remain distinct")
verify(InterfaceTheme.allCases.map(\.rawValue) == ["system", "light", "dark"],
       "Theme choices must remain stable for AppStorage")
verify(InterfaceLanguage.allCases.map(\.rawValue) == ["system", "hu", "en"],
       "UI language choices must remain stable for AppStorage")

MainActor.assumeIsolated {
    let monitor = SystemAppearanceMonitor()
    let systemIsDark = NSApplication.shared.effectiveAppearance
        .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let resolved = monitor.scheme
    verify(resolved == (systemIsDark ? .dark : .light),
           "System appearance must resolve from AppKit, never from a stale override")
}

print("PASS: theme persistence choices and native system appearance resolution")
