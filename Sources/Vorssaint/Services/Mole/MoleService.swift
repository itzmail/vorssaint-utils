// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// What one Mole run left behind, kept per command so switching sections
/// does not lose a scan.
struct MoleResult {
    enum Kind: Equatable {
        case preview
        case run(removed: String?)
    }

    let kind: Kind
    let report: MoleReport
    let slim: MoleSlimList?
    /// The tail of the raw output, shown when the report could not be read
    /// or the run did not finish cleanly.
    let rawTail: String
    let failed: Bool
    let timedOut: Bool
    let date: Date
}

/// Runs the separately installed Mole command line tool and keeps its
/// results. One command runs at a time: every one of them walks the disk.
final class MoleService: ObservableObject {
    static let shared = MoleService()

    @Published private(set) var executable: String?
    @Published private(set) var busy: MoleCommand?
    /// Whether the busy command is a real run rather than a preview.
    @Published private(set) var busyIsRun = false
    /// What the busy command has printed so far, read as it arrives.
    @Published private(set) var progress: MoleProgress?
    @Published private(set) var results: [MoleCommand: MoleResult] = [:]

    private let queue = DispatchQueue(label: "Vorssaint.Mole", qos: .utility)

    private init() {
        executable = MoleSupport.executable()
    }

    func refreshExecutable() {
        let found = MoleSupport.executable()
        if found != executable { executable = found }
    }

