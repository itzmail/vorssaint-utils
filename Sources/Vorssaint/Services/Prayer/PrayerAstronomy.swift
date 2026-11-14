// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The sun's position and the moments it reaches a given altitude: a Swift
/// port of the parts of Adhan (adhan-js 4.4.6, MIT, Copyright (c) Batoul Apps)
/// that the prayer times run on, by way of Oyen Poni's Rust port (MIT). The
/// arithmetic follows the JavaScript step for step, including where it cuts to
/// whole seconds, so the minutes agree with Kemenag's after its rounding.
/// Formulas are from Jean Meeus, "Astronomical Algorithms". The licence text
/// is in THIRD-PARTY-NOTICES.txt.
///
/// Times are UTC milliseconds since 1970. `nil` means the sun never reaches
/// that altitude that day.
enum PrayerAstronomy {
    static let dayMilliseconds = 86_400_000

    // MARK: Angles

    private static func radians(_ degrees: Double) -> Double { degrees * Double.pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / Double.pi }

    private static func normalize(_ number: Double, to maximum: Double) -> Double {
        number - maximum * (number / maximum).rounded(.down)
    }

    private static func unwind(_ angle: Double) -> Double { normalize(angle, to: 360) }

    /// JavaScript's `Math.round`: halves go up, toward +infinity.
    static func jsRound(_ value: Double) -> Double {
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        return abs(rounded - value) == 0.5 ? value.rounded(.up) : rounded
    }

    static func quadrantShift(_ angle: Double) -> Double {
        (-180.0...180.0).contains(angle) ? angle : angle - 360 * jsRound(angle / 360)
    }

    // MARK: Meeus

    static func julianDay(year: Int, month: Int, day: Int) -> Double {
        let (y, m) = month > 2 ? (Double(year), Double(month)) : (Double(year) - 1, Double(month) + 12)
        let a = (y / 100).rounded(.towardZero)
        let b = (2 - a + (a / 4).rounded(.towardZero)).rounded(.towardZero)
        let i0 = (365.25 * (y + 4716)).rounded(.towardZero)
        let i1 = (30.6001 * (m + 1)).rounded(.towardZero)
        return i0 + i1 + Double(day) + b - 1524.5
    }

    private static func julianCentury(_ jd: Double) -> Double { (jd - 2451545) / 36525 }

    private static func meanSolarLongitude(_ t: Double) -> Double {
        unwind(280.4664567 + 36000.76983 * t + 0.0003032 * (t * t))
    }

    private static func meanLunarLongitude(_ t: Double) -> Double { unwind(218.3165 + 481267.8813 * t) }

    private static func ascendingLunarNode(_ t: Double) -> Double {
        unwind(125.04452 - 1934.136261 * t + 0.0020708 * (t * t) + (t * t * t) / 450000)
    }

    private static func meanSolarAnomaly(_ t: Double) -> Double {
        unwind(357.52911 + 35999.05029 * t - 0.0001537 * (t * t))
    }

    private static func equationOfTheCenter(_ t: Double, anomaly: Double) -> Double {
        let m = radians(anomaly)
        let term1 = (1.914602 - 0.004817 * t - 0.000014 * (t * t)) * sin(m)
        let term2 = (0.019993 - 0.000101 * t) * sin(2 * m)
        let term3 = 0.000289 * sin(3 * m)
        return term1 + term2 + term3
    }

    private static func apparentSolarLongitude(_ t: Double, mean: Double) -> Double {
        let longitude = mean + equationOfTheCenter(t, anomaly: meanSolarAnomaly(t))
        let omega = 125.04 - 1934.136 * t
        return unwind(longitude - 0.00569 - 0.00478 * sin(radians(omega)))
    }

    private static func meanObliquity(_ t: Double) -> Double {
        23.439291 - 0.013004167 * t - 0.0000001639 * (t * t) + 0.0000005036 * (t * t * t)
    }

    private static func apparentObliquity(_ t: Double, mean: Double) -> Double {
        mean + 0.00256 * cos(radians(125.04 - 1934.136 * t))
    }

    private static func meanSiderealTime(_ t: Double) -> Double {
        let jd = t * 36525 + 2451545
        return unwind(280.46061837 + 360.98564736629 * (jd - 2451545) + 0.000387933 * (t * t) - (t * t * t) / 38710000)
    }

