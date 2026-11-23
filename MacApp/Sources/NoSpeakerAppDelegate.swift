import AppKit

/// Closing the only window exits the application, instead of leaving a
/// windowless background app and possibly a running audio child process.
final class NoSpeakerAppDelegate: NSObject, NSApplicationDelegate {
    weak var playback: PlaybackController?

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        playback?.stop()
    }
}
