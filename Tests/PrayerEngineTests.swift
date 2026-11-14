// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The prayer engine against Kemenag's own published 2026 schedule and against
/// the reference engine it was ported from. The fixtures are text files, one
/// line per place and day: `id date imsak subuh terbit dzuhur ashar maghrib isya`
/// in the place's local time.
enum PrayerEngineTests {
    static func run(_ suite: TestSuite) {
        astronomyContracts(suite)
        calendarContracts(suite)
        placeListContracts(suite)
        searchContracts(suite)
        kemenagPublishedSchedule(suite)
        referenceEngine(suite)
        papuaAnglesContract(suite)
        semarangRamadanSchedule(suite)
        orderContracts(suite)
        currentAndNextContracts(suite)
        ummAlQuraContracts(suite)
        dueAndCountdownContracts(suite)
    }

    // MARK: Fixtures

    private static func fixture(_ name: String) -> String {
        guard let packed = try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/prayer/\(name).txt.lzfse")),
              let data = try? (packed as NSData).decompressed(using: .lzfse) as Data,
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private static let list: PrayerPlaceList = {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "Resources/Prayer/places.json")),
              let list = PrayerPlaceList.parse(data) else { return PrayerPlaceList(places: []) }
        return list
    }()

    private static func site(_ id: String) -> PrayerSite {
        guard let site = list.find(id)?.site else { fatalError("missing place \(id)") }
        return site
    }

    /// "HH:MM" as minutes after midnight.
    private static func minuteOfDay(_ text: Substring) -> Int {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }

    private static func day(_ text: String) -> Int {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return PrayerCalendar.days(year: parts[0], month: parts[1], day: parts[2])
    }

    private struct Row {
        let id: String
        let day: Int
        let minutes: [Int]
    }

    private static func rows(_ text: String) -> [Row] {
        text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: " ")
            guard fields.count == 9 else { return nil }
            return Row(id: String(fields[0]), day: day(String(fields[1])), minutes: fields[2...].map(minuteOfDay))
        }
    }

    private static func computed(_ site: PrayerSite, day: Int) -> [Int] {
        guard let times = PrayerEngine.dayTimes(site, day: day) else { return [] }
        return PrayerTime.allCases.map { site.localMinutes(times.get($0), day: day) }
    }

    /// UTC seconds of a wall-clock time at a site.
    private static func at(_ site: PrayerSite, _ date: String, _ hhmm: String) -> Int {
        day(date) * 86_400 + minuteOfDay(Substring(hhmm)) * 60 - site.offsetMinutes(at: 0) * 60
    }

    // MARK: Astronomy

    private static func astronomyContracts(_ suite: TestSuite) {
        // Meeus example 7.a: 1957 October 4.81 is JD 2436116.31.
        suite.expectClose(PrayerAstronomy.julianDay(year: 1957, month: 10, day: 4) + 0.81, 2436116.31,
                          "the Julian day follows Meeus 7.a", tol: 1e-9)
        suite.expect(PrayerAstronomy.julianDay(year: 2000, month: 1, day: 1) == 2451544.5,
                     "the Julian day of 2000-01-01 is 2451544.5")
        // Meeus example 25.a: 1992 October 13.0 TD.
        let sun = PrayerAstronomy.SolarCoordinates(julianDay: 2448908.5)
        suite.expectClose(sun.declination, -7.78507, "the sun's declination follows Meeus 25.a", tol: 0.0001)
        suite.expectClose(sun.rightAscension, 198.38083, "the sun's right ascension follows Meeus 25.a", tol: 0.0001)
        // JavaScript's Math.round sends halves toward +infinity.
        suite.expect(PrayerAstronomy.jsRound(2.5) == 3 && PrayerAstronomy.jsRound(-2.5) == -2
                        && PrayerAstronomy.jsRound(-2.6) == -3,
                     "rounding halves goes up, as in JavaScript")
        suite.expect(PrayerAstronomy.quadrantShift(540) == -180 && PrayerAstronomy.quadrantShift(-540) == -180
                        && PrayerAstronomy.quadrantShift(190) == -170,
                     "angles shift into -180...180 as Adhan does")
        // -2.8 h on 2026-10-24 is 21:12:00 UTC the day before: seconds are cut, not rounded.
        let day0 = PrayerCalendar.days(year: 2026, month: 10, day: 24) * 86_400_000
        let moment = PrayerAstronomy.utcMilliseconds(day0: day0, hours: -2.8)
        suite.expect(moment.map { ($0 - day0) / 1000 } == -2 * 3600 - 48 * 60,
                     "a moment keeps whole seconds, truncated")
        suite.expect(PrayerAstronomy.utcMilliseconds(day0: day0, hours: .nan) == nil,
                     "a sun that never reaches the altitude has no moment")
        suite.expect(PrayerAstronomy.addSeconds(1000, -0.0015) == 998, "fractional seconds are cut toward zero")
    }

    // MARK: Calendar and clock

    private static func calendarContracts(_ suite: TestSuite) {
        suite.expect(PrayerCalendar.days(year: 1970, month: 1, day: 1) == 0
                        && PrayerCalendar.days(year: 2026, month: 10, day: 24) == 20_750,
                     "days count from 1970-01-01")
        for date in ["1970-01-01", "2000-02-29", "2026-12-31", "2027-03-01", "1969-12-31"] {
            let n = day(date)
            let back = PrayerCalendar.civil(days: n)
            suite.expect(String(format: "%04d-%02d-%02d", back.year, back.month, back.day) == date,
                         "a date survives the round trip: \(date)")
        }
        let jakarta = site("jakarta")
        let midnight = at(jakarta, "2026-10-24", "00:05")
        suite.expect(jakarta.hhmm(midnight) == "00:05" && jakarta.localDay(midnight) == day("2026-10-24"),
                     "a place reads its own clock and date")
        suite.expect(jakarta.localDay(midnight - 600) == day("2026-10-23"),
                     "ten minutes earlier is the day before at the place")
        suite.expect(PrayerClock.offsetMinutes(zone: "Asia/Jayapura") == 540
                        && PrayerClock.offsetMinutes(zone: "Asia/Riyadh") == 180
                        && PrayerClock.offsetMinutes(zone: "Europe/London") == nil,
                     "only the zones of the list are known")
        suite.expect(PrayerEngine.minutesUntil(now: 0, at: 0) == 0 && PrayerEngine.minutesUntil(now: 0, at: 61) == 2,
                     "a started minute counts as one")
    }

    // MARK: Place list

    private static func placeListContracts(_ suite: TestSuite) {
        suite.expect(list.places.count == 520, "every Kemenag location plus Makkah, Madinah and Jeddah: \(list.places.count)")
        var ids = Set<String>(), labels = Set<String>()
        var problems: [String] = []
        for place in list.places {
            if !ids.insert(place.id).inserted { problems.append("duplicate id \(place.id)") }
            if !labels.insert(place.label).inserted { problems.append("duplicate label \(place.label)") }
            if place.site == nil { problems.append("\(place.id): unknown zone \(place.zone)") }
            switch place.kind {
            case "kota", "kab", "pulau":
                if place.method != .kemenag { problems.append("\(place.id): method") }
                if !(-11.5...6.5).contains(place.latitude) || !(94.5...141.5).contains(place.longitude) {
                    problems.append("\(place.id) lies outside Indonesia")
                }
                if !(-3.5 ... -0.5).contains(place.horizon) { problems.append("\(place.id) horizon \(place.horizon)") }
            case "abroad":
                if place.method != .ummAlQura { problems.append("\(place.id): method") }
            default:
                problems.append("\(place.id): kind \(place.kind)")
            }
        }
        suite.expect(problems.isEmpty, "the place list is consistent: \(problems.prefix(5))")
        for id in ["jakarta", "bandung", "kab-bandung", "semarang", "kota-sofifi", "kab-intan-jaya",
                   "pulau-laut-kab-natuna", "makkah", "madinah", "jeddah"] {
            suite.expect(list.find(id) != nil, "the list has \(id)")
        }
        suite.expect(list.find("nowhere") == nil && PrayerPlaceList.parse(Data("nope".utf8)) == nil,
                     "an unknown id and a broken file give nothing")
        // Gedung Sate, in the city of Bandung.
        let bandung = list.nearest(latitude: -6.9025, longitude: 107.6188)
        suite.expect(bandung?.place.id == "bandung" && (bandung?.kilometres ?? 99) < 5, "the nearest place to Gedung Sate is Kota Bandung")
        let haram = list.nearest(latitude: 21.4225, longitude: 39.8262)
        suite.expect(haram?.place.id == "makkah" && (haram?.kilometres ?? 99) < 1, "the nearest place to Masjidil Haram is Makkah")
        suite.expect((list.nearest(latitude: 0, longitude: -160)?.kilometres ?? 0) > PrayerPlaceList.nearestLimit,
                     "mid-Pacific has nothing within reach")
        suite.expectClose(PrayerPlaceList.distance(-6.2, 106.8, -6.9, 107.6), 117, "Jakarta to Bandung is about 117 km", tol: 3)
        suite.expect(PrayerPlaceList.suggestedPlaceID(utcOffsetMinutes: 420) == "jakarta"
                        && PrayerPlaceList.suggestedPlaceID(utcOffsetMinutes: 480) == "makassar"
                        && PrayerPlaceList.suggestedPlaceID(utcOffsetMinutes: 540) == "jayapura"
                        && PrayerPlaceList.suggestedPlaceID(utcOffsetMinutes: 180) == "makkah"
                        && PrayerPlaceList.suggestedPlaceID(utcOffsetMinutes: 60) == nil,
                     "a time zone suggests a listed place")
        for id in ["jakarta", "makassar", "jayapura", "makkah"] {
            suite.expect(list.find(id) != nil, "the suggested place \(id) is listed")
        }
    }

    private static func searchContracts(_ suite: TestSuite) {
        func labels(_ query: String, _ limit: Int = 8) -> [String] { list.search(query, limit: limit).map(\.label) }
        suite.expect(labels("band") == ["Kota Banda Aceh", "Kota Bandar Lampung", "Kab. Bandung", "Kota Bandung", "Kab. Bandung Barat"],
                     "names that start with the text come first: \(labels("band"))")
        suite.expect(labels("BANDUNG barat") == ["Kab. Bandung Barat"], "case does not matter")
        suite.expect(labels("kab. bandung").first == "Kab. Bandung", "the dot of Kab. does not matter")
        suite.expect(labels("makkah") == ["Makkah"], "Makkah is found")
        suite.expect(labels("  ").isEmpty, "blank text finds nothing")
        suite.expect(list.search("a", limit: 6).count == 6, "a search stops at its limit")
    }

    // MARK: Kemenag's published schedule

    private static func kemenagPublishedSchedule(_ suite: TestSuite) {
        let published = rows(fixture("kemenag-2026"))
        var total = 0, exact = 0, worst = 0
        var perPlace: [String: (times: Int, exact: Int)] = [:]
        for row in published {
            guard let site = list.find(row.id)?.site else { suite.expect(false, "\(row.id) is not in the list"); return }
            let got = computed(site, day: row.day)
            guard got.count == 7 else { suite.expect(false, "\(row.id) has no times on \(row.day)"); return }
            for index in 0..<7 {
                let difference = abs(got[index] - row.minutes[index])
                total += 1
                perPlace[row.id, default: (0, 0)].times += 1
                if difference == 0 { exact += 1; perPlace[row.id, default: (0, 0)].exact += 1 }
                worst = max(worst, difference)
            }
        }
        let indonesian = list.places.filter { $0.kind != "abroad" }.count
        suite.expect(perPlace.count == indonesian, "every Indonesian place is replayed: \(perPlace.count) of \(indonesian)")
        suite.expect(total == 227_367, "the published schedule holds 227,367 times: \(total)")
        let rate = Double(exact) / Double(max(total, 1))
        suite.expect(rate >= 0.98, "at least 98% of Kemenag's minutes are exact: \(rate)")
        suite.expect(worst <= 1, "no time is more than a minute from Kemenag's: \(worst)")
        let lowest = perPlace.map { ($0.key, Double($0.value.exact) / Double($0.value.times)) }.min { $0.1 < $1.1 }
        suite.expect((lowest?.1 ?? 0) >= 0.95, "every place is at least 95% exact: \(String(describing: lowest))")
        print("  kemenag: \(total) times, \(String(format: "%.2f", rate * 100))% exact, largest difference \(worst) min")
    }

    private static func referenceEngine(_ suite: TestSuite) {
        let golden = rows(fixture("engine-golden"))
        suite.expect(golden.count > 18_000, "the reference engine's days are all there: \(golden.count)")
        var wrong: [String] = []
        for row in golden {
            guard let site = list.find(row.id)?.site else { wrong.append("\(row.id) missing"); continue }
            let got = computed(site, day: row.day)
            if got != row.minutes { wrong.append("\(row.id) \(PrayerCalendar.civil(days: row.day)) got \(got) want \(row.minutes)") }
        }
        suite.expect(wrong.isEmpty, "\(wrong.count) of \(golden.count) days differ from the reference engine, first: \(wrong.prefix(3))")
    }

    private static func papuaAnglesContract(_ suite: TestSuite) {
        // Kemenag's Subuh and Isya there match 21 and 19 degrees, minutes wider than the usual 20 and 18.
        let own = list.places.filter { $0.subuhAngle != PrayerEngine.kemenagSubuhAngle || $0.isyaAngle != PrayerEngine.kemenagIsyaAngle }
        suite.expect(own.map(\.id).sorted() == ["kab-intan-jaya", "kab-lanny-jaya", "kab-paniai", "kab-pegunungan-arfak", "kab-puncak", "kab-puncak-jaya"],
                     "six Papua highland regencies have their own angles: \(own.map(\.id))")
        let date = day("2026-06-01")
        for place in own {
            guard let site = place.site else { continue }
            var usual = site
            usual.subuhAngle = PrayerEngine.kemenagSubuhAngle
            usual.isyaAngle = PrayerEngine.kemenagIsyaAngle
            guard let wide = PrayerEngine.dayTimes(site, day: date), let narrow = PrayerEngine.dayTimes(usual, day: date) else {
                suite.expect(false, "\(place.id) has times"); continue
            }
            suite.expect((place.subuhAngle, place.isyaAngle) == (21, 19), "\(place.id) uses 21 and 19 degrees")
            suite.expect((240...360).contains(narrow.subuh - wide.subuh) && (240...360).contains(wide.isya - narrow.isya),
                         "\(place.id): Subuh and Isya move 4 to 6 minutes")
            suite.expect(wide.terbit == narrow.terbit && wide.dzuhur == narrow.dzuhur && wide.ashar == narrow.ashar
                            && wide.maghrib == narrow.maghrib,
                         "\(place.id): the other times stay")
        }
    }

    private static func semarangRamadanSchedule(_ suite: TestSuite) {
        // Kanwil Kemenag Jawa Tengah, Jadwal Imsakiyah Ramadan 1447 H, Kota Semarang (WIB).
        let pdf: [(String, [String])] = [
            ("2026-02-19", ["04:16", "04:26", "05:40", "11:56", "15:05", "18:04", "19:14"]),
            ("2026-03-01", ["04:18", "04:28", "05:40", "11:54", "14:56", "18:01", "19:10"]),
            ("2026-03-19", ["04:18", "04:28", "05:39", "11:50", "14:59", "17:53", "19:01"]),
        ]
        let semarang = site("semarang")
        for (date, expected) in pdf {
            let d = day(date)
            guard let times = PrayerEngine.dayTimes(semarang, day: d) else { suite.expect(false, "Semarang has times"); continue }
            suite.expect(PrayerTime.allCases.map { semarang.hhmm(times.get($0)) } == expected,
                         "Semarang on \(date) matches the Kanwil's Ramadan schedule")
        }
    }

    private static func orderContracts(_ suite: TestSuite) {
        let date = day("2026-10-24")
        var problems: [String] = []
        for place in list.places {
            guard let site = place.site, let t = PrayerEngine.dayTimes(site, day: date) else { problems.append(place.id); continue }
            if t.subuh - t.imsak != 600 { problems.append("\(place.id) imsak") }
            if !(t.subuh < t.terbit && t.terbit < t.dzuhur && t.dzuhur < t.ashar && t.ashar < t.maghrib && t.maghrib < t.isya) {
                problems.append("\(place.id) order")
            }
            if t.subuh % 60 != 0 || t.isya % 60 != 0 { problems.append("\(place.id) minute") }
        }
        suite.expect(problems.isEmpty, "every place keeps the day in order, Imsak ten minutes before Subuh: \(problems.prefix(5))")
    }

    // MARK: Moments

    private static func currentAndNextContracts(_ suite: TestSuite) {
        // Kota Jakarta, Saturday 24 Oct 2026: Dzuhur 11:40, Ashar 14:51, Maghrib 17:49.
        let jakarta = site("jakarta")
        let afternoon = at(jakarta, "2026-10-24", "14:43")
        let next = PrayerEngine.nextPrayer(jakarta, after: afternoon)
        suite.expect(next?.prayer == .ashar && next.map { jakarta.hhmm($0.at) } == "14:51"
                        && next.map { PrayerEngine.minutesUntil(now: afternoon, at: $0.at) } == 8,
                     "at 14:43 the next prayer is Ashar in 8 minutes")
        let current = PrayerEngine.currentPrayer(jakarta, at: afternoon)
        suite.expect(current?.prayer == .dzuhur && current.map { jakarta.hhmm($0.at) } == "11:40"
                        && current.map { jakarta.hhmm($0.end) } == "14:51",
                     "at 14:43 Dzuhur is current and lasts until Ashar")
        let ashar = at(jakarta, "2026-10-24", "14:51")
        suite.expect(PrayerEngine.currentPrayer(jakarta, at: ashar)?.prayer == .ashar
                        && PrayerEngine.nextPrayer(jakarta, after: ashar)?.prayer == .maghrib,
                     "at the minute itself the prayer is current and the next one is Maghrib")
        suite.expect(PrayerEngine.minutesUntil(now: ashar - 1, at: ashar) == 1, "one second before counts as one minute")

        let late = at(jakarta, "2026-10-24", "23:30")
        let subuh = PrayerEngine.nextPrayer(jakarta, after: late)
        suite.expect(subuh?.prayer == .subuh && subuh?.day == day("2026-10-25"), "after Isya the next prayer is tomorrow's Subuh")
        let isya = PrayerEngine.currentPrayer(jakarta, at: late)
        suite.expect(isya?.prayer == .isya && isya?.day == day("2026-10-24") && isya?.end == subuh?.at,
                     "Isya lasts until the next Subuh, across midnight")
        let dawn = at(jakarta, "2026-10-25", "03:00")
        suite.expect(PrayerEngine.currentPrayer(jakarta, at: dawn)?.day == day("2026-10-24")
                        && PrayerEngine.nextPrayer(jakarta, after: dawn)?.prayer == .subuh,
                     "before dawn, yesterday's Isya is still current")

        let from = at(jakarta, "2026-10-24", "00:00")
        let today = PrayerEngine.prayers(jakarta, from: from, to: from + 86_400)
        suite.expect(today.map(\.prayer) == Prayer.allCases && zip(today, today.dropFirst()).allSatisfy { $0.at < $1.at },
                     "a day lists each prayer once, in order")
        suite.expect(PrayerEngine.prayers(jakarta, from: ashar, to: ashar + 60).isEmpty
                        && PrayerEngine.prayers(jakarta, from: ashar - 60, to: ashar).count == 1
                        && PrayerEngine.prayers(jakarta, from: ashar, to: ashar).isEmpty,
                     "the range leaves out its start and keeps its end")
    }

    private static func ummAlQuraContracts(_ suite: TestSuite) {
        let makkah = site("makkah")
        func gap(_ date: String) -> Int? {
            PrayerEngine.dayTimes(makkah, day: day(date)).map { ($0.isya - $0.maghrib) / 60 }
        }
        suite.expect(gap("2026-02-17") == 90, "Isya is 90 minutes after Maghrib outside Ramadan")
        suite.expect(gap("2026-02-18") == 120 && gap("2026-03-19") == 120, "and 120 minutes through Ramadan 1447")
        suite.expect(gap("2026-03-20") == 90, "on 1 Syawal it is 90 again")
        suite.expect(PrayerEngine.isRamadanUmmAlQura(day: day("2027-02-08")) && !PrayerEngine.isRamadanUmmAlQura(day: day("2027-02-07")),
                     "Ramadan 1448 starts on 2027-02-08")
        suite.expect(PrayerEngine.dayTimes(makkah, day: day("2026-06-01")).map { $0.subuh % 60 == 0 && $0.isya % 60 == 0 } == true,
                     "Umm al-Qura times fall on whole minutes")
    }

    private static func dueAndCountdownContracts(_ suite: TestSuite) {
        suite.expect(PrayerEngine.due(at: 1000, now: 1000) == .ring && PrayerEngine.due(at: 1000, now: 1120) == .ring,
                     "a prayer rings when it is on time")
        suite.expect(PrayerEngine.due(at: 1000, now: 1121) == .quiet && PrayerEngine.due(at: 1000, now: 2800) == .quiet,
                     "after a sleep it shows without sound for half an hour")
        suite.expect(PrayerEngine.due(at: 1000, now: 2801) == .skip && PrayerEngine.due(at: 1000, now: 999) == .skip,
                     "an older or a future time is left alone")

        let jakarta = site("jakarta")
        let now = at(jakarta, "2026-10-24", "14:43")
        let countdown = PrayerEngine.countdown(jakarta, at: now, beforeMinutes: 10)
        suite.expect(countdown?.moment.prayer == .ashar && countdown?.minutes == 8, "the countdown opens ten minutes before")
        suite.expect(PrayerEngine.countdown(jakarta, at: now - 30, beforeMinutes: 10)?.minutes == 9, "and counts the started minute")
        suite.expect(PrayerEngine.countdown(jakarta, at: at(jakarta, "2026-10-24", "14:40"), beforeMinutes: 10) == nil,
                     "it waits until then")
        suite.expect(PrayerEngine.countdown(jakarta, at: now, beforeMinutes: 0) == nil, "zero minutes switches it off")
        suite.expect(PrayerEngine.countdown(jakarta, at: at(jakarta, "2026-10-24", "14:51"), beforeMinutes: 10) == nil,
                     "at the minute it has moved on to Maghrib, out of reach")
    }
}
