import SwiftUI

/// Native menu with a Liquid Glass trigger on supported systems.
/// The actual options remain platform menus, not a custom popover.
struct SpeechLanguageMenu: View {
    @Binding var selection: SpeechChoice
    let isDisabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                menu
                    .menuStyle(.button)
                    .buttonStyle(.glass)
            } else {
                menu
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .tint(StudioStyle.accent(for: colorScheme))
        .disabled(isDisabled)
        .accessibilityIdentifier("speechLanguageMenu")
    }

    private var menu: some View {
        Menu {
            ForEach(SpeechChoice.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    if selection == choice {
                        Label {
                            Text(choice.title)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(choice.title)
                    }
                }
            }
        } label: {
            Text(selection.title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 4)
        }
    }
}
