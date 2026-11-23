import SwiftUI

/// A real Glass material track with a morphing, orange-tinted Glass thumb.
/// Older macOS versions retain the native segmented Picker.
struct GlassOutputSelector: View {
    @Binding var selection: SoundOutput
    let isDisabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumbNamespace

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                glassSelector
            } else {
                Picker("Audio output", selection: $selection) {
                    ForEach(SoundOutput.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.large)
            }
        }
        .disabled(isDisabled)
        .accessibilityIdentifier("audioOutputSelector")
    }

    @available(macOS 26.0, *)
    private var glassSelector: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SoundOutput.allCases) { option in
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                            selection = option
                        }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                selection == option ? .white : .primary
                            )
                            .frame(minWidth: 83, minHeight: 32)
                            .padding(.horizontal, 6)
                            .background {
                                if selection == option {
                                    Capsule()
                                        .fill(.clear)
                                        .glassEffect(
                                            .regular.tint(
                                                StudioStyle.accent(for: colorScheme)
                                            ).interactive(),
                                            in: .capsule
                                        )
                                        .matchedGeometryEffect(
                                            id: "outputThumb", in: thumbNamespace
                                        )
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                    .accessibilityAddTraits(
                        selection == option ? [.isSelected] : []
                    )
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
        }
    }
}
