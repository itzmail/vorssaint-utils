// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Mole bridge's decisions: where `mo` is found, what each command is run
/// with, and how its plain text report reads. The fixtures are real dry runs
/// captured with no terminal attached, which is how the app runs the tool.
enum MoleSupportTests {
    static func run(_ suite: TestSuite) {
        locatorContracts(suite)
        commandContracts(suite)
        cleanReportContracts(suite)
        emptyReportContracts(suite)
        optimizeReportContracts(suite)
        slimContracts(suite)
        outcomeContracts(suite)
        terminalContracts(suite)
        progressContracts(suite)
        shortSizeContracts(suite)
    }

    private static func fixture(_ name: String) -> String {
        (try? String(contentsOfFile: "Tests/Fixtures/Mole/\(name).txt", encoding: .utf8)) ?? ""
    }

    // MARK: Locator

    private static func locatorContracts(_ suite: TestSuite) {
        let found = MoleSupport.executable(candidates: ["/a/mo", "/b/mo"]) { $0 == "/b/mo" }
        suite.expect(found == "/b/mo", "the first candidate that exists is used")
        suite.expect(MoleSupport.executable(candidates: ["/a/mo"], exists: { _ in false }) == nil,
                     "no candidate means Mole is not installed")
        suite.expect(MoleSupport.defaultCandidates.first == "/opt/homebrew/bin/mo"
                     && MoleSupport.defaultCandidates.contains("/usr/local/bin/mo"),
                     "Homebrew's Apple Silicon and Intel prefixes are both searched")
    }

    // MARK: Commands

    private static func commandContracts(_ suite: TestSuite) {
        suite.expect(MoleCommand.clean.previewArguments == ["clean", "--dry-run"], "clean previews with --dry-run")
        suite.expect(MoleCommand.slim.previewArguments == ["slim", "--dry-run"], "slim previews with --dry-run")
        suite.expect(MoleCommand.clean.runArguments == ["clean"], "clean runs unattended as is")
        suite.expect(MoleCommand.purge.runArguments == ["purge", "--yes"],
                     "purge needs --yes to run without a terminal")
        suite.expect(MoleCommand.optimize.runArguments == ["optimize"], "optimize runs unattended as is")
        suite.expect(MoleCommand.slim.runsInTerminal && MoleCommand.installer.runsInTerminal,
                     "slim and installer pick their items in a terminal, so they run there")
        suite.expect(!MoleCommand.clean.runsInTerminal && !MoleCommand.purge.runsInTerminal
                     && !MoleCommand.optimize.runsInTerminal,
                     "clean, purge and optimize run inside the app")
        suite.expect(MoleCommand.allCases.count == 5, "five commands are offered")
        suite.expect(MoleCommand.optimize.changesSystemServices && !MoleCommand.clean.changesSystemServices,
                     "only optimize carries the system services warning")
    }

    // MARK: Reports

    private static func cleanReportContracts(_ suite: TestSuite) {
        let report = MoleSupport.parse(fixture("clean"))
        let titles = report.sections.map(\.title).filter { !$0.isEmpty }
        suite.expect(titles.first == "User essentials", "the first section is User essentials: \(titles)")
        suite.expect(titles.contains("Developer tools") && titles.contains("Large files"),
                     "Developer tools and Large files are sections")
        let dev = report.sections.first { $0.title == "Developer tools" }
        suite.expect(dev?.lines.contains { $0.kind == .item && $0.text.hasPrefix("npm cache directory") } == true,
                     "an item line keeps its text without the glyph")
        suite.expect(dev?.lines.contains { $0.kind == .skipped && $0.text.hasPrefix("Project caches") } == true,
                     "a skipped line is recognised")
        suite.expect(dev?.lines.contains { $0.kind == .info && $0.text.hasPrefix("Homebrew unused") } == true,
                     "an info line is recognised")
        let browsers = report.sections.first { $0.title == "Browsers" }
        suite.expect(browsers?.lines.first?.kind == .clear && browsers?.isClear == true,
                     "a section that only says nothing to clean is clear")
        suite.expect(report.summary == "Potential space: 5.13GB · 705 items",
                     "the potential space line is the summary: \(report.summary ?? "nil")")
        suite.expect(report.reclaimable == "5.13GB", "the reclaimable size is read from the summary")
        suite.expect(report.listPath == "/Users/user/.config/mole/clean-list.txt",
                     "the detailed list path is read: \(report.listPath ?? "nil")")
        suite.expect(!report.notes.contains { $0.contains("====") },
                     "the rule lines of the footer are not notes")
        suite.expect(!report.hasNothingToShow, "a populated report has something to show")
    }

