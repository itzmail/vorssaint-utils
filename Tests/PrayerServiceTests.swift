// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The prayer times' decisions: when a prayer is handled, what sounds for it,
/// when the location is asked again and what the preferences hold.
enum PrayerServiceTests {
    static func run(_ suite: TestSuite) {
        scheduleContracts(suite)
        playbackContracts(suite)
        locationContracts(suite)
        preferenceContracts(suite)
        textContracts(suite)
    }

    private static let jakarta = PrayerSite(latitude: -6.1833, longitude: 106.8333, offset: 420, horizon: -1,
                                            subuhAngle: 20, isyaAngle: 18, method: .kemenag)

    private static func utc(_ date: String, _ hhmm: String) -> Int {
        let d = date.split(separator: "-").compactMap { Int($0) }
        let t = hhmm.split(separator: ":").compactMap { Int($0) }
        return PrayerCalendar.days(year: d[0], month: d[1], day: d[2]) * 86_400 + (t[0] * 60 + t[1]) * 60 - 420 * 60
    }

    // MARK: Schedule

    private static func scheduleContracts(_ suite: TestSuite) {
        // Jakarta, 24 Oct 2026: Ashar 14:51.
        let ashar = utc("2026-10-24", "14:51")
        let first = PrayerSchedule.advance(jakarta, handledUntil: nil, now: ashar - 600)
        suite.expect(first.fires.isEmpty && first.handledUntil == ashar - 600,
                     "the first look only marks the time: nothing rings for a prayer that is already past")

        let on = PrayerSchedule.advance(jakarta, handledUntil: ashar - 5, now: ashar + 2)
        suite.expect(on.fires.map(\.moment.prayer) == [.ashar] && on.fires.map(\.due) == [.ring] && on.handledUntil == ashar + 2,
                     "a prayer that comes while the app watches rings once")
        let again = PrayerSchedule.advance(jakarta, handledUntil: on.handledUntil, now: ashar + 7)
        suite.expect(again.fires.isEmpty, "and is not handled twice")

        let slept = PrayerSchedule.advance(jakarta, handledUntil: ashar - 600, now: ashar + 20 * 60)
        suite.expect(slept.fires.map(\.moment.prayer) == [.ashar] && slept.fires.map(\.due) == [.quiet],
                     "a prayer that came during a sleep shows without sound")
        let long = PrayerSchedule.advance(jakarta, handledUntil: ashar - 600, now: ashar + 2 * 3600)
        suite.expect(long.fires.isEmpty && long.handledUntil == ashar + 2 * 3600,
                     "one that came hours ago is left alone")
        let overnight = PrayerSchedule.advance(jakarta, handledUntil: utc("2026-10-24", "12:00"), now: utc("2026-10-25", "05:30"))
        suite.expect(overnight.fires.isEmpty, "a night's sleep does not replay the evening")

        let same = PrayerSchedule.advance(jakarta, handledUntil: ashar, now: ashar)
        suite.expect(same.fires.isEmpty && same.handledUntil == ashar, "no time passed, nothing to do")
        let back = PrayerSchedule.advance(jakarta, handledUntil: ashar + 5 * 3600, now: ashar)
        suite.expect(back.fires.isEmpty && back.handledUntil == ashar,
                     "a clock moved far back starts over from the new time")
        let slightly = PrayerSchedule.advance(jakarta, handledUntil: ashar + 30, now: ashar)
        suite.expect(slightly.fires.isEmpty && slightly.handledUntil == ashar + 30,
                     "a clock a little behind waits for time to catch up")
    }

    // MARK: Sound

    private static func playbackContracts(_ suite: TestSuite) {
        suite.expect(PrayerSupport.playback(.ashar, sound: .adzan, ring: true) == .adzan
                        && PrayerSupport.playback(.maghrib, sound: .adzan, ring: true) == .adzan,
                     "the adzan plays for the day's prayers")
        suite.expect(PrayerSupport.playback(.subuh, sound: .adzan, ring: true) == .tone,
                     "the recording has no Subuh adzan, so Subuh gets the tone")
        suite.expect(PrayerSupport.playback(.dzuhur, sound: .tone, ring: true) == .tone, "the tone is the tone")
        suite.expect(PrayerSupport.playback(.dzuhur, sound: .silent, ring: true) == .silent, "silent is silent")
        suite.expect(Prayer.allCases.allSatisfy { PrayerSupport.playback($0, sound: .adzan, ring: false) == .silent },
                     "a prayer that is late, or hidden by a full-screen app, never sounds")
    }

