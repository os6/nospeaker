//
//  NoSpeakerGUI.swift
//  NoSpeaker
//
//  A native macOS application for NoSpeaker.
//  Transforms your Force Touch trackpad into an acoustic synthesizer, speaker, and instrument.
//

import SwiftUI
import AppKit

// MARK: - Navigation Tabs

enum NavigationTab: String, CaseIterable, Identifiable {
    case show = "The Show"
    case speech = "Say Anything"
    case theremin = "Touch Instrument"
    case lab = "Lab & Soundboard"
    case settings = "Hardware & Setup"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .show: return "play.circle.fill"
        case .speech: return "waveform.and.mic"
        case .theremin: return "hand.tap.fill"
        case .lab: return "tuningfork"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - Main Application Entry

@main
struct NoSpeakerApp: App {
    @StateObject private var engine = NoSpeakerEngine.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 880, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var engine: NoSpeakerEngine
    @State private var selectedTab: NavigationTab = .show

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                TopStatusBar()
                Divider()
                ZStack {
                    switch selectedTab {
                    case .show:
                        TheShowView()
                    case .speech:
                        SpeechLabView()
                    case .theremin:
                        ThereminView()
                    case .lab:
                        SoundboardLabView()
                    case .settings:
                        HardwareSetupView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedTab: NavigationTab
    @EnvironmentObject var engine: NoSpeakerEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // App Branding Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("NO SPEAKER")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                    Text("Haptic Voice Synthesis")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Divider()
                .padding(.horizontal, 12)

            // Navigation Items
            VStack(spacing: 4) {
                ForEach(NavigationTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 22)
                                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)

                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))

                            Spacer()

                            if tab == .show && engine.activeOperation != .idle {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
            }

            Spacer()

            // Hardware Status Footer
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(engine.isMotorReady ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(engine.isMotorReady ? "Trackpad Ready" : "No Trackpad")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text(engine.deviceName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)

                HStack {
                    Text("Actuations:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(engine.totalActuations)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            .padding(12)
        }
    }
}

// MARK: - Top Status Bar

struct TopStatusBar: View {
    @EnvironmentObject var engine: NoSpeakerEngine