    private static func emptyReportContracts(_ suite: TestSuite) {
        for name in ["purge", "installer"] {
            let report = MoleSupport.parse(fixture(name))
            suite.expect(report.sections.flatMap(\.lines).contains { $0.kind == .clear },
                         "\(name): the nothing to clean line is kept")
            suite.expect(report.hasNothingToClean, "\(name): an empty result is detected")
            suite.expect(report.summary == nil, "\(name): there is no summary")
        }
        suite.expect(MoleSupport.parse("").hasNothingToShow, "empty text is nothing to show")
        let odd = MoleSupport.parse("something unexpected\nline two")
        suite.expect(odd.notes == ["something unexpected", "line two"],
                     "text the parser does not know is kept as notes, never dropped")
    }

    private static func optimizeReportContracts(_ suite: TestSuite) {
        let report = MoleSupport.parse(fixture("optimize"))
        let titles = report.sections.map(\.title)
        suite.expect(titles.contains("Finder Cache Refresh") && titles.contains("Spotlight Optimization"),
                     "optimize sections are read: \(titles)")
        let first = report.sections.first { $0.title == "Finder Cache Refresh" }
        suite.expect(first?.lines.count == 2 && first?.lines.allSatisfy { $0.kind == .item } == true,
                     "optimize steps are item lines")
        suite.expect(report.notes.contains { $0.hasPrefix("System") },
                     "the system status line is a note: \(report.notes)")
    }

    // MARK: Slim

    private static func slimContracts(_ suite: TestSuite) {
        let slim = MoleSupport.parseSlim(fixture("slim"))
        suite.expect(slim.apps.count == 18, "eighteen apps are listed: \(slim.apps.count)")
        suite.expect(slim.apps.first?.name == "Claude" && slim.apps.first?.size == "234.0MB",
                     "an app row keeps its name and size")
        suite.expect(slim.apps.contains { $0.name == "Visual Studio Code" && $0.size == "187.3MB" },
                     "a name with spaces survives")
        suite.expect(slim.apps.last?.name == "Mounty" && slim.apps.last?.size == "218KB",
                     "a KB size is read")
        suite.expect(slim.total == "1.29GB", "the total is read from the footer: \(slim.total ?? "nil")")
        suite.expect(MoleSupport.parseSlim("✓ No apps with Intel code to remove").apps.isEmpty,
                     "no apps parses as an empty list")
    }

    // MARK: Outcome

    private static func outcomeContracts(_ suite: TestSuite) {
        suite.expect(MoleSupport.removedAmount(in: "Removed: 1.2GB\nfoo") == "1.2GB", "clean's removed line")
        suite.expect(MoleSupport.removedAmount(in: "Estimated space freed: 3.4MB") == "3.4MB",
                     "purge's freed line")
        suite.expect(MoleSupport.removedAmount(in: "nothing here") == nil, "no amount when none is printed")
        suite.expect(MoleSupport.tail(of: "a\nb\nc\nd", lines: 2) == "c\nd", "the tail keeps the last lines")
        suite.expect(MoleSupport.tail(of: "a", lines: 5) == "a", "a short text is kept whole")
    }

    // MARK: Terminal

    private static func terminalContracts(_ suite: TestSuite) {
        suite.expect(MoleSupport.shellQuote("a b") == "'a b'", "a plain word is single quoted")
        suite.expect(MoleSupport.shellQuote("it's") == "'it'\\''s'", "a single quote is closed, escaped and reopened")
        let script = MoleSupport.terminalScript(executable: "/opt/homebrew/bin/mo", arguments: ["slim"])
        suite.expect(script.hasPrefix("#!/bin/zsh\n"), "the script runs under zsh")
        suite.expect(script.contains("'/opt/homebrew/bin/mo' 'slim'"), "the command is quoted: \(script)")
        suite.expect(script.contains("trap 'rm -f -- \"$0\"' EXIT"), "the script removes itself however it ends")
        suite.expect(MoleSupport.isTrustedListPath("/Users/u/.config/mole/clean-list.txt", home: "/Users/u"),
                     "Mole's own list is trusted")
        suite.expect(!MoleSupport.isTrustedListPath("/Applications/Evil.app", home: "/Users/u")
                     && !MoleSupport.isTrustedListPath("/Users/u/.config/mole/../x/clean-list.txt", home: "/Users/u")
                     && !MoleSupport.isTrustedListPath("/Users/u/.config/mole/run.command", home: "/Users/u"),
                     "any other location or file type is refused")
        let install = MoleSupport.terminalScript(executable: "/opt/homebrew/bin/brew", arguments: ["install", "mole"])
        suite.expect(install.contains("'/opt/homebrew/bin/brew' 'install' 'mole'"), "any tool can be run the same way")
    }

    // MARK: Progress

