// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Mole's own commands in one place. Mole is a separate command line tool
/// that has to be installed; this page previews what each command would do,
/// runs the ones that can run without a terminal, and opens Terminal for
/// the two that choose their items with the keyboard.
struct MoleView: View {
    @ObservedObject private var service = MoleService.shared
    @State private var command = MoleCommand.clean
    @State private var confirming = false
    /// In the island a SwiftUI dialog would hang from it as a sheet, so the
    /// confirmation is an alert above it, as the port manager asks.
    @Environment(\.notchPresentation) private var inNotch
    /// Hosted in the narrow menu bar panel: no outer scroll view or padding,
    /// and a menu instead of a segmented picker.
    var compact = false

    private enum Copy {
        static let title = "Mole"
        static let notInstalled = "Mole is not installed"
        static let notInstalledDetail = "Mole is a free command line cleaner. Install it with Homebrew, then check again."
        static let install = "Install Mole"
        static let checkAgain = "Check again"
        static let scan = "Scan"
        static let scanning = "Scanning. This can take a minute."
        static let running = "Running. Leave this open until it finishes."
        static let nothing = "Nothing to clean."
        static let clearPrefix = "Nothing to clean in: "
        static let openList = "Open full list"
        static let rescan = "Scan again"
        static let openTerminal = "Open in Terminal"
        static let chooseFolders = "Choose folders"
        static let failed = "Mole did not finish. Its last output:"
        static let timedOut = "Mole took too long and was stopped. Its last output:"
        static let noReport = "Mole printed something this page cannot read. Its last output:"
        static let cancel = "Cancel"
    }

    private func title(_ command: MoleCommand) -> String {
        switch command {
        case .clean: return "Clean"
        case .purge: return "Purge"
        case .installer: return "Installers"
        case .slim: return "Slim"
        case .optimize: return "Optimize"
        }
    }

    private func summary(_ command: MoleCommand) -> String {
        switch command {
        case .clean:
            return "Caches, logs and leftovers: developer tools, browsers, apps and more. System caches that need an admin password are skipped."
        case .purge:
            return "Build folders of old projects, such as node_modules, target and dist. They are rebuilt on demand."
        case .installer:
            return "Installer files left behind: .dmg, .pkg, .iso, .xip and .zip."
        case .slim:
            return "Removes the Intel code from universal apps, which this Mac never uses. Each app is checked after slimming and the original goes to the Trash. An app update brings the Intel code back."
        case .optimize:
            return "Refreshes system caches and services, and repairs small maintenance problems. It changes no personal files."
        }
    }

    private func runLabel(_ command: MoleCommand) -> String {
        switch command {
        case .clean: return "Clean now"
        case .purge: return "Purge now"
        case .optimize: return "Optimize now"
        case .installer, .slim: return Copy.openTerminal
        }
    }

    private func confirmMessage(_ command: MoleCommand) -> String {
        switch command {
        case .optimize:
            return "Optimize refreshes system caches and services. Finder and the Dock may restart for a moment."
        default:
            return "Mole scans again and deletes what it finds now, which can differ from the last scan. It skips anything on its protected list."
        }
    }