    private static func nutationInLongitude(l0: Double, lp: Double, omega: Double) -> Double {
        let term1 = -17.2 / 3600 * sin(radians(omega))
        let term2 = 1.32 / 3600 * sin(2 * radians(l0))
        let term3 = 0.23 / 3600 * sin(2 * radians(lp))
        let term4 = 0.21 / 3600 * sin(2 * radians(omega))
        return term1 - term2 - term3 + term4
    }

    private static func nutationInObliquity(l0: Double, lp: Double, omega: Double) -> Double {
        let term1 = 9.2 / 3600 * cos(radians(omega))
        let term2 = 0.57 / 3600 * cos(2 * radians(l0))
        let term3 = 0.1 / 3600 * cos(2 * radians(lp))
        let term4 = 0.09 / 3600 * cos(2 * radians(omega))
        return term1 + term2 + term3 - term4
    }

    private static func altitude(latitude: Double, declination: Double, hourAngle: Double) -> Double {
        let term1 = sin(radians(latitude)) * sin(radians(declination))
        let term2 = cos(radians(latitude)) * cos(radians(declination)) * cos(radians(hourAngle))
        return degrees(asin(term1 + term2))
    }

    private static func interpolate(_ y2: Double, _ y1: Double, _ y3: Double, _ n: Double) -> Double {
        let a = y2 - y1, b = y3 - y2, c = b - a
        return y2 + n / 2 * (a + b + n * c)
    }

    private static func interpolateAngles(_ y2: Double, _ y1: Double, _ y3: Double, _ n: Double) -> Double {
        let a = unwind(y2 - y1), b = unwind(y3 - y2), c = b - a
        return y2 + n / 2 * (a + b + n * c)
    }

    /// The sun's coordinates at 0h UT of a Julian day.
    struct SolarCoordinates {
        let declination: Double
        let rightAscension: Double
        let apparentSiderealTime: Double

        init(julianDay jd: Double) {
            let t = PrayerAstronomy.julianCentury(jd)
            let l0 = PrayerAstronomy.meanSolarLongitude(t)
            let lp = PrayerAstronomy.meanLunarLongitude(t)
            let omega = PrayerAstronomy.ascendingLunarNode(t)
            let lambda = PrayerAstronomy.radians(PrayerAstronomy.apparentSolarLongitude(t, mean: l0))
            let theta0 = PrayerAstronomy.meanSiderealTime(t)
            let dPsi = PrayerAstronomy.nutationInLongitude(l0: l0, lp: lp, omega: omega)
            let dEpsilon = PrayerAstronomy.nutationInObliquity(l0: l0, lp: lp, omega: omega)
            let epsilon0 = PrayerAstronomy.meanObliquity(t)
            let epsilon = PrayerAstronomy.radians(PrayerAstronomy.apparentObliquity(t, mean: epsilon0))
            declination = PrayerAstronomy.degrees(asin(sin(epsilon) * sin(lambda)))
            rightAscension = PrayerAstronomy.unwind(PrayerAstronomy.degrees(atan2(cos(epsilon) * sin(lambda), cos(lambda))))
            apparentSiderealTime = theta0
                + dPsi * 3600 * cos(PrayerAstronomy.radians(epsilon0 + dEpsilon)) / 3600
        }
    }

    // MARK: One day's sun at one place

    /// Adhan's `SolarTime`. Moments are hours after 0h UT of the date (negative
    /// is the evening before, in UTC).
    struct SolarTime {
        let latitude: Double
        let longitude: Double
        let solar: SolarCoordinates
        let previous: SolarCoordinates
        let next: SolarCoordinates
        let approximateTransit: Double
        private(set) var transit = 0.0
        private(set) var sunrise = 0.0
        private(set) var sunset = 0.0

        init(year: Int, month: Int, day: Int, latitude: Double, longitude: Double) {
            let jd = PrayerAstronomy.julianDay(year: year, month: month, day: day)
            self.latitude = latitude
            self.longitude = longitude
            solar = SolarCoordinates(julianDay: jd)
            previous = SolarCoordinates(julianDay: jd - 1)
            next = SolarCoordinates(julianDay: jd + 1)
            approximateTransit = PrayerAstronomy.approximateTransit(
                longitude: longitude, siderealTime: solar.apparentSiderealTime, rightAscension: solar.rightAscension)
            transit = correctedTransit()
            sunrise = hourAngle(-50.0 / 60, afterTransit: false)
            sunset = hourAngle(-50.0 / 60, afterTransit: true)
        }

