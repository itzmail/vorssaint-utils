// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Prayer times for one place: the five daily prayers plus Imsak and Terbit,
/// and the next and current prayer. Every moment is UTC seconds since 1970 and
/// falls on a whole minute.
///
/// Indonesian places follow Kemenag RI's (Bimas Islam) rules, checked against
/// Kemenag's published 2026 schedule for all 517 of its locations:
/// - Subuh: sun 20° below the horizon; Isya: 18° (21° and 19° in six Papua
///   highland regencies, as Kemenag computes them).
/// - Ashar: a shadow as long as the object plus its noon shadow (Syafi'i).
/// - Terbit and Maghrib: the sun's centre at the place's horizon (-1°, or -2°
///   in highland places); Dzuhur: transit.
/// - Ihtiyat: round up to the whole minute, then add 2 minutes (Dzuhur 3);
///   Terbit drops the seconds, then takes 2 off. Imsak is Subuh minus 10.
///
/// Makkah, Madinah and Jeddah follow Umm al-Qura: Subuh at 18.5°, Isya 90
/// minutes after Maghrib (120 in Ramadan), to the nearest minute.
///
/// A place's own date decides the day, through its clock: one offset all year
/// in Indonesia and Saudi Arabia.
enum PrayerMethod: String {
    case kemenag
    case ummAlQura = "ummalqura"
}

/// A place's clock, in minutes east of UTC. Every zone the list uses keeps one
/// offset all year.
enum PrayerClock {
    static func offsetMinutes(zone: String) -> Int? {
        switch zone {
        case "Asia/Jakarta", "Asia/Pontianak": return 7 * 60
        case "Asia/Makassar": return 8 * 60
        case "Asia/Jayapura": return 9 * 60
        case "Asia/Riyadh": return 3 * 60
        default: return nil
        }
    }
}

/// A place reduced to what the engine needs.
struct PrayerSite: Equatable {
    var latitude: Double
    var longitude: Double
    var offset: Int
    /// Sun altitude for Terbit and Maghrib (Kemenag places only).
    var horizon: Double
    var subuhAngle: Double
    var isyaAngle: Double
    var method: PrayerMethod

    func offsetMinutes(at utc: Int) -> Int { offset }

    /// The place's own date (days since 1970-01-01) at a UTC moment.
    func localDay(_ utc: Int) -> Int {
        PrayerEngine.floorDivide(utc + offset * 60, 86_400)
    }

    /// Minutes after the place's midnight of `day`; outside 0..<1440 when the
    /// moment falls on another date.
    func localMinutes(_ utc: Int, day: Int) -> Int {
        PrayerEngine.floorDivide(utc + offset * 60 - day * 86_400, 60)
    }

