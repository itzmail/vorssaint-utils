// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Static identity of the app, shared by UI, notifications and tooling.
enum AppInfo {
    static let name = "Solvane"
    static let copyright = "© 2026 itzmail. Based on Vorssaint, © 2026 Vorssaint, GPL-3.0. Not an official Vorssaint release."
    static let websiteURL = URL(string: "https://github.com/itzmail/vorssaint-utils")!
    static let repositoryURL = URL(string: "https://github.com/itzmail/vorssaint-utils")!
    /// True in this fork. It is not an official Vorssaint release, so the in-app
    /// updater (which only trusts the maintainer's signing identity) stays off
    /// and updates come through the Homebrew tap instead.
    static let isForkBuild = true
    static var updatesAreDisabled: Bool { isDeveloperBuild || isForkBuild }
    /// Link sharing and feedback ran on the maintainer's servers. A fork must
    /// not use them, so this reserved host (RFC 6761) never resolves and
    /// nothing leaves the Mac until a server of the fork's own replaces it.
    static let sharingEndpoint = URL(string: "https://sharing.invalid")!
    /// The project this fork is built from. Shown in About as required credit.
    static let upstreamURL = URL(string: "https://github.com/vorssaint/vorssaint-utils")!
    static let coffeeURL = URL(string: "https://buymeacoffee.com/vorssaint")!
    static let discordURL = URL(string: "https://discord.gg/M6BwWH4BJp")!
    static let socialURL = URL(string: "https://x.com/vorssaint")!

    /// The bundle version. The fallback only applies to the bare binary
    /// (e.g. `--selftest`), never the shipped app, which reads its Info.plist.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// True for the local "Vorssaint (Developer)" build (bundle id ends in `.dev`).
    /// It is never published and never auto-updates; all work is tested here first.
    static var isDeveloperBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")
    }

    /// True when the current version is a pre-release (e.g. 3.3.4-beta.1 or 3.3.4-rc.1).
    static var isBeta: Bool {
        if isDeveloperBuild && UserDefaults.standard.bool(forKey: DefaultsKey.simulateBetaUI) {
            return true
        }
        let v = version.lowercased()
        return v.contains("-beta") || v.contains("-rc") || v.contains("-alpha")
    }

    /// The git commit a Developer build was compiled from, e.g. "ed2ebba · 2026-06-15 21:30"
    /// (or with a "-dirty" suffix on the SHA for uncommitted changes). build.sh stamps
    /// this into the Developer bundle only, so you can confirm at a glance that the
    /// running dev app matches the source you are about to change. nil in the official app.
    static var buildCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintBuildCommit") as? String
    }
}