        private func correctedTransit() -> Double {
            let m0 = approximateTransit
            let lw = -longitude
            let theta = PrayerAstronomy.unwind(solar.apparentSiderealTime + 360.985647 * m0)
            let a = PrayerAstronomy.unwind(PrayerAstronomy.interpolateAngles(
                solar.rightAscension, previous.rightAscension, next.rightAscension, m0))
            let h = PrayerAstronomy.quadrantShift(theta - lw - a)
            let dm = h / -360
            return (m0 + dm) * 24
        }

        /// Hours (UT) when the sun's centre is at `angle` degrees (negative is
        /// below the horizon), before or after transit. NaN when it never is.
        func hourAngle(_ angle: Double, afterTransit: Bool) -> Double {
            let m0 = approximateTransit
            let lw = -longitude
            let d2 = solar.declination
            let term1 = sin(PrayerAstronomy.radians(angle)) - sin(PrayerAstronomy.radians(latitude)) * sin(PrayerAstronomy.radians(d2))
            let term2 = cos(PrayerAstronomy.radians(latitude)) * cos(PrayerAstronomy.radians(d2))
            let h0 = PrayerAstronomy.degrees(acos(term1 / term2))
            let m = afterTransit ? m0 + h0 / 360 : m0 - h0 / 360
            let theta = PrayerAstronomy.unwind(solar.apparentSiderealTime + 360.985647 * m)
            let a = PrayerAstronomy.unwind(PrayerAstronomy.interpolateAngles(
                solar.rightAscension, previous.rightAscension, next.rightAscension, m))
            let delta = PrayerAstronomy.interpolate(d2, previous.declination, next.declination, m)
            let h = theta - lw - a
            let alt = PrayerAstronomy.altitude(latitude: latitude, declination: delta, hourAngle: h)
            let term3 = alt - angle
            let term4 = 360 * cos(PrayerAstronomy.radians(delta)) * cos(PrayerAstronomy.radians(latitude))
                * sin(PrayerAstronomy.radians(h))
            return (m + term3 / term4) * 24
        }

        /// Hours (UT) when a shadow is `shadowLength` times the object plus its
        /// noon shadow (1 is Syafi'i Ashar, 2 is Hanafi).
        func afternoon(shadowLength: Double) -> Double {
            let tangent = abs(latitude - solar.declination)
            let inverse = shadowLength + tan(PrayerAstronomy.radians(tangent))
            return hourAngle(PrayerAstronomy.degrees(atan(1 / inverse)), afterTransit: true)
        }
    }

    private static func approximateTransit(longitude: Double, siderealTime: Double, rightAscension: Double) -> Double {
        let lw = -longitude
        let m0 = normalize((rightAscension + lw - siderealTime) / 360, to: 1)
        let expected = normalize((12 - longitude / 15) / 24, to: 1)
        if m0 - expected > 0.5 { return m0 - 1 }
        if expected - m0 > 0.5 { return m0 + 1 }
        return m0
    }

    /// Adhan's `TimeComponents(hours).utcDate(...)`: hours after 0h UT of the
    /// day, cut to whole seconds, as UTC milliseconds.
    static func utcMilliseconds(day0: Int, hours: Double) -> Int? {
        guard hours.isFinite else { return nil }
        let h = hours.rounded(.down)
        let m = ((hours - h) * 60).rounded(.down)
        let s = ((hours - (h + m / 60)) * 60 * 60).rounded(.down)
        return day0 + Int(h) * 3_600_000 + Int(m) * 60_000 + Int(s) * 1000
    }

    /// A JavaScript `Date` moved by fractional seconds keeps whole
    /// milliseconds, cut toward zero.
    static func addSeconds(_ milliseconds: Int, _ seconds: Double) -> Int {
        Int((Double(milliseconds) + seconds * 1000).rounded(.towardZero))
    }

    // MARK: Adhan's PrayerTimes