    // MARK: Location

    private static func locationContracts(_ suite: TestSuite) {
        let now = 1_000_000
        suite.expect(PrayerSupport.needsLocation(follow: true, locatedAt: nil, now: now), "a first ask is due")
        suite.expect(!PrayerSupport.needsLocation(follow: true, locatedAt: now - 3 * 3600 + 1, now: now), "not before three hours")
        suite.expect(PrayerSupport.needsLocation(follow: true, locatedAt: now - 3 * 3600, now: now), "after three hours")
        suite.expect(!PrayerSupport.needsLocation(follow: false, locatedAt: nil, now: now), "a place picked by hand is never moved")
        suite.expect(PrayerSupport.needsLocation(follow: true, locatedAt: now + 3600, now: now),
                     "a clock moved back asks again")
    }

    // MARK: Preferences

    private static func preferenceContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.prayer-service"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        suite.expect(PrayerSupport.sound(in: defaults) == .tone && PrayerSupport.remindBeforeMinutes(in: defaults) == 10
                        && PrayerSupport.followsLocation(in: defaults) && PrayerSupport.pausesMusic(in: defaults)
                        && PrayerSupport.placeID(in: defaults) == nil,
                     "a fresh Mac gets the tone, ten minutes of notice, location and a pause for music")
        defaults.set("adzan", forKey: DefaultsKey.prayerSound)
        defaults.set(5, forKey: DefaultsKey.prayerRemindBefore)
        defaults.set(false, forKey: DefaultsKey.prayerFollowLocation)
        defaults.set(false, forKey: DefaultsKey.prayerPauseMusic)
        defaults.set("bandung", forKey: DefaultsKey.prayerPlace)
        suite.expect(PrayerSupport.sound(in: defaults) == .adzan && PrayerSupport.remindBeforeMinutes(in: defaults) == 5
                        && !PrayerSupport.followsLocation(in: defaults) && !PrayerSupport.pausesMusic(in: defaults)
                        && PrayerSupport.placeID(in: defaults) == "bandung",
                     "what is chosen is what is read")
        defaults.set("loud", forKey: DefaultsKey.prayerSound)
        defaults.set(9_999, forKey: DefaultsKey.prayerRemindBefore)
        suite.expect(PrayerSupport.sound(in: defaults) == .tone && PrayerSupport.remindBeforeMinutes(in: defaults) == 60,
                     "an unknown sound falls back and a long notice is cut to an hour")
        defaults.set(-4, forKey: DefaultsKey.prayerRemindBefore)
        suite.expect(PrayerSupport.remindBeforeMinutes(in: defaults) == 0, "a negative notice is off")
        defaults.set("", forKey: DefaultsKey.prayerPlace)
        suite.expect(PrayerSupport.placeID(in: defaults) == nil, "an empty place is no place")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.prayerFollowLocation] as? Bool == true
                        && Defaults.registeredDefaults[DefaultsKey.prayerSound] as? String == "tone"
                        && Defaults.registeredDefaults[DefaultsKey.prayerRemindBefore] as? Int == 10
                        && Defaults.registeredDefaults[DefaultsKey.prayerPauseMusic] as? Bool == true,
                     "the defaults are registered")
    }

    // MARK: Text

    private static func textContracts(_ suite: TestSuite) {
        let ashar = utc("2026-10-24", "14:51")
        let moment = PrayerMoment(prayer: .ashar, at: ashar, end: ashar + 10_000, day: 20_750)
        suite.expect(PrayerSupport.detail(moment, site: jakarta, placeLabel: "Kota Jakarta") == "14:51 \u{00B7} Kota Jakarta",
                     "a notice says when and where")
        suite.expect(PrayerSupport.detail(moment, site: jakarta, placeLabel: "") == "14:51",
                     "without a place it says only when")
    }
}
