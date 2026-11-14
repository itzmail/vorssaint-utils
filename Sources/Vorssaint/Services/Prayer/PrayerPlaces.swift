// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One place in the list (`Resources/Prayer/places.json`): every location in
/// Kemenag RI's prayer schedule named as Kemenag writes it, plus Makkah,
/// Madinah and Jeddah. Settings keep the chosen place by its id, so an id is
/// never renamed.
struct PrayerPlace: Equatable, Decodable {
    let id: String
    /// As Kemenag writes it: "Kota Bandung", "Kab. Bandung Barat".
    let label: String
    /// "kota", "kab", "pulau" or "abroad".
    let kind: String
    /// Province, or the country for places abroad.
    let province: String
    let latitude: Double
    let longitude: Double
    /// IANA time zone; see `PrayerClock`.
    let zone: String
    /// Sun altitude for Terbit and Maghrib (Kemenag places only).
    let horizon: Double
    /// Degrees below the horizon for Subuh and Isya (Kemenag uses 21 and 19 in
    /// six Papua highland regencies).
    let subuhAngle: Double
    let isyaAngle: Double
    let method: PrayerMethod

    private enum CodingKeys: String, CodingKey {
        case id, label, kind, lat, lng, tz, h0, method
        case province = "prov"
        case subuhAngle = "subuh_angle"
        case isyaAngle = "isya_angle"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = try values.decode(String.self, forKey: .label)
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? ""
        province = try values.decodeIfPresent(String.self, forKey: .province) ?? ""
        latitude = try values.decode(Double.self, forKey: .lat)
        longitude = try values.decode(Double.self, forKey: .lng)
        zone = try values.decode(String.self, forKey: .tz)
        horizon = try values.decodeIfPresent(Double.self, forKey: .h0) ?? -1
        subuhAngle = try values.decodeIfPresent(Double.self, forKey: .subuhAngle) ?? PrayerEngine.kemenagSubuhAngle
        isyaAngle = try values.decodeIfPresent(Double.self, forKey: .isyaAngle) ?? PrayerEngine.kemenagIsyaAngle
        let key = try values.decodeIfPresent(String.self, forKey: .method) ?? PrayerMethod.kemenag.rawValue
        guard let method = PrayerMethod(rawValue: key) else {
            throw DecodingError.dataCorruptedError(forKey: .method, in: values, debugDescription: "unknown method \(key)")
        }
        self.method = method
    }

    /// What the engine needs, or nil when the time zone is not one we know.
    var site: PrayerSite? {
        guard let offset = PrayerClock.offsetMinutes(zone: zone) else { return nil }
        return PrayerSite(latitude: latitude, longitude: longitude, offset: offset, horizon: horizon,
                          subuhAngle: subuhAngle, isyaAngle: isyaAngle, method: method)
    }
}

struct PrayerPlaceList {
    let places: [PrayerPlace]

    /// Farther than this from every listed place, a location picks none: the
    /// times there would be minutes off.
    static let nearestLimit = 250.0

    private struct File: Decodable { let places: [PrayerPlace] }

    /// Nil for a file that is not a place list; one unreadable place makes the
    /// whole list unusable rather than silently shorter.
    static func parse(_ data: Data) -> PrayerPlaceList? {
        (try? JSONDecoder().decode(File.self, from: data)).map { PrayerPlaceList(places: $0.places) }
    }

    func find(_ id: String) -> PrayerPlace? { places.first { $0.id == id } }

    /// The listed place nearest to a point, and how far it is (km).
    func nearest(latitude: Double, longitude: Double) -> (place: PrayerPlace, kilometres: Double)? {
        places.map { ($0, Self.distance(latitude, longitude, $0.latitude, $0.longitude)) }
            .min { $0.1 < $1.1 }
            .map { (place: $0.0, kilometres: $0.1) }
    }

    /// Great-circle distance in km (haversine).
    static func distance(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        func radians(_ degrees: Double) -> Double { degrees * Double.pi / 180 }
        let a = pow(sin(radians(lat2 - lat1) / 2), 2)
            + cos(radians(lat1)) * cos(radians(lat2)) * pow(sin(radians(lng2 - lng1) / 2), 2)
        return 2 * 6371.0088 * asin(min(sqrt(a), 1))
    }

    /// The place a Mac's time zone suggests until one is found or picked.
    static func suggestedPlaceID(utcOffsetMinutes: Int) -> String? {
        switch utcOffsetMinutes {
        case 420: return "jakarta"
        case 480: return "makassar"
        case 540: return "jayapura"
        case 180: return "makkah"
        default: return nil
        }
    }

    // MARK: Search

    /// What was typed, as the names are searched: lowercase words, accents
    /// taken off, the dots of "Kab." and other marks read as spaces.
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        let words = plain.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar)) ? Character(scalar) : " "
        }
        return String(words).split(separator: " ").joined(separator: " ")
    }

    /// 0: the whole name; 1: a word of the name starts with the query; 2: the
    /// query is anywhere in it.
    private static func rank(_ name: String, _ query: String) -> Int? {
        if name == query { return 0 }
        if name.hasPrefix(query) || name.contains(" " + query) { return 1 }
        return name.contains(query) ? 2 : nil
    }

    /// Places whose name holds what was typed, best first: the whole name (with
    /// or without "Kab." / "Kota"), a word of it starting with it, then anywhere
    /// in it. At most `limit`.
    func search(_ query: String, limit: Int) -> [PrayerPlace] {
        let folded = Self.fold(query)
        guard !folded.isEmpty else { return [] }
        let hits: [(rank: Int, bare: String, place: PrayerPlace)] = places.compactMap { place in
            let name = Self.fold(place.label)
            // Sorted by the name without "Kab." / "Kota", so Bandung's kab and kota sit together.
            let bare = ["kab ", "kota "].first(where: name.hasPrefix).map { String(name.dropFirst($0.count)) } ?? name
            guard let rank = [Self.rank(name, folded), Self.rank(bare, folded)].compactMap({ $0 }).min() else { return nil }
            return (rank, bare, place)
        }
        let sorted = hits.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.bare != $1.bare { return $0.bare < $1.bare }
            return $0.place.label < $1.place.label
        }
        return sorted.prefix(limit).map(\.place)
    }
}
