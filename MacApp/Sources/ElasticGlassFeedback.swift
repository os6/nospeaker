import SwiftUI

/// Bounded elastic movement for macOS 27 Glass controls. A real drag
/// takes priority over click recognition, so tugging Play never starts audio.
struct ElasticGlassFeedback: ViewModifier {
    let isEnabled: Bool
    var onDragDetected: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .offset(
                x: reduceMotion ? 0 : rubberBand(translation.width),
                y: reduceMotion ? 0 : rubberBand(translation.height)
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .updating($translation) { value, state, _ in
                        state = value.translation
                    }
                    .onChanged { _ in onDragDetected?() }
                    .onEnded { _ in onDragEnded?() },
                including: isEnabled ? .all : .none
            )
            .animation(
                reduceMotion ? nil :
                    .spring(response: 0.23, dampingFraction: 0.64),
                value: translation
            )
    }

    private func rubberBand(_ distance: CGFloat) -> CGFloat {
        let sign: CGFloat = distance < 0 ? -1 : 1
        return sign * 9 * (1 - exp(-abs(distance) / 22))
    }
}
