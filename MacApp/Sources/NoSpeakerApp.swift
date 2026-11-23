import SwiftUI

@main
struct NoSpeakerApp: App {
    @NSApplicationDelegateAdaptor(NoSpeakerAppDelegate.self)
    private var applicationDelegate
    @StateObject private var player = PlaybackController()
    @StateObject private var systemAppearance = SystemAppearanceMonitor()
    @AppStorage("displayLanguage") private var displayLanguage = "system"
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private var selectedLanguage: InterfaceLanguage {
        InterfaceLanguage(rawValue: displayLanguage) ?? .system
    }

    private var selectedTheme: InterfaceTheme {
        InterfaceTheme(rawValue: appearanceMode) ?? .system
    }

    private var resolvedScheme: ColorScheme {
        selectedTheme.preferredColorScheme ?? systemAppearance.scheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                player: player,
                languageCode: $displayLanguage,
                themeCode: $appearanceMode
            )
            .environment(\.locale, selectedLanguage.locale)
            .preferredColorScheme(resolvedScheme)
            .frame(minWidth: 810, minHeight: 540)
            .onAppear { applicationDelegate.playback = player }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Playback") {
                Button("Play") { player.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!player.canStart)
                Button("Stop") { player.stop() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!player.status.isBusy)
            }
        }
    }
}
