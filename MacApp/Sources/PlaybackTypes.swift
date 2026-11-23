import SwiftUI

enum SpeechChoice: String, CaseIterable, Identifiable {
    case hungarian = "hu"
    case english = "en"

    var id: String { rawValue }
    var title: LocalizedStringKey { self == .hungarian ? "Magyar" : "English" }
    var voice: LocalizedStringKey {
        self == .hungarian ? "Tünde" : "System voice"
    }
}

enum SoundOutput: String, CaseIterable, Identifiable {
    case trackpad, speakers

    var id: String { rawValue }
    var title: LocalizedStringKey {
        self == .trackpad ? "Trackpad" : "Speakers"
    }
}

enum PlaybackStatus: Equatable {
    case ready, preparing, playing, stopping

    var isBusy: Bool { self != .ready }
    var title: LocalizedStringKey {
        switch self {
        case .ready: "Ready to play"
        case .preparing: "Preparing audio…"
        case .playing: "Playing"
        case .stopping: "Stopping…"
        }
    }
}

enum PlaybackIssue {
    case missingMotor
    case cannotStart(String)
    case processFailed(Int32, String)

    var message: LocalizedStringKey {
        switch self {
        case .missingMotor:
            "The NoSpeaker audio engine is missing from the app."
        case .cannotStart:
            "Playback could not start."
        case .processFailed:
            "Playback stopped unexpectedly."
        }
    }

    var detail: String? {
        switch self {
        case .missingMotor: nil
        case .cannotStart(let message): message
        case .processFailed(let code, let message):
            message.isEmpty ? "Exit code: \(code)" : message
        }
    }
}
