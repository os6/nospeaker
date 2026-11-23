import SwiftUI

extension ContentView {
    var sidebar: some View {
        SidebarContent(player: player)
    }
}

private struct SidebarContent: View {
    @ObservedObject var player: PlaybackController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "waveform.path")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 23, weight: .medium))
                    .frame(width: 43, height: 43)
                    .background(Color.primary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("NoSpeaker")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Trackpad Studio")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 22) {
                configuration("Speech language") {
                    Picker("Speech language", selection: $player.language) {
                        ForEach(SpeechChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(player.status.isBusy)
                }

                configuration("Audio output") {
                    Picker("Audio output", selection: $player.output) {
                        ForEach(SoundOutput.allCases) { output in
                            Text(output.title).tag(output)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .animation(
                        reduceMotion ? nil : .smooth(duration: 0.24),
                        value: player.output
                    )
                    .disabled(player.status.isBusy)
                }
            }

            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: player.output == .trackpad
                      ? "hand.point.up.left" : "speaker.wave.2")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.secondary)
                Group {
                    if player.output == .trackpad {
                        Text("Audio plays through the trackpad haptic motor.")
                    } else {
                        Text("Preview the motor signal on your Mac speakers.")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    Text("Voice")
                    Spacer()
                    Text(player.language.voice)
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: StudioStyle.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(StudioStyle.sidebar(for: colorScheme))
    }

    func configuration<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