    var body: some View {
        HStack(spacing: 16) {
            // Live Status indicator
            HStack(spacing: 8) {
                if engine.activeOperation != .idle {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text(engine.activeOperation.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("Ready")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Real-time Note & Frequency readout
            if engine.currentHz > 0 && engine.activeOperation != .idle {
                HStack(spacing: 6) {
                    Text(engine.currentNoteName)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)

                    Text("\(Int(engine.currentHz)) Hz")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .transition(.opacity)
            }

            // Formants indicator (when speaking)
            if engine.currentF0 > 0 {
                HStack(spacing: 6) {
                    Text("F0: \(Int(engine.currentF0))")
                    Text("F1: \(Int(engine.currentF1))")
                    Text("F2: \(Int(engine.currentF2))")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(4)
            }

            Spacer()

            // Speaker Mute Advice & Action
            if engine.areSpeakersMuted == false {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("Speakers are on")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)

                    Button("Mute for Illusion") {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                        p.arguments = ["-e", "set volume output muted true"]
                        try? p.run()
                        engine.refreshHardware()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            } else if engine.areSpeakersMuted == true {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text("Speakers Muted (Perfect)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.08))
                .cornerRadius(6)
            }

            // Global Emergency Stop Button
            if engine.activeOperation != .idle {
                Button {
                    engine.stopAll()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("Stop")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - View 1: The Show

struct TheShowView: View {
    @EnvironmentObject var engine: NoSpeakerEngine

    let showStages = [
        (1, "Loading & Speech Synthesis", "Prepares linear predictive voice models"),
        (2, "Heartbeat (Waking Up)", "Felt and heard haptic pulse"),
        (3, "First Words", "The trackpad greets you"),
        (4, "Frequency Sweep", "Rises smoothly from 100 Hz to 4,000 Hz"),
        (5, "Singing Melody", "Performs “The Hook” with vibrato and glides"),
        (6, "Beat & Rap Groove", "Synthesizes drums, bass, and lyrics simultaneously"),
        (7, "Your Turn", "Invitation to touch"),
        (8, "Touch to Play", "Trackpad operates as a musical instrument"),
        (9, "Say Anything", "Whispering through the glass"),
        (10, "Outro & Sparkle", "Ascending arpeggio sign-off")
    ]

    var isShowRunning: Bool {
        if case .show = engine.activeOperation { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Banner
                VStack(spacing: 12) {
                    Text("THE SHOW")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .tracking(2.0)

                    Text("Mute your Mac. Your trackpad will still talk.")
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("There is no speaker in your trackpad — only a Force Touch haptic motor. Driven up to 4,000 times per second, the glass vibrates to produce human speech, melody, and beats.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 580)

                    // Control Buttons
                    HStack(spacing: 14) {
                        if !isShowRunning {
                            Button {
                                engine.startFullShow()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text("Start The Show")
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Button {
                                engine.skipStage()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "forward.fill")
                                    Text("Skip Stage")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                            Button {
                                engine.stopAll()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "stop.fill")
                                    Text("Stop Show")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.red)
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // Live Caption Box
                if !engine.currentCaption.isEmpty {
                    VStack(spacing: 8) {
                        Text("TRACKPAD CAPTION")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .tracking(1.0)

                        Text("“\(engine.currentCaption)”")
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
                    )
                }

                // Stage Checklist / Timeline
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("SHOW SEQUENCE (10 PARTS)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        if isShowRunning {
                            Text("Part \(engine.showStep) of 10")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(showStages, id: \.0) { stage in
                            let isCurrent = isShowRunning && engine.showStep == stage.0
                            let isPast = isShowRunning && engine.showStep > stage.0

                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(isCurrent ? Color.accentColor : (isPast ? Color.green : Color.secondary.opacity(0.2)))
                                        .frame(width: 26, height: 26)

                                    if isPast {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Text("\(stage.0)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(isCurrent ? .white : .secondary)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stage.1)
                                        .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                                        .foregroundColor(isCurrent ? .primary : (isPast ? .secondary : .secondary.opacity(0.8)))

                                    Text(stage.2)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary.opacity(0.7))
                                }

                                Spacer()

                                if isCurrent {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                        Text("Playing")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .padding(24)
        }
    }
}

// MARK: - View 2: Speech Lab ("Say Anything")

struct SpeechLabView: View {
    @EnvironmentObject var engine: NoSpeakerEngine
    @State private var inputText: String = "Hello there! I am your trackpad."
    @State private var voiceFilter: String = ""
    @State private var history: [String] = [
        "Good afternoon. I'm your trackpad.",
        "No speaker. No wires. Just a motor and a beat.",
        "Mute your Mac. I can still talk.",
        "I live under the glass.",
        "Please stop clicking me so hard!"
    ]

    var filteredVoices: [VoiceMetadata] {
        if voiceFilter.isEmpty {
            return engine.availableVoices
        }
        return engine.availableVoices.filter {
            $0.name.localizedCaseInsensitiveContains(voiceFilter) ||
            $0.locale.localizedCaseInsensitiveContains(voiceFilter)
        }
    }

    var isSpeaking: Bool {
        if case .speaking = engine.activeOperation { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Speech Input Box
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("TRACKPAD SPEECH SYNTHESIS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Formants F1 + F2")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }

                    TextEditor(text: $inputText)
                        .font(.system(size: 15))
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    // Voice Selection & Speak Actions
                    HStack(spacing: 12) {
                        // Voice Selector
                        HStack {
                            Image(systemName: "person.wave.2")
                                .foregroundColor(.secondary)
                            Picker("Voice:", selection: $engine.selectedVoice) {
                                ForEach(engine.availableVoices) { v in
                                    Text("\(v.name) (\(v.locale))").tag(v.name)
                                }
                            }
                            .frame(maxWidth: 240)
                        }

                        Spacer()

                        if isSpeaking {
                            Button {
                                engine.stopAll()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "stop.fill")
                                    Text("Stop Speaking")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button {
                                let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                if !history.contains(trimmed) {
                                    history.insert(trimmed, at: 0)
                                }
                                engine.speak(text: trimmed)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "speaker.wave.2.fill")
                                    Text("Speak to Trackpad")
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // Quick Preset Pills
                VStack(alignment: .leading, spacing: 10) {
                    Text("QUICK SUGGESTIONS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(history, id: \.self) { phrase in
                            Button {
                                inputText = phrase
                                engine.speak(text: phrase)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 10))
                                    Text(phrase)
                                        .font(.system(size: 12))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )

                // How it works note
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.accentColor)
                        Text("How speech synthesis works on the trackpad:")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("1. macOS’s speech engine speaks the text into audio memory in 32-bit floating point.\n2. Linear Predictive Coding (LPC order 18) calculates the two primary resonant formants (F1 and F2) plus pitch (F0) every 10 milliseconds.\n3. The haptic motor plays both formant frequencies simultaneously, re-triggered at the voice pitch so it sounds like vocal chords humming.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.15), lineWidth: 1))
                )
            }
            .padding(24)
        }
    }
}

// MARK: - View 3: Touch Instrument (Theremin)

struct ThereminView: View {
    @EnvironmentObject var engine: NoSpeakerEngine
    let notes = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"]

    var isThereminRunning: Bool {
        if case .theremin = engine.activeOperation { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header Instructions
            VStack(spacing: 6) {
                Text("TRACKPAD THEREMIN")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .tracking(1.5)

                Text("Touch and slide your finger across your trackpad")
                    .font(.system(size: 18, weight: .bold))

                Text("Horizontal position controls pitch · Vertical position adds vibrato · Finger pressure controls loudness")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)

            // Start/Stop Toggle
            HStack(spacing: 12) {
                if !isThereminRunning {
                    Button {
                        engine.startTheremin()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.tap.fill")
                            Text("Enable Trackpad Instrument Mode")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        engine.stopTheremin()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                            Text("Disable Instrument Mode")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                }
            }

            // Virtual Trackpad Display
            GeometryReader { geo in
                ZStack {
                    // Trackpad Surface Canvas
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.windowBackgroundColor)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isThereminRunning ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isThereminRunning ? 2 : 1)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                    // Vertical note guidelines
                    HStack(spacing: 0) {
                        ForEach(notes, id: \.self) { note in
                            VStack {
                                Text(note)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .padding(.top, 8)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 1),
                                alignment: .trailing
                            )
                        }
                    }

                    // Touch Indicator dot
                    if engine.touchState.down {
                        let dotX = CGFloat(engine.touchState.x) * geo.size.width
                        let dotY = CGFloat(1.0 - engine.touchState.y) * geo.size.height

                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.25))
                                .frame(width: 64, height: 64)
                                .scaleEffect(CGFloat(1.0 + engine.touchState.size * 2))

                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 24, height: 24)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                        }
                        .position(x: dotX, y: dotY)
                        .animation(.linear(duration: 0.04), value: dotX)
                    } else if isThereminRunning {
                        Text("Place your finger on the trackpad to play")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 240)
            .padding(.horizontal, 24)

            // Current Note Readout
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("NOTE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(engine.currentNoteName)
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                        .foregroundColor(.accentColor)
                }

                Divider().frame(height: 36)

                VStack(spacing: 4) {
                    Text("FREQUENCY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("\(Int(engine.currentHz)) Hz")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                }

                Divider().frame(height: 36)

                VStack(spacing: 4) {
                    Text("CONTACT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(engine.touchState.down ? "Touching" : "Lifted")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(engine.touchState.down ? .green : .secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .padding(.bottom, 16)
        }
        .padding(24)
    }
}

// MARK: - View 4: Lab & Soundboard

struct SoundboardLabView: View {
    @EnvironmentObject var engine: NoSpeakerEngine
    @State private var sweepDuration: Double = 5.0
    @State private var sweepStartHz: Double = 100.0
    @State private var sweepEndHz: Double = 4000.0
    @State private var manualToneHz: Double = 1000.0

    let pianoNotes = ["C5", "D5", "E5", "F5", "G5", "A5", "B5", "C6", "D6", "E6", "F6", "G6", "A6", "B6", "C7"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Section 1: Soundboard Presets
                VStack(alignment: .leading, spacing: 14) {
                    Text("SOUNDBOARD PRESETS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        PresetCard(title: "Heartbeat", subtitle: "Double haptic thump", icon: "heart.fill", color: .red) {
                            engine.playHeartbeat()
                        }

                        PresetCard(title: "The Hook", subtitle: "Melody with vibrato", icon: "music.note", color: .blue) {
                            engine.playMelody()
                        }

                        PresetCard(title: "Beat & Rap", subtitle: "Drums, bass & vocal", icon: "waveform", color: .purple) {
                            engine.playGroove()
                        }

                        PresetCard(title: "Sparkle", subtitle: "Ascending arpeggio", icon: "sparkles", color: .yellow) {
                            engine.playSparkle()
                        }

                        PresetCard(title: "Felt Thump", subtitle: "Fast pitch dive (120 Hz)", icon: "circle.circle.fill", color: .orange) {
                            engine.executeThump(1.0)
                        }

                        PresetCard(title: "1 kHz Sweet Spot", subtitle: "Motor's purest resonance", icon: "tuningfork", color: .green) {
                            engine.playTone(hz: 1047, ms: 500)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // Section 2: Interactive Piano Keys
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("PIANO SOUNDBOARD")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Click any key to actuate")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        ForEach(pianoNotes, id: \.self) { note in
                            Button {
                                engine.playNote(note)
                            } label: {
                                VStack {
                                    Spacer()
                                    Text(note)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .padding(.bottom, 8)
                                }
                                .frame(height: 90)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(NSColor.windowBackgroundColor))
                                        .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // Section 3: Frequency Sweep Generator
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("FREQUENCY SWEEP")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(sweepStartHz)) Hz → \(Int(sweepEndHz)) Hz (\(String(format: "%.1f", sweepDuration)) s)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Duration:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Slider(value: $sweepDuration, in: 2.0...10.0, step: 0.5)
                        }

                        Button {
                            engine.sweep(duration: sweepDuration, startHz: sweepStartHz, endHz: sweepEndHz)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.path")
                                Text("Run Sweep")
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // Section 4: Manual Tone Generator
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("PURE TONE GENERATOR")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(manualToneHz)) Hz (\(MusicTheory.noteName(manualToneHz)))")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }

                    HStack(spacing: 16) {
                        Slider(value: $manualToneHz, in: 100...4000, step: 10)

                        Button {
                            engine.playTone(hz: manualToneHz, ms: 600, level: 0.95)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Play Tone")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .padding(24)
        }
    }
}

struct PresetCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(color)
                    }
                    Spacer()
                    Image(systemName: "play.circle")
                        .foregroundColor(.secondary.opacity(0.6))
                }

                Text(title)
                    .font(.system(size: 14, weight: .bold))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View 5: Hardware & Setup

struct HardwareSetupView: View {
    @EnvironmentObject var engine: NoSpeakerEngine
    @State private var installStatus: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hardware Status Box
                VStack(alignment: .leading, spacing: 14) {
                    Text("TRACKPAD HARDWARE STATUS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    VStack(spacing: 10) {
                        InfoRow(label: "Mac Model", value: AudioHardware.macModel())
                        InfoRow(label: "Device Connected", value: engine.deviceName)
                        InfoRow(label: "Haptic Actuator Ready", value: engine.isMotorReady ? "Yes (Force Touch active)" : "No")
                        InfoRow(label: "Speakers Muted", value: engine.areSpeakersMuted == true ? "Yes" : (engine.areSpeakersMuted == false ? "No (speakers audible)" : "Unknown"))
                        InfoRow(label: "Total Haptic Vibrations", value: "\(engine.totalActuations)")
                    }

                    Divider()

                    // Toggle for External Magic Trackpad
                    Toggle(isOn: $engine.preferExternal) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prefer External Magic Trackpad")
                                .font(.system(size: 13, weight: .medium))
                            Text("Target an external Apple Magic Trackpad 2 or newer instead of the built-in trackpad.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: engine.preferExternal) {
                        engine.openMotor()
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                // CLI Installation Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "terminal.fill")
                                .foregroundColor(.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Terminal Command Line Utility")
                                .font(.system(size: 14, weight: .bold))
                            Text("Install `nospeaker` into ~/.local/bin so you can run it from any terminal.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            installCLI()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Install `nospeaker` CLI")
                                    .fontWeight(.bold)
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if let status = installStatus {
                            Text(status)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }

                    Text("Usage in terminal:\n  nospeaker                 # Play the full interactive show\n  nospeaker \"hello there\"   # Say any words through trackpad\n  nospeaker --sweep         # Frequency sweep 100 Hz to 4 kHz")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(6)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .padding(24)
        }
    }

    private func installCLI() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin")
        let sourceBinary = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("nospeaker")

        do {
            try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
            let dest = localBin.appendingPathComponent("nospeaker")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: sourceBinary, to: dest)
            installStatus = "Successfully installed to ~/.local/bin/nospeaker!"
        } catch {
            installStatus = "Installation failed: \(error.localizedDescription)"
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }
}

// MARK: - Flow Layout for Suggestion Pills

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            height = max(height, currentY + lineHeight)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
