import SwiftUI

/// Direct, single-level macOS menus. The selected option is checked without
/// putting the choices into an unnecessary nested Picker submenu.
struct AppearanceToolbar: View {
    @Binding var languageCode: String
    @Binding var themeCode: String

    private var language: InterfaceLanguage {
        InterfaceLanguage(rawValue: languageCode) ?? .system
    }

    private var theme: InterfaceTheme {
        InterfaceTheme(rawValue: themeCode) ?? .system
    }

    var body: some View {
        Menu {
            ForEach(InterfaceLanguage.allCases) { choice in
                Button {
                    languageCode = choice.rawValue
                } label: {
                    selectionLabel(choice.title,
                                   selected: languageCode == choice.rawValue)
                }
            }
        } label: {
            Label {
                Text(language.title)
            } icon: {
                Image(systemName: "globe")
            }
        }
        .help("Display language")
        .accessibilityIdentifier("displayLanguageMenu")

        Menu {
            ForEach(InterfaceTheme.allCases) { choice in
                Button {
                    themeCode = choice.rawValue
                } label: {
                    selectionLabel(choice.title,
                                   selected: themeCode == choice.rawValue)
                }
            }
        } label: {
            Label {
                Text(theme.title)
            } icon: {
                Image(systemName: theme.icon)
            }
        }
        .help("Appearance")
        .accessibilityIdentifier("appearanceMenu")
    }

    @ViewBuilder
    private func selectionLabel(
        _ title: LocalizedStringKey, selected: Bool
    ) -> some View {
        if selected {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "checkmark")
            }
        } else {
            Text(title)
        }
    }
}
