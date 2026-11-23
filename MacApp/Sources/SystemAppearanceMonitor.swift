import AppKit
import SwiftUI

/// Resolve "System" to a concrete SwiftUI scheme. Passing nil to
/// preferredColorScheme after an explicit override can leave stale surfaces
/// on macOS; the app appearance remains system-owned.
@MainActor
final class SystemAppearanceMonitor: ObservableObject {
    @Published private(set) var scheme: ColorScheme
    private var appObserver: NSObjectProtocol?
    private var systemObserver: NSObjectProtocol?

    init() {
        scheme = Self.currentScheme()
        appObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        systemObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private static func currentScheme() -> ColorScheme {
        let appearance = NSApplication.shared.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
            .dark : .light
    }

    func refresh() {
        let current = Self.currentScheme()
        if scheme != current { scheme = current }
    }

    deinit {
        if let appObserver { NotificationCenter.default.removeObserver(appObserver) }
        if let systemObserver {
            DistributedNotificationCenter.default().removeObserver(systemObserver)
        }
    }
}
