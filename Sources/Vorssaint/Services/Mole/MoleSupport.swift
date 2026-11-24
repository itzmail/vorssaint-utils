// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The five Mole commands this app fronts. Mole is a separate command line
/// tool; the app only runs it and reads what it prints.
enum MoleCommand: String, CaseIterable, Identifiable {
    case clean, purge, installer, slim, optimize

    var id: String { rawValue }

    /// Every command can preview with --dry-run, which changes nothing.
    var previewArguments: [String] { [rawValue, "--dry-run"] }

    /// The arguments of a real run with nobody at a terminal. Purge asks for
    /// a confirmation unless it is given one up front.
    var runArguments: [String] {
        self == .purge ? [rawValue, "--yes"] : [rawValue]
    }

    /// Slim and installer choose their items with arrow keys and, without a
    /// terminal, only list. Their real run belongs in a Terminal window.
    var runsInTerminal: Bool { self == .slim || self == .installer }

    /// Optimize restarts or refreshes system services rather than deleting
    /// the user's files, which is worth saying before it runs.
    var changesSystemServices: Bool { self == .optimize }
}

/// One line of a Mole report, by the glyph Mole put in front of it.
struct MoleLine: Equatable {
    enum Kind: Equatable {
        /// Something that would be, or was, cleaned (the circle glyph).
        case item
        /// Nothing to do here (the check mark).
        case clear
        /// Left out, and why (the target glyph).
        case skipped
        /// Worth knowing, never touched (the dotted circle glyph).
        case info
    }

    let kind: Kind
    let text: String
}

struct MoleSection: Equatable {
    let title: String
    var lines: [MoleLine]

    /// A section whose only content is that there is nothing to clean.
    var isClear: Bool { !lines.isEmpty && lines.allSatisfy { $0.kind == .clear } }
}

/// What a Mole run printed, read leniently: a line the reader does not know
/// is kept as a note rather than dropped, so a format change degrades into
/// plain text instead of an empty screen.
struct MoleReport: Equatable {
    /// Lines before the first heading land in a section with an empty title.
    var sections: [MoleSection] = []
    var notes: [String] = []
    var summary: String?
    var listPath: String?

    /// "3.98GB" out of "Potential space: 3.98GB · 702 items".
    var reclaimable: String? {
        guard let summary, let range = summary.range(of: "Potential space: ") else { return nil }
        let rest = summary[range.upperBound...]
        let size = rest.components(separatedBy: " ·").first ?? String(rest)
        let trimmed = size.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasNothingToClean: Bool {
        let lines = sections.flatMap(\.lines)
        return !lines.contains { $0.kind == .item } && lines.contains { $0.kind == .clear }
    }

    var hasNothingToShow: Bool {
        sections.isEmpty && notes.isEmpty && summary == nil
    }
}

/// Where a run stands, read from what it has printed so far. Mole prints a
/// section's heading before it scans that section and its lines as they
/// finish, so the last heading is what is being scanned now.
struct MoleProgress: Equatable {
    /// The section being scanned, nil until the first heading.
    var section: String?
    /// The most recent line a finished step printed.
    var lastLine: MoleLine?
    var finishedSections = 0
    /// Items found so far, and their sizes added up where Mole states one.
    var itemCount = 0
    var foundBytes: Int64 = 0
    /// The newest lines as Mole printed them, for a terminal-like view.
    var log: [String] = []
}

struct MoleSlimApp: Equatable {
    let name: String
    let size: String
}

struct MoleSlimList: Equatable {
    var apps: [MoleSlimApp] = []
    var total: String?
}

enum MoleSupport {
    static let defaultCandidates = ["/opt/homebrew/bin/mo", "/usr/local/bin/mo"]

    /// The first place `mo` exists. Homebrew's two prefixes cover Apple
    /// Silicon and Intel; a login shell's PATH is not consulted.
    static func executable(candidates: [String] = defaultCandidates,
                           exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        candidates.first(where: exists)
    }

    private static let sectionMarker = "➤ "
    private static let glyphs: [(prefix: String, kind: MoleLine.Kind)] = [
        ("○ ", .item), ("✓ ", .clear), ("◎ ", .skipped), ("⊙ ", .info),
    ]
    private static let statusGlyph = "⚙ "

    /// Headings and banners that frame a report without being part of it.
    private static let bannerExact: Set<String> = [
        "Clean Your Mac", "Optimize", "Purge Project Artifacts", "Dry run complete - no changes made",
    ]
    private static let bannerPrefixes = ["Dry Run Mode", "○ DRY RUN MODE"]

    static func parse(_ text: String) -> MoleReport {
        var report = MoleReport()
        var current: MoleSection?

        func closeSection() {
            if let section = current, !section.lines.isEmpty || !section.title.isEmpty {
                report.sections.append(section)
            }
            current = nil
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || isRule(line) || bannerExact.contains(line)
                || bannerPrefixes.contains(where: { line.hasPrefix($0) }) { continue }
            if line.hasPrefix("Potential space:") { report.summary = line; continue }
            if line.hasPrefix("Detailed file list: ") {
                report.listPath = String(line.dropFirst("Detailed file list: ".count))
                continue
            }
            if line.hasPrefix(sectionMarker) {
                closeSection()
                current = MoleSection(title: String(line.dropFirst(sectionMarker.count)), lines: [])
                continue
            }
            if line.hasPrefix(statusGlyph) {
                report.notes.append(String(line.dropFirst(statusGlyph.count)))
                continue
            }
            if let glyph = glyphs.first(where: { line.hasPrefix($0.prefix) }) {
                let entry = MoleLine(kind: glyph.kind, text: String(line.dropFirst(glyph.prefix.count)))
                if current == nil { current = MoleSection(title: "", lines: []) }
                current?.lines.append(entry)
                continue
            }
            report.notes.append(line)
        }
        closeSection()
        return report
    }

