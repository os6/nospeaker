import SwiftUI

struct ContentView: View {
    @ObservedObject var player: PlaybackController
    @Binding var languageCode: String
    @Binding var themeCode: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.primary.opacity(0.085))
                .frame(width: 1)
            workArea
        }
        .background {
            StudioStyle.background(for: colorScheme)
                .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(" ")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(StudioStyle.accent(for: colorScheme))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                AppearanceToolbar(
                    languageCode: $languageCode,
                    themeCode: $themeCode
                )
            }
        }
        .alert("Playback error", isPresented: Binding(
            get: { player.error != nil },
            set: { if !$0 { player.error = nil } }
        )) {
            Button("OK", role: .cancel) { player.error = nil }
        } message: {
            VStack(alignment: .leading) {
                Text(player.error?.message ?? "")
                if let detail = player.error?.detail {
                    Text(verbatim: detail)
                }
            }
        }
    }

    private var workArea: some View {
        VStack(alignment: .leading, spacing: StudioStyle.spacing) {
            header

            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("TEXT")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(player.text.count.formatted())
                        Text("characters")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }

                WordTrackingEditor(
                    text: $player.text,
                    highlightedRange: player.activeRange,
                    editable: !player.status.isBusy
                )
                .accessibilityLabel("Text to speak")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StudioStyle.editor(for: colorScheme),
                            in: RoundedRectangle(cornerRadius: StudioStyle.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: StudioStyle.cornerRadius)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
            }

            playbackControls
        }
        .padding(StudioStyle.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text playback")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.65)
            Text("Enter text below. The current word is highlighted as it plays.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var playbackControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(player.status == .playing ?
                        StudioStyle.accent(for: colorScheme) : .secondary)
                    .frame(width: 7, height: 7)
                Text(player.status.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(time(player.elapsed) + "  /  " + time(player.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: player.elapsed, total: max(player.duration, 0.001))
                .progressViewStyle(.linear)
                .accessibilityLabel("Playback progress")

            HStack(spacing: 10) {
                AdaptivePlaybackButton(
                    title: "Play", symbol: "play.fill",
                    isPrimary: true, isEnabled: player.canStart,
                    action: player.start
                )

                AdaptivePlaybackButton(
                    title: "Stop", symbol: "stop.fill",
                    isPrimary: false,
                    isEnabled: player.status.isBusy && player.status != .stopping,
                    action: player.stop
                )

                Spacer()
                Text("⌘↩ Play · esc Stop")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }

    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