    /// Output as it arrives, shared between the pipe's reader and the code
    /// that finishes the run. Past the limit the oldest output goes, so the
    /// summary at the end is always kept.
    private final class Stream: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var lastPublish = Date.distantPast
        private var launched = false
        private(set) var timedOut = false
        private(set) var cancelled = false
        let process = Process()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            if data.count > MoleService.outputLimit { data.removeFirst(data.count - MoleService.outputLimit) }
            lock.unlock()
        }

        var text: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }

        /// True at most five times a second, so a chatty run does not
        /// reparse its output on every chunk.
        func shouldPublish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            let now = Date()
            guard now.timeIntervalSince(lastPublish) >= 0.2 else { return false }
            lastPublish = now
            return true
        }

        func markTimedOut() { lock.lock(); timedOut = true; lock.unlock() }

        /// False when the run was stopped before it started: it never starts.
        var mayLaunch: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }

        /// True when a stop came in between the launch and this call.
        func markLaunched() -> Bool {
            lock.lock(); defer { lock.unlock() }
            launched = true
            return cancelled
        }

        /// Whether the process is there to be signalled: ending one that has
        /// not started raises an exception, so a stop before then is only
        /// remembered and the launch checks it.
        func requestCancel() -> Bool {
            lock.lock(); defer { lock.unlock() }
            cancelled = true
            return launched
        }
    }

    private var stream: Stream?
    fileprivate static let outputLimit = 4 * 1024 * 1024

    /// `mo` runs with the login shell's environment, since a program started
    /// from Finder has almost no PATH and Mole finds the developer tools it
    /// cleans (npm, pnpm, Docker, brew) by name. Its output is read as it is
    /// printed, which is what the live progress shows.
    private func launch(_ command: MoleCommand, path: String, arguments: [String],
                        timeout: TimeInterval, isRun: Bool) {
        busy = command
        busyIsRun = isRun
        progress = MoleProgress()
        let stream = Stream()
        self.stream = stream
        queue.async { [weak self] in
            let process = stream.process
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.environment = HomebrewEnvironment.forBrew
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = pipe
            let reader = pipe.fileHandleForReading
            let eof = DispatchSemaphore(value: 0)
            reader.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    // The end of the output; left set the handler would spin.
                    handle.readabilityHandler = nil
                    eof.signal()
                    return
                }
                stream.append(chunk)
                if stream.shouldPublish() {
                    let text = stream.text
                    DispatchQueue.main.async {
                        // A late write must not outlive the run it belongs to.
                        guard let self, self.stream === stream else { return }
                        self.progress = MoleSupport.progress(of: text)
                    }
                }
            }
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            guard stream.mayLaunch, (try? process.run()) != nil else {
                reader.readabilityHandler = nil
                DispatchQueue.main.async { self?.finish(command, stream, status: -1, isRun: isRun) }
                return
            }
            if stream.markLaunched() { process.terminate() }
            let pid = process.processIdentifier
            let timer = DispatchWorkItem { stream.markTimedOut(); process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            // A tool that ignores the polite stop is ended outright, so a run
            // can never keep the queue and the island's strip forever.
            if finished.wait(timeout: .now() + timeout + 5) == .timedOut {
                kill(pid, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
            timer.cancel()
            // A helper that outlived `mo` can hold the pipe open, so the tail
            // gets a moment and no more.
            _ = eof.wait(timeout: .now() + 0.3)
            reader.readabilityHandler = nil
            try? reader.close()
            let status = process.isRunning ? -1 : process.terminationStatus
            DispatchQueue.main.async { self?.finish(command, stream, status: status, isRun: isRun) }
        }
    }

    private func finish(_ command: MoleCommand, _ stream: Stream, status: Int32, isRun: Bool) {
        let text = stream.text
        if !stream.cancelled {
            let kind: MoleResult.Kind = isRun ? .run(removed: MoleSupport.removedAmount(in: text)) : .preview
            results[command] = Self.makeResult(command, text: text, status: status,
                                               timedOut: stream.timedOut, kind: kind)
        }
        busy = nil
        progress = nil
        self.stream = nil
    }

    /// A dry run: reads, changes nothing.
    func preview(_ command: MoleCommand) {
        guard busy == nil, let path = executable else { return }
        launch(command, path: path, arguments: command.previewArguments, timeout: 600, isRun: false)
    }

    /// The real run, for the commands that can run without a terminal.
    func run(_ command: MoleCommand) {
        guard busy == nil, let path = executable, !command.runsInTerminal else { return }
        launch(command, path: path, arguments: command.runArguments, timeout: 3600, isRun: true)
    }

    /// Stops the running command; what it had printed is discarded.
    func cancel() {
        guard let stream else { return }
        guard stream.requestCancel() else { return }
        let process = stream.process
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private static func makeResult(_ command: MoleCommand, text: String, status: Int32,
                                   timedOut: Bool, kind: MoleResult.Kind) -> MoleResult {
        MoleResult(
            kind: kind,
            report: MoleSupport.parse(text),
            slim: command == .slim ? MoleSupport.parseSlim(text) : nil,
            rawTail: MoleSupport.tail(of: text, lines: 40),
            failed: status != 0 && !timedOut,
            timedOut: timedOut,
            date: Date())
    }

    func discard(_ command: MoleCommand) {
        results[command] = nil
    }

    // MARK: Terminal

    /// For the commands that choose their items with the keyboard: a Terminal
    /// window opens a temporary script that runs them.
    func openInTerminal(_ command: MoleCommand) {
        openInTerminal(arguments: [command.rawValue])
    }

    func openInTerminal(arguments: [String]) {
        guard let path = executable else { return }
        openScript(executable: path, arguments: arguments)
    }

    /// Mole itself comes from Homebrew.
    func installMole() {
        guard let brew = HomebrewCommandBuilder.candidatePaths
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        openScript(executable: brew, arguments: ["install", "mole"])
    }

    private func openScript(executable: String, arguments: [String]) {
        let name = "vorssaint-mole-\(UUID().uuidString).command"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let script = MoleSupport.terminalScript(executable: executable, arguments: arguments)
        guard FileManager.default.createFile(atPath: url.path, contents: Data(script.utf8),
                                             attributes: [.posixPermissions: 0o700]) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Mole's own file with every path it would clean, one per line.
    func openList(_ path: String) {
        guard MoleSupport.isTrustedListPath(path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
