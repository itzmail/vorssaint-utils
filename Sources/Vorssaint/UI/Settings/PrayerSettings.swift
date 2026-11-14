// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The prayer times: the place, the sound and the countdown in the island.
struct PrayerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = PrayerService.shared
    @AppStorage(DefaultsKey.prayerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.prayerFollowLocation) private var follows = true
    @AppStorage(DefaultsKey.prayerSound) private var soundRaw = PrayerSound.tone.rawValue
    @AppStorage(DefaultsKey.prayerRemindBefore) private var remind = 10
    @AppStorage(DefaultsKey.prayerPauseMusic) private var pauseMusic = true
    @State private var query = ""

    private static let countdownChoices = [5, 10, 15, 20, 30]

    private var text: PrayerStrings { FeatureStrings.prayer(l10n.language) }

    var body: some View {
        Form {
            Section {
                Toggle(text.title, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in syncAll() }
                Text(text.description).font(.caption).foregroundStyle(.secondary)
            }
            if enabled {
                placeSection
                timesSection
                soundSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Place

    private var placeSection: some View {
        Section(text.place) {
            if let place = service.place {
                LabeledContent(place.label) {
                    Text([place.province, Self.methodName(place.method)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(text.followLocation, isOn: $follows)
                .onChange(of: follows) { _, on in service.setFollowsLocation(on) }
            Text(text.followHint).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(text.useLocationNow) { service.locateNow() }
                    .disabled(service.locationStatus == .asking)
                Spacer()
                locationStatus
            }
            if service.locationStatus == .denied {
                Button(text.openSettings) { Self.openLocationSettings() }
            }
            TextField(text.search, text: $query)
            ForEach(service.search(query), id: \.id) { place in
                Button {
                    service.choosePlace(place.id)
                    query = ""
                } label: {
                    HStack {
                        Text(place.label)
                        Spacer()
                        Text(place.province).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var locationStatus: some View {
        switch service.locationStatus {
        case .idle: EmptyView()
        case .asking: Text(text.locating).font(.caption).foregroundStyle(.secondary)
        case .found: Label(text.located, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .denied: Text(text.denied).font(.caption).foregroundStyle(.orange)
        case .unknown: Text(text.unknown).font(.caption).foregroundStyle(.orange)
        case .unsupported: Text(text.unsupported).font(.caption).foregroundStyle(.orange)
        }
    }

    // MARK: Times

    @ViewBuilder private var timesSection: some View {
        if let today = service.today() {
            Section(text.next) {
                if let next = service.next {
                    LabeledContent(next.prayer.name) { Text(today.site.hhmm(next.at)).monospacedDigit() }
                        .font(.headline)
                }
                ForEach(PrayerTime.allCases, id: \.self) { time in
                    LabeledContent(time.name) { Text(today.site.hhmm(today.times.get(time))).monospacedDigit() }
                }
            }
        }
    }

    // MARK: Sound

    private var soundSection: some View {
        Section(text.sound) {
            Picker(text.sound, selection: $soundRaw) {
                Text(text.soundAdzan).tag(PrayerSound.adzan.rawValue)
                Text(text.soundTone).tag(PrayerSound.tone.rawValue)
                Text(text.soundSilent).tag(PrayerSound.silent.rawValue)
            }
            .pickerStyle(.segmented)
            Toggle(text.pauseMusic, isOn: $pauseMusic)
            Picker(text.countdown, selection: $remind) {
                Text(text.countdownOff).tag(0)
                ForEach(Self.countdownChoices, id: \.self) { Text(text.countdownText($0)).tag($0) }
            }
            .onChange(of: remind) { _, _ in syncAll() }
            HStack {
                Button(text.test) { service.test() }
                if service.adzanPlaying {
                    Button(text.stop) { service.stopAdzan() }
                }
            }
            Text(text.soundNote).font(.caption).foregroundStyle(.secondary)
            Text(text.credits).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func syncAll() {
        PrayerService.shared.syncWithPreferences()
        NotchService.shared.syncWithPreferences()
    }

    private static func methodName(_ method: PrayerMethod) -> String {
        method == .kemenag ? "Kemenag RI" : "Umm al-Qura"
    }

    private static func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
