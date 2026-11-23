import SwiftUI

/// Use the actual Liquid Glass button styles on modern macOS, with the
/// platform-native bordered styles on older supported systems.
struct AdaptivePlaybackButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let isPrimary: Bool
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                if isPrimary {
                    button
                        .buttonStyle(.glassProminent)
                        .tint(StudioStyle.accent(for: colorScheme))
                } else {
                    button.buttonStyle(.glass)
                }
            } else {
                if isPrimary {
                    button
                        .buttonStyle(.borderedProminent)
                        .tint(StudioStyle.accent(for: colorScheme))
                } else {
                    button.buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.large)
        .disabled(!isEnabled)
    }

    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(minWidth: isPrimary ? 125 : 0)
        }
    }
}