    /// A line of equals or box drawing characters only.
    private static func isRule(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { "=-─━".contains($0) }
    }

    // MARK: Progress

    static let logLimit = 200

    static func progress(of text: String) -> MoleProgress {
        let report = parse(text)
        var progress = MoleProgress()
        progress.log = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(logLimit)
        progress.log = Array(progress.log)
        let titled = report.sections.filter { !$0.title.isEmpty }
        progress.section = titled.last?.title
        progress.finishedSections = max(0, titled.count - 1)
        let lines = report.sections.flatMap(\.lines)
        progress.lastLine = lines.last
        for line in lines where line.kind == .item {
            progress.itemCount += 1
            let added = progress.foundBytes.addingReportingOverflow(bytes(in: line.text) ?? 0)
            progress.foundBytes = added.overflow ? Int64.max : added.partialValue
        }
        return progress
    }

    /// A size in at most four or five characters, for the island's strip:
    /// "291K", "17M", "1.5G". Nothing found yet is an ellipsis.
    static func shortSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "…" }
        let units: [(String, Double)] = [("T", 1_099_511_627_776), ("G", 1_073_741_824),
                                         ("M", 1_048_576), ("K", 1_024)]
        guard let unit = units.first(where: { Double(bytes) >= $0.1 }) else { return "\(bytes)B" }
        let value = Double(bytes) / unit.1
        // A fixed region: this is a compact reading, not prose in the user's language.
        let region = Locale(identifier: "en_US")
        return (value < 10 ? String(format: "%.1f", locale: region, value)
                           : String(format: "%.0f", locale: region, value)) + unit.0
    }

    /// The first size Mole states in a line ("1.85GB", "291KB"), in bytes.
    static func bytes(in text: String) -> Int64? {
        let units: [(String, Double)] = [("TB", 1_099_511_627_776), ("GB", 1_073_741_824), ("MB", 1_048_576), ("KB", 1_024), ("B", 1)]
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else { index += 1; continue }
            var end = index
            while end < characters.count, characters[end].isNumber || characters[end] == "." { end += 1 }
            let number = String(characters[index..<end])
            let rest = String(characters[end...])
            if let value = Double(number),
               let unit = units.first(where: { rest.hasPrefix($0.0) }),
               !(rest.dropFirst(unit.0.count).first?.isLetter ?? false),
               !(index > 0 && characters[index - 1].isLetter) {
                let scaled = (value * unit.1).rounded()
                // A file name can carry any digits; a size that does not fit is no size.
                guard scaled.isFinite, scaled < Double(Int64.max) else { return nil }
                return Int64(scaled)
            }
            index = end
        }
        return nil
    }

    // MARK: Slim

    /// Rows are a name, two or more spaces, and a size; the footer is
    /// "18 apps, 1.29GB of Intel code".
    static func parseSlim(_ text: String) -> MoleSlimList {
        var list = MoleSlimList()
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.contains(" of Intel code"), let comma = line.range(of: ", ") {
                let rest = line[comma.upperBound...]
                list.total = rest.components(separatedBy: " of ").first
                continue
            }
            guard let gap = line.range(of: "  ", options: .backwards) else { continue }
            let name = line[..<gap.lowerBound].trimmingCharacters(in: .whitespaces)
            let size = line[gap.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, isSize(size) else { continue }
            list.apps.append(MoleSlimApp(name: name, size: size))
        }
        return list
    }

    private static func isSize(_ text: String) -> Bool {
        for unit in ["KB", "MB", "GB", "TB", "B"] where text.hasSuffix(unit) {
            let number = text.dropLast(unit.count)
            return !number.isEmpty && Double(number) != nil
        }
        return false
    }

    // MARK: Outcome

    /// The amount a real run says it removed or freed.
    static func removedAmount(in text: String) -> String? {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            for prefix in ["Removed: ", "Estimated space freed: "] where line.hasPrefix(prefix) {
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// Mole's detailed list lives in its own config folder. A path anywhere
    /// else, or a file that is not plain text, is never opened.
    static func isTrustedListPath(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let folder = URL(fileURLWithPath: home).appendingPathComponent(".config/mole").standardizedFileURL
        return url.pathExtension == "txt" && url.deletingLastPathComponent().path == folder.path
    }

    /// The last `lines` lines, for showing a failure without the whole log.
    static func tail(of text: String, lines count: Int) -> String {
        let all = text.components(separatedBy: .newlines)
        return all.suffix(max(1, count)).joined(separator: "\n")
    }

    // MARK: Terminal

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A script for a Terminal window: the command, a pause so the output can
    /// be read, and the script's own removal. Every part is quoted, and only
    /// fixed program paths and this file's own argument lists reach it.
    static func terminalScript(executable: String, arguments: [String]) -> String {
        let command = ([executable] + arguments).map(shellQuote).joined(separator: " ")
        return """
        #!/bin/zsh
        trap 'rm -f -- "$0"' EXIT
        clear
        \(command)
        echo
        echo "Finished. You can close this window."

        """
    }
}