    /// How Adhan bounds Fajr and Isha where twilight lasts all night.
    enum HighLatitudeRule {
        case middleOfTheNight, seventhOfTheNight

        /// Adhan's `HighLatitudeRule.recommended`.
        static func recommended(latitude: Double) -> HighLatitudeRule {
            latitude > 48 ? .seventhOfTheNight : .middleOfTheNight
        }

        var portion: Double { self == .middleOfTheNight ? 1.0 / 2 : 1.0 / 7 }
    }

    /// Adhan's `CalculationParameters`, the parts the engine uses: no method
    /// adjustments and no rounding, which the caller does.
    struct Params {
        /// Degrees below the horizon.
        var fajrAngle: Double
        /// Degrees below the horizon; unused when `ishaIntervalMinutes` > 0.
        var ishaAngle: Double
        /// Isha this many minutes after sunset (Umm al-Qura); 0 is by angle.
        var ishaIntervalMinutes: Double
        /// 1 is Syafi'i, 2 is Hanafi.
        var shadowLength: Double
        var highLatitude: HighLatitudeRule
    }

    /// Adhan's `PrayerTimes` with rounding off: UTC milliseconds, whole seconds.
    struct Moments {
        let fajr: Int
        let sunrise: Int
        let dhuhr: Int
        let asr: Int
        let sunset: Int
        let isha: Int
    }

    /// Moments for one calendar date of the place (not of UTC). `nil` when the
    /// sun does not rise or set that day.
    static func moments(year: Int, month: Int, day: Int, latitude: Double, longitude: Double,
                        params p: Params) -> Moments? {
        let days = PrayerCalendar.days(year: year, month: month, day: day)
        let day0 = days * dayMilliseconds
        let sun = SolarTime(year: year, month: month, day: day, latitude: latitude, longitude: longitude)
        guard let dhuhr = utcMilliseconds(day0: day0, hours: sun.transit),
              let sunrise = utcMilliseconds(day0: day0, hours: sun.sunrise),
              let sunset = utcMilliseconds(day0: day0, hours: sun.sunset) else { return nil }
        let tomorrowDate = PrayerCalendar.civil(days: days + 1)
        let tomorrow = SolarTime(year: tomorrowDate.year, month: tomorrowDate.month, day: tomorrowDate.day,
                                 latitude: latitude, longitude: longitude)
        guard let asr = utcMilliseconds(day0: day0, hours: sun.afternoon(shadowLength: p.shadowLength)) else { return nil }
        // The night's length bounds Fajr and Isha; where tomorrow's sunrise is
        // missing, Adhan's bound is an invalid date and the angle's moment stands.
        let night = utcMilliseconds(day0: day0 + dayMilliseconds, hours: tomorrow.sunrise)
            .map { Double($0 - sunset) / 1000 }
        let portion = p.highLatitude.portion

        let safeFajr = night.map { addSeconds(sunrise, -(portion * $0)) }
        let angleFajr = utcMilliseconds(day0: day0, hours: sun.hourAngle(-p.fajrAngle, afterTransit: false))
        let fajr: Int
        switch (angleFajr, safeFajr) {
        case let (f?, s?): fajr = max(f, s)
        case let (f?, nil): fajr = f
        case let (nil, s?): fajr = s
        default: return nil
        }

        let isha: Int
        if p.ishaIntervalMinutes > 0 {
            isha = addSeconds(sunset, p.ishaIntervalMinutes * 60)
        } else {
            let safeIsha = night.map { addSeconds(sunset, portion * $0) }
            let angleIsha = utcMilliseconds(day0: day0, hours: sun.hourAngle(-p.ishaAngle, afterTransit: true))
            switch (angleIsha, safeIsha) {
            case let (i?, s?): isha = min(i, s)
            case let (i?, nil): isha = i
            case let (nil, s?): isha = s
            default: return nil
            }
        }
        return Moments(fajr: fajr, sunrise: sunrise, dhuhr: dhuhr, asr: asr, sunset: sunset, isha: isha)
    }
}

/// Days since 1970-01-01 and calendar dates (proleptic Gregorian).
enum PrayerCalendar {
    static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shifted = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shifted + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civil(days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shifted = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shifted + 2) / 5 + 1
        let month = shifted < 10 ? shifted + 3 : shifted - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}