    var body: some View {
        Group {
            if service.executable == nil {
                missing
            } else {
                installed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { service.refreshExecutable() }
    }

    // MARK: Not installed

    private var missing: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(Copy.notInstalled).font(.headline)
            Text(Copy.notInstalledDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack {
                if HomebrewCommandBuilder.candidatePaths.contains(where: {
                    FileManager.default.isExecutableFile(atPath: $0)
                }) {
                    Button(Copy.install) { service.installMole() }
                        .buttonStyle(.borderedProminent)
                }
                Button(Copy.checkAgain) { service.refreshExecutable() }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Installed

    private var picker: some View {
        Picker("", selection: $command) {
            ForEach(MoleCommand.allCases) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(service.busy != nil)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary(command))
                .font(compact ? .caption : .callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            body(for: command)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var installedLayout: some View {
        if compact {
            VStack(alignment: .leading, spacing: 10) {
                picker
                ScrollView { details }.frame(maxHeight: 320)
            }
        } else {
            VStack(spacing: 0) {
                picker
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                Divider()
                ScrollView { details.padding(24) }
            }
        }
    }

    private var installed: some View {
        installedLayout
        .confirmationDialog(runLabel(command), isPresented: $confirming, titleVisibility: .visible) {
            Button(runLabel(command), role: .destructive) { service.run(command) }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            Text(confirmMessage(command))
        }
    }

    @ViewBuilder
    private func body(for command: MoleCommand) -> some View {
        if service.busy == command {
            MoleProgressView(isRun: service.busyIsRun, progress: service.progress) { service.cancel() }
        } else if service.busy != nil {
            Text("Another Mole command is running.").foregroundStyle(.secondary)
        } else if let result = service.results[command] {
            resultView(command, result)
        } else {
            actions(command, hasResult: false)
        }
    }

    private func actions(_ command: MoleCommand, hasResult: Bool) -> some View {
        HStack {
            if hasResult {
                Button(Copy.rescan) { service.preview(command) }
            } else {
                Button(Copy.scan) { service.preview(command) }
                    .buttonStyle(.borderedProminent)
            }
            if command == .purge {
                Button(Copy.chooseFolders) {
                    service.openInTerminal(arguments: ["purge", "--paths"])
                }
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func resultView(_ command: MoleCommand, _ result: MoleResult) -> some View {
        if case let .run(removed) = result.kind {
            ranView(command, result, removed: removed)
        } else if result.failed || result.timedOut {
            rawBlock(result.timedOut ? Copy.timedOut : Copy.failed, result)
            actions(command, hasResult: true)
        } else if command == .slim, let slim = result.slim {
            slimView(slim)
            footer(command, result, canRun: !slim.apps.isEmpty)
        } else if result.report.hasNothingToShow {
            rawBlock(Copy.noReport, result)
            actions(command, hasResult: true)
        } else if result.report.hasNothingToClean && result.report.summary == nil {
            Label(Copy.nothing, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            actions(command, hasResult: true)
        } else {
            reportView(result.report)
            footer(command, result, canRun: true)
        }
    }

    private func ranView(_ command: MoleCommand, _ result: MoleResult, removed: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if result.failed || result.timedOut {
                rawBlock(result.timedOut ? Copy.timedOut : Copy.failed, result)
            } else {
                Label(removed.map { "Done. \($0) removed." } ?? "Done.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                if !result.report.hasNothingToShow {
                    reportView(result.report)
                }
            }
            actions(command, hasResult: true)
        }
    }

    private func requestRun(_ command: MoleCommand) {
        guard inNotch else { confirming = true; return }
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(runLabel(command), message: confirmMessage(command),
                                             action: runLabel(command), destructive: true,
                                             cancel: Copy.cancel) else { return }
            service.run(command)
        }
    }

    private func footer(_ command: MoleCommand, _ result: MoleResult, canRun: Bool) -> some View {
        HStack {
            if canRun {
                Button(runLabel(command)) {
                    if command.runsInTerminal {
                        service.openInTerminal(command)
                    } else {
                        requestRun(command)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Button(Copy.rescan) {
                service.preview(command)
            }
            if let path = result.report.listPath, MoleSupport.isTrustedListPath(path) {
                Button(Copy.openList) { service.openList(path) }
            }
        }
    }

    private func reportView(_ report: MoleReport) -> some View {
        let clear = report.sections.filter(\.isClear).map(\.title).filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 12) {
            if let summary = report.summary {
                Text(summary).font(.headline)
            }
            ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                if !section.isClear { sectionView(section) }
            }
            if !clear.isEmpty {
                Text(Copy.clearPrefix + clear.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionView(_ section: MoleSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !section.title.isEmpty {
                Text(section.title).font(.subheadline.weight(.semibold))
            }
            ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: symbol(line.kind))
                        .foregroundStyle(tint(line.kind))
                        .frame(width: 14)
                    Text(line.text).font(.callout)
                }
            }
        }
    }

    private func symbol(_ kind: MoleLine.Kind) -> String {
        switch kind {
        case .item: return "circle.fill"
        case .clear: return "checkmark"
        case .skipped: return "exclamationmark.circle"
        case .info: return "info.circle"
        }
    }

    private func tint(_ kind: MoleLine.Kind) -> Color {
        switch kind {
        case .item: return .accentColor
        case .clear: return .green
        case .skipped: return .orange
        case .info: return .secondary
        }
    }

    private func slimView(_ slim: MoleSlimList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if slim.apps.isEmpty {
                Label(Copy.nothing, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                if let total = slim.total {
                    Text("\(slim.apps.count) apps, \(total) of Intel code").font(.headline)
                }
                ForEach(Array(slim.apps.enumerated()), id: \.offset) { _, app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Text(app.size).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func rawBlock(_ heading: String, _ result: MoleResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(heading, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(result.rawTail)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// What a running Mole command is doing right now: the section it is in, the
/// last thing it found, and a running total. Shared by every surface that
/// shows Mole at work.
struct MoleProgressView: View {
    let isRun: Bool
    let progress: MoleProgress?
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(headline).font(.headline)
                Spacer()
                Button("Stop", action: stop)
            }
            if let line = progress?.lastLine {
                Text(line.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let log = progress?.log, !log.isEmpty { MoleLogView(lines: log) }
            if let progress, progress.itemCount > 0 {
                Text("\(progress.itemCount) found, \(MoleProgressText.size(progress.foundBytes)) so far, \(progress.finishedSections) sections done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        let verb = isRun ? "Running" : "Scanning"
        guard let section = progress?.section else { return "\(verb)…" }
        return "\(verb) \(section)…"
    }
}

/// What Mole prints, line by line, following the newest like a terminal.
struct MoleLogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .frame(height: 150)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            .onChange(of: lines.count) { _ in proxy.scrollTo(lines.count - 1, anchor: .bottom) }
            .onAppear { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
        }
    }
}

enum MoleProgressText {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