    private static func progressContracts(_ suite: TestSuite) {
        suite.expect(MoleSupport.bytes(in: "User app cache · 20 items, 1.85GB dry") == 1_986_422_374,
                     "a GB size is read with 1024 steps: \(String(describing: MoleSupport.bytes(in: "User app cache · 20 items, 1.85GB dry")))")
        suite.expect(MoleSupport.bytes(in: "VS Code logs · 291KB dry") == 297_984, "a KB size is read")
        suite.expect(MoleSupport.bytes(in: "npm cache · would clean") == nil, "no size means nil")
        suite.expect(MoleSupport.bytes(in: "Parsecd cache · 15 items, 17.1MB dry") == 17_930_650,
                     "a count before the size is not mistaken for it")

        let lines = fixture("clean").components(separatedBy: "\n")
        func upTo(_ marker: String, including: Bool) -> String {
            let index = lines.firstIndex { $0.contains(marker) } ?? 0
            return lines[..<(including ? index + 1 : index)].joined(separator: "\n")
        }

        suite.expect(MoleSupport.bytes(in: "99999999999999999999999999GB.dmg") == nil,
                     "a size that does not fit in 64 bits is no size")
        let huge = MoleSupport.progress(of: "➤ A\n  ○ x · 4000000TB\n  ○ y · 4000000TB\n  ○ z · 4000000TB\n")
        suite.expect(huge.foundBytes == Int64.max && huge.itemCount == 3,
                     "a total that overflows is clamped: \(huge.foundBytes)")

        let logged = MoleSupport.progress(of: "➤ A\n\n  ○ x · 1KB\n  \n  ✓ y\n")
        suite.expect(logged.log == ["➤ A", "○ x · 1KB", "✓ y"],
                     "the log keeps the printed lines, blanks dropped: \(logged.log)")
        let long = (1...500).map { "line \($0)" }.joined(separator: "\n")
        let cut = MoleSupport.progress(of: long)
        suite.expect(cut.log.count == MoleSupport.logLimit && cut.log.last == "line 500",
                     "the log keeps the newest lines only: \(cut.log.count)")

        let none = MoleSupport.progress(of: "")
        suite.expect(none.section == nil && none.finishedSections == 0 && none.itemCount == 0,
                     "nothing printed means no progress")

        let start = MoleSupport.progress(of: upTo("User essentials", including: true))
        suite.expect(start.section == "User essentials" && start.finishedSections == 0,
                     "a heading with no items yet is the section being scanned: \(String(describing: start.section))")

        let mid = MoleSupport.progress(of: upTo("Browsers", including: true))
        suite.expect(mid.section == "Browsers" && mid.finishedSections == 2,
                     "the heading just printed is current, the two before it are finished: \(mid.finishedSections)")
        suite.expect(mid.itemCount == 7 && mid.foundBytes > 1_900_000_000,
                     "items and sizes so far are totalled: \(mid.itemCount), \(mid.foundBytes)")
        suite.expect(mid.lastLine?.text.hasPrefix("Apple Python cache") == true,
                     "the last finished line is kept: \(mid.lastLine?.text ?? "nil")")

        let full = MoleSupport.progress(of: fixture("clean"))
        suite.expect(full.section == "Project artifacts" && full.finishedSections == 13,
                     "the full report ends on its last heading: \(full.section ?? "nil"), \(full.finishedSections)")
        suite.expect(full.foundBytes >= mid.foundBytes, "the total never shrinks as the report grows")
        let skipped = MoleSupport.progress(of: "➤ A\n  ◎ Trash · skipped\n  ⊙ Big · 9.00GB\n")
        suite.expect(skipped.itemCount == 0 && skipped.foundBytes == 0,
                     "skipped and info lines do not count as found")
    }

    // MARK: Short size

    private static func shortSizeContracts(_ suite: TestSuite) {
        suite.expect(MoleSupport.shortSize(0) == "…", "nothing found yet reads as an ellipsis")
        suite.expect(MoleSupport.shortSize(512) == "512B", "bytes")
        suite.expect(MoleSupport.shortSize(297_984) == "291K", "kilobytes are whole numbers")
        suite.expect(MoleSupport.shortSize(17_930_650) == "17M", "megabytes of ten or more are whole")
        suite.expect(MoleSupport.shortSize(5_242_880) == "5.0M", "under ten keeps one decimal")
        suite.expect(MoleSupport.shortSize(1_610_612_736) == "1.5G", "gigabytes keep one decimal under ten")
        suite.expect(MoleSupport.shortSize(12 * 1_073_741_824) == "12G", "gigabytes of ten or more are whole")
        suite.expect(MoleSupport.shortSize(5_000_000_000_000).count <= 5, "the reading stays short")
    }
}
