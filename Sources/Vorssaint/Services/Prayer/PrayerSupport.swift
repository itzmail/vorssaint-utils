// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What sounds when a prayer's time comes.
enum PrayerSound: String, CaseIterable {
    case adzan, tone, silent
}

/// What actually plays for one prayer.
enum PrayerPlayback: Equatable {
    case adzan, tone, silent
}

struct PrayerFire: Equatable {
    let moment: PrayerMoment
    let due: PrayerDue
}

/// What one look at the clock found: the prayers whose time came since the
/// last look, and where the next look starts.
struct PrayerTick: Equatable {
    let handledUntil: Int
    let fires: [PrayerFire]
}

enum PrayerSchedule {
    /// A clock moved back by more than this starts over from the new time.
    private static let clockSetBack = 3600

    /// The prayers in (`handledUntil`, `now`] and how each is to be treated:
    /// on time it rings; after a sleep or a restart it shows without sound;
    /// older than that it is left alone. The first look only marks the time,
    /// so starting the app after Maghrib does not announce Maghrib.
    static func advance(_ site: PrayerSite, handledUntil: Int?, now: Int) -> PrayerTick {
        guard let from = handledUntil else { return PrayerTick(handledUntil: now, fires: []) }
        if from - now > clockSetBack { return PrayerTick(handledUntil: now, fires: []) }
        guard now > from else { return PrayerTick(handledUntil: from, fires: []) }
        let fires = PrayerEngine.prayers(site, from: from, to: now).compactMap { moment -> PrayerFire? in
            let due = PrayerEngine.due(at: moment.at, now: now)
            return due == .skip ? nil : PrayerFire(moment: moment, due: due)
        }
        return PrayerTick(handledUntil: now, fires: fires)
    }
}

enum PrayerSupport {
    /// How often the location is asked again while the Mac follows it.
    static let locationInterval = 3 * 3600
    static let maximumRemindMinutes = 60

    // MARK: Decisions

    /// `ring` is false for a prayer that came late, or while a full-screen app
    /// hides the island. The recording is not Subuh's adzan (it lacks "ash-shalatu
    /// khairum minan naum"), so Subuh takes the tone.
    static func playback(_ prayer: Prayer, sound: PrayerSound, ring: Bool) -> PrayerPlayback {
        guard ring else { return .silent }
        switch sound {
        case .adzan: return prayer == .subuh ? .tone : .adzan
        case .tone: return .tone
        case .silent: return .silent
        }
    }

    static func needsLocation(follow: Bool, locatedAt: Int?, now: Int) -> Bool {
        guard follow else { return false }
        guard let locatedAt, locatedAt <= now else { return true }
        return now - locatedAt >= locationInterval
    }

    /// "14:51 · Kota Jakarta": when, on the place's own clock, and where.
    static func detail(_ moment: PrayerMoment, site: PrayerSite, placeLabel: String) -> String {
        let time = site.hhmm(moment.at)
        return placeLabel.isEmpty ? time : "\(time) \u{00B7} \(placeLabel)"
    }

    // MARK: Preferences

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.prayerEnabled)
    }

    static func placeID(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: DefaultsKey.prayerPlace).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func followsLocation(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.prayerFollowLocation) as? Bool ?? true
    }

    static func sound(in defaults: UserDefaults = .standard) -> PrayerSound {
        defaults.string(forKey: DefaultsKey.prayerSound).flatMap(PrayerSound.init(rawValue:)) ?? .tone
    }

    /// Minutes before each prayer the island counts down; 0 is no countdown.
    static func remindBeforeMinutes(in defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: DefaultsKey.prayerRemindBefore) as? Int ?? 10
        return min(maximumRemindMinutes, max(0, stored))
    }

    static func pausesMusic(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.prayerPauseMusic) as? Bool ?? true
    }
}
