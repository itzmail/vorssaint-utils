// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreLocation
import Foundation

/// What asking macOS for the Mac's location came to.
enum PrayerLocated: Equatable {
    /// Latitude and longitude, degrees.
    case at(latitude: Double, longitude: Double)
    /// Location Services is off, or not allowed for Vorssaint.
    case denied
    /// macOS could not tell where the Mac is (no Wi-Fi around, no answer).
    case unknown
}

/// The decisions of one location ask, apart from Core Location itself.
enum PrayerLocationSupport {
    enum Step: Equatable {
        /// Put macOS's question to the person.
        case askPermission
        case denied
        /// Ask for the one fix.
        case requestFix
        /// Nothing to do until macOS says more.
        case wait
    }

    /// What to do about the permission as it stands: the question while nobody
    /// has answered it, the fix once allowed. Each is done once per ask, even
    /// though macOS reports the permission again after each change.
    static func step(status: CLAuthorizationStatus, askedPerson: Bool, requestedFix: Bool) -> Step {
        switch status {
        case .notDetermined: return askedPerson ? .wait : .askPermission
        case .denied, .restricted: return .denied
        default: return requestedFix ? .wait : .requestFix
        }
    }

    static func outcome(latitude: Double, longitude: Double) -> PrayerLocated {
        PrayerPlaceList.isPoint(latitude: latitude, longitude: longitude)
            ? .at(latitude: latitude, longitude: longitude) : .unknown
    }

    static func outcome(error: Error) -> PrayerLocated {
        (error as? CLError)?.code == .denied ? .denied : .unknown
    }
}
