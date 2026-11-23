import AppKit
import Foundation
import SwiftUI

@MainActor final class PlaybackController: ObservableObject {
    @Published var text = """
        Szia! Örülök, hogy újra itt vagy. Ma egy hosszabb magyar szöveget         próbálunk ki. Gyönyörű idő van odakint, a gyerekek játszanak a         kertben, és a szél finoman mozgatja a fákat.
        """
    @Published var language: SpeechChoice = .hungarian
    @Published var output: SoundOutput = .trackpad
    @Published private(set) var status: PlaybackStatus = .ready
    @Published private(set) var activeRange: NSRange?
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var error: PlaybackIssue?

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var pendingBytes = Data()
    private var errorBytes = Data()
    private var generation = UUID()

    var canStart: Bool {
        !status.isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() {
        guard canStart else { return }
        guard let executable = Bundle.main.resourceURL?
            .appendingPathComponent("nospeaker"),
            FileManager.default.isExecutableFile(atPath: executable.path) else {
            error = .missingMotor
            return
        }

        let run = UUID()
        generation = run
        error = nil
        elapsed = 0
        duration = 0
        activeRange = nil
        status = .preparing
        pendingBytes = Data()
        errorBytes = Data()

        let task = Process()
        task.executableURL = executable
        task.arguments = ["--lang", language.rawValue, "--stdin", "--word-events"] +
            (output == .speakers ? ["--preview"] : [])
        let input = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardInput = input
        task.standardOutput = stdout
        task.standardError = stderr
        outputPipe = stdout
        errorPipe = stderr
        process = task

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            Task { @MainActor [weak self] in
                self?.consume(bytes: bytes, run: run)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            Task { @MainActor [weak self] in
                self?.consumeError(bytes: bytes, run: run)
            }
        }
        task.terminationHandler = { [weak self] completed in
            Task { @MainActor [weak self] in
                self?.complete(run: run, exit: completed.terminationStatus)
            }
        }

        do {
            try task.run()
            input.fileHandleForWriting.write(Data(text.utf8))
            try? input.fileHandleForWriting.close()
        } catch {
            cleanup()
            status = .ready
            self.error = .cannotStart(error.localizedDescription)
        }
    }

    func stop() {
        guard status.isBusy, status != .stopping else { return }
        status = .stopping
        if let process, process.isRunning {
            process.terminate()
        }
    }

    private func consume(bytes: Data, run: UUID) {
        guard generation == run, !bytes.isEmpty else { return }
        pendingBytes.append(bytes)
        while let end = pendingBytes.firstIndex(of: 10) {
            let line = String(decoding: pendingBytes[..<end], as: UTF8.self)
            pendingBytes.removeSubrange(...end)
            processLine(line)
        }
    }

    private func consumeError(bytes: Data, run: UUID) {
        guard generation == run, !bytes.isEmpty else { return }
        if errorBytes.count < 8192 { errorBytes.append(bytes.prefix(8192 - errorBytes.count)) }
    }

    private func processLine(_ line: String) {
        guard line.hasPrefix("NSP\t") else { return }
        let tokens = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard tokens.count >= 2 else { return }
        switch tokens[1] {
        case "START":
            duration = tokens.count > 2 ? Double(tokens[2]) ?? 0 : 0
            if status == .preparing { status = .playing }
        case "WORD":
            guard tokens.count >= 4, let location = Int(tokens[2]),
                  let length = Int(tokens[3]), location >= 0, length > 0,
                  location + length <= (text as NSString).length else { return }
            activeRange = NSRange(location: location, length: length)
        case "TIME":
            if tokens.count > 2, let value = Double(tokens[2]) {
                elapsed = min(max(0, value), max(0, duration))
            }
        case "END": elapsed = duration
        default: break
        }
    }

    private func complete(run: UUID, exit: Int32) {
        guard generation == run else { return }
        let wasStopping = status == .stopping
        if exit != 0 && !wasStopping {
            let detail = String(decoding: errorBytes, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            error = .processFailed(exit, detail)
        }
        cleanup()
        status = .ready
        activeRange = nil
        if wasStopping { elapsed = 0 }
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        errorPipe = nil
    }
}
