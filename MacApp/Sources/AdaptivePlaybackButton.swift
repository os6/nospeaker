import SwiftUI

/// Interactive native Glass on macOS 27, stock Glass on macOS 26, and
/// standard bordered controls for earlier supported macOS versions.
struct AdaptivePlaybackButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let isPrimary: Bool
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 27.0, *) {
                button
                    .buttonStyle(.plain)
                    .glassEffect(
                        isPrimary ?
                            .regular.tint(StudioStyle.accent(for: colorScheme))
                                .interactive() :
                            .regular.interactive(),
                        in: .capsule
                    )
                    .modifier(ElasticGlassFeedback(isEnabled: isEnabled))
            } else if #available(macOS 26.0, *) {
                if isPrimary {
                    button
                        .buttonStyle(.glassProminent)
                        .tint(StudioStyle.accent(for: colorScheme))
                } else {
                    button.buttonStyle(.glass)
                }
            } else if isPrimary {
                button
                    .buttonStyle(.borderedProminent)
                    .tint(StudioStyle.accent(for: colorScheme))
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .disabled(!isEnabled)
    }

    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(isPrimary ? .white : .primary)
                .frame(minWidth: isPrimary ? 125 : 0, minHeight: 29)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .contentShape(Capsule())
        }
    }
}