    /// "HH:MM" on the place's own clock.
    func hhmm(_ utc: Int) -> String {
        let minute = PrayerEngine.floorDivide(utc + offset * 60, 60)
        let ofDay = ((minute % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", ofDay / 60, ofDay % 60)
    }
}

/// The five daily prayers, named as Kemenag writes them.
enum Prayer: CaseIterable {
    case subuh, dzuhur, ashar, maghrib, isya

    var name: String {
        switch self {
        case .subuh: return "Subuh"
        case .dzuhur: return "Dzuhur"
        case .ashar: return "Ashar"
        case .maghrib: return "Maghrib"
        case .isya: return "Isya"
        }
    }

    var time: PrayerTime {
        switch self {
        case .subuh: return .subuh
        case .dzuhur: return .dzuhur
        case .ashar: return .ashar
        case .maghrib: return .maghrib
        case .isya: return .isya
        }
    }
}

/// Every time a day's schedule lists, in order.
enum PrayerTime: CaseIterable {
    case imsak, subuh, terbit, dzuhur, ashar, maghrib, isya

    var name: String {
        switch self {
        case .imsak: return "Imsak"
        case .subuh: return "Subuh"
        case .terbit: return "Terbit"
        case .dzuhur: return "Dzuhur"
        case .ashar: return "Ashar"
        case .maghrib: return "Maghrib"
        case .isya: return "Isya"
        }
    }
}

/// One date's schedule at one place, UTC seconds.
struct PrayerDayTimes: Equatable {
    let imsak: Int
    let subuh: Int
    let terbit: Int
    let dzuhur: Int
    let ashar: Int
    let maghrib: Int
    let isya: Int

    func get(_ time: PrayerTime) -> Int {
        switch time {
        case .imsak: return imsak
        case .subuh: return subuh
        case .terbit: return terbit
        case .dzuhur: return dzuhur
        case .ashar: return ashar
        case .maghrib: return maghrib
        case .isya: return isya
        }
    }

    func prayer(_ prayer: Prayer) -> Int { get(prayer.time) }
}

/// One of the five prayers on one date, with when its time ends: Subuh at
/// Terbit, Isya at the next Subuh, the others at the following prayer.
struct PrayerMoment: Equatable {
    let prayer: Prayer
    /// UTC seconds.
    let at: Int
    /// UTC seconds.
    let end: Int
    /// The place's date it belongs to (days since 1970-01-01).
    let day: Int
}

/// What to do about a prayer time that passed at `at`, seen at `now`: on time
/// (within 2 minutes) it rings; after a sleep or a restart (within 30 minutes)
/// it shows without a sound; later than that it is left alone.
enum PrayerDue: Equatable {
    case ring, quiet, skip
}

struct PrayerCountdown: Equatable {
    let moment: PrayerMoment
    let minutes: Int
}

enum PrayerEngine {
    private static let minute = 60_000
    static let imsakBeforeSubuhMinutes = 10
    /// Kemenag's twilight angles, degrees below the horizon.
    static let kemenagSubuhAngle = 20.0
    static let kemenagIsyaAngle = 18.0

    static func floorDivide(_ number: Int, _ divisor: Int) -> Int {
        let quotient = number / divisor
        return number % divisor != 0 && (number < 0) != (divisor < 0) ? quotient - 1 : quotient
    }

    private static func ceilMinute(_ milliseconds: Int) -> Int { floorDivide(milliseconds + minute - 1, minute) * minute }
    private static func floorMinute(_ milliseconds: Int) -> Int { floorDivide(milliseconds, minute) * minute }
    /// JavaScript's `Math.round(t / 60000) * 60000`: half a minute rounds up.
    private static func nearestMinute(_ milliseconds: Int) -> Int { floorDivide(milliseconds + minute / 2, minute) * minute }

    // MARK: A day

    /// The schedule for the place's date `day` (days since 1970-01-01).
    static func dayTimes(_ site: PrayerSite, day: Int) -> PrayerDayTimes? {
        let date = PrayerCalendar.civil(days: day)
        let ms: [Int]?
        switch site.method {
        case .kemenag: ms = kemenag(site, date.year, date.month, date.day)
        case .ummAlQura: ms = ummAlQura(site, day, date.year, date.month, date.day)
        }
        guard let ms else { return nil }
        return PrayerDayTimes(imsak: (ms[0] - imsakBeforeSubuhMinutes * minute) / 1000, subuh: ms[0] / 1000,
                              terbit: ms[1] / 1000, dzuhur: ms[2] / 1000, ashar: ms[3] / 1000,
                              maghrib: ms[4] / 1000, isya: ms[5] / 1000)
    }

    /// Subuh, Terbit, Dzuhur, Ashar, Maghrib and Isya in UTC milliseconds.
    private static func kemenag(_ site: PrayerSite, _ year: Int, _ month: Int, _ day: Int) -> [Int]? {
        let base = PrayerAstronomy.Params(
            fajrAngle: site.subuhAngle, ishaAngle: site.isyaAngle, ishaIntervalMinutes: 0, shadowLength: 1,
            highLatitude: .recommended(latitude: site.latitude))
        guard let t = PrayerAstronomy.moments(year: year, month: month, day: day, latitude: site.latitude,
                                              longitude: site.longitude, params: base) else { return nil }
        // Terbit and Maghrib: the morning and evening moments with the sun at the horizon.
        var horizon = base
        horizon.fajrAngle = -site.horizon
        horizon.ishaAngle = -site.horizon
        guard let h = PrayerAstronomy.moments(year: year, month: month, day: day, latitude: site.latitude,
                                              longitude: site.longitude, params: horizon) else { return nil }
        return [ceilMinute(t.fajr + 2 * minute), floorMinute(h.fajr - 2 * minute), ceilMinute(t.dhuhr + 3 * minute),
                ceilMinute(t.asr + 2 * minute), ceilMinute(h.isha + 2 * minute), ceilMinute(t.isha + 2 * minute)]
    }

    private static func ummAlQura(_ site: PrayerSite, _ days: Int, _ year: Int, _ month: Int, _ day: Int) -> [Int]? {
        let params = PrayerAstronomy.Params(
            fajrAngle: 18.5, ishaAngle: 0, ishaIntervalMinutes: isRamadanUmmAlQura(day: days) ? 120 : 90,
            shadowLength: 1, highLatitude: .middleOfTheNight)
        guard let t = PrayerAstronomy.moments(year: year, month: month, day: day, latitude: site.latitude,
                                              longitude: site.longitude, params: params) else { return nil }
        return [t.fajr, t.sunrise, t.dhuhr, t.asr, t.sunset, t.isha].map(nearestMinute)
    }

    /// Ramadan in the Umm al-Qura calendar: (first day as days since 1970, length).
    /// From ICU's islamic-umalqura calendar; 1440-1501 AH.
    private static let ramadanUmmAlQura: [(start: Int, length: Int)] = [
        (18022, 29), (18376, 30), (18730, 30), (19084, 30), (19438, 29), (19792, 30), (20147, 29), (20502, 30), (20857, 29), (21211, 30),
        (21565, 30), (21919, 29), (22273, 30), (22628, 29), (22983, 29), (23337, 30), (23692, 29), (24046, 30), (24400, 30), (24754, 30),
        (25109, 29), (25463, 30), (25817, 29), (26172, 29), (26526, 30), (26881, 29), (27235, 30), (27590, 29), (27944, 30), (28298, 30),
        (28653, 29), (29007, 30), (29361, 29), (29716, 29), (30070, 30), (30425, 30), (30779, 30), (31133, 30), (31488, 29), (31842, 30),
        (32196, 30), (32550, 30), (32905, 29), (33259, 30), (33614, 29), (33968, 30), (34322, 30), (34677, 29), (35031, 30), (35385, 30),
        (35740, 29), (36095, 29), (36449, 30), (36803, 30), (37158, 29), (37512, 30), (37866, 30), (38221, 29), (38575, 30), (38929, 30),
        (39283, 30), (39637, 30),
    ]

    /// Is `day` (days since 1970-01-01) in Ramadan by Umm al-Qura?
    static func isRamadanUmmAlQura(day: Int) -> Bool {
        ramadanUmmAlQura.contains { day >= $0.start && day < $0.start + $0.length }
    }

    // MARK: Moments

    private static func moments(on day: Int, _ site: PrayerSite) -> [PrayerMoment]? {
        guard let today = dayTimes(site, day: day), let tomorrow = dayTimes(site, day: day + 1) else { return nil }
        let ends = [today.terbit, today.ashar, today.maghrib, today.isya, tomorrow.subuh]
        return zip(Prayer.allCases, ends).map { PrayerMoment(prayer: $0, at: today.prayer($0), end: $1, day: day) }
    }

    /// The prayers of the place's yesterday, today and tomorrow, in time order.
    private static func around(_ site: PrayerSite, _ utc: Int) -> [PrayerMoment] {
        let today = site.localDay(utc)
        return (today - 1...today + 1).flatMap { moments(on: $0, site) ?? [] }
    }

    /// The next of the five prayers strictly after `utc` (tomorrow's Subuh after Isya).
    static func nextPrayer(_ site: PrayerSite, after utc: Int) -> PrayerMoment? {
        around(site, utc).first { $0.at > utc }
    }

    /// The latest prayer whose time has come (at or before `utc`).
    static func currentPrayer(_ site: PrayerSite, at utc: Int) -> PrayerMoment? {
        around(site, utc).last { $0.at <= utc }
    }

    /// Every prayer time in (`from`, `to`], oldest first.
    static func prayers(_ site: PrayerSite, from: Int, to: Int) -> [PrayerMoment] {
        guard to > from else { return [] }
        let last = site.localDay(to) + 1
        var day = site.localDay(from) - 1
        var found: [PrayerMoment] = []
        while day <= last {
            found += (moments(on: day, site) ?? []).filter { $0.at > from && $0.at <= to }
            day += 1
        }
        return found
    }

    /// Whole minutes from `now` until `at`, counting a started minute as one.
    static func minutesUntil(now: Int, at: Int) -> Int { floorDivide(at - now + 59, 60) }

    /// The countdown before the next prayer: that prayer and the minutes left,
    /// while it is `beforeMinutes` away or less (0 is no countdown).
    static func countdown(_ site: PrayerSite, at utc: Int, beforeMinutes: Int) -> PrayerCountdown? {
        guard beforeMinutes > 0, let next = nextPrayer(site, after: utc) else { return nil }
        let left = minutesUntil(now: utc, at: next.at)
        return left <= beforeMinutes ? PrayerCountdown(moment: next, minutes: left) : nil
    }

    static func due(at: Int, now: Int) -> PrayerDue {
        switch now - at {
        case ..<0: return .skip
        case 0...120: return .ring
        case 121...(30 * 60): return .quiet
        default: return .skip
        }
    }
}
