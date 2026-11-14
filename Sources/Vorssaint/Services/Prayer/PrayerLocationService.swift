// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreLocation
import Foundation

/// Where the Mac is, for the prayer times: macOS's Location Services, asked
/// on the main thread. macOS decides how (Wi-Fi, mostly) and whether Vorssaint
/// may ask: the first time it asks the person itself, and System Settings >
/// Privacy & Security > Location Services changes the answer later.
///
/// The point only picks the nearest listed place; it is never stored or sent
/// anywhere. Nothing runs between asks: the manager is let go as soon as the
/// answer is in, and an ask that gets none ends after `timeout`.
final class PrayerLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = PrayerLocationService()

    /// The longest one ask may take, macOS's question to the person included.
    static let timeout: TimeInterval = 60
    /// A kab/kota is all the prayer times need, and a coarse fix comes fastest (metres).
    private static let accuracy: CLLocationAccuracy = 3000

    private var manager: CLLocationManager?
    private var completion: ((PrayerLocated) -> Void)?
    private var askedPerson = false
    private var requestedFix = false
    /// Which ask this is: a timeout left from an earlier one does nothing.
    private var generation = 0

    private override init() { super.init() }

    var isAsking: Bool { manager != nil }

    /// Ask once; `completion` runs once, on the main thread.
    func locate(_ completion: @escaping (PrayerLocated) -> Void) {
        guard !isAsking else { return }
        generation += 1
        let ask = generation
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = Self.accuracy
        self.manager = manager
        self.completion = completion
        askedPerson = false
        requestedFix = false
        advance()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            guard let self, self.generation == ask else { return }
            self.finish(.unknown)
        }
    }

    /// Let go of an ask in progress, as when the feature is switched off.
    func cancel() {
        generation += 1
        release()
    }

    private func advance() {
        guard let manager else { return }
        switch PrayerLocationSupport.step(status: manager.authorizationStatus, askedPerson: askedPerson,
                                          requestedFix: requestedFix) {
        case .askPermission:
            askedPerson = true
            manager.requestWhenInUseAuthorization()
        case .denied:
            finish(.denied)
        case .requestFix:
            requestedFix = true
            manager.requestLocation()
        case .wait:
            break
        }
    }

    private func finish(_ result: PrayerLocated) {
        guard let completion else { return }
        self.completion = nil
        release()
        completion(result)
    }

    private func release() {
        manager?.delegate = nil
        manager?.stopUpdatingLocation()
        manager = nil
        completion = nil
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        advance()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        finish(PrayerLocationSupport.outcome(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(PrayerLocationSupport.outcome(error: error))
    }
}
