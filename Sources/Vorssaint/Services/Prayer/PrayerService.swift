// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Watches the clock for the prayer times of the chosen place and says so:
/// a sound for each prayer and, in the island, a notice and a countdown. The
/// times come from `PrayerEngine` on this Mac; nothing is downloaded. Main
/// thread only.
///
/// The place is the one picked in Settings, or the nearest listed place to the
/// Mac while it follows its location. Only the chosen place is kept, never the
/// location itself.
final class PrayerService: ObservableObject {
    static let shared = PrayerService()

    /// What the last ask for the Mac's location came to, as Settings tells it.
    enum LocationStatus: Equatable {
        case idle, asking, found
        /// Location Services is off, or not allowed for Vorssaint.
        case denied
        /// macOS could not tell where the Mac is.
        case unknown
        /// The Mac is farther than 250 km from every listed place.
        case unsupported
    }

    @Published private(set) var place: PrayerPlace?
    @Published private(set) var locationStatus = LocationStatus.idle
    /// The next prayer, for Settings and the island.
    @Published private(set) var next: PrayerMoment?
    /// The minutes left before the next prayer, while the countdown shows.
    @Published private(set) var countdown: PrayerCountdown?
    @Published private(set) var adzanPlaying = false

    private let player = PrayerSoundPlayer()
    private var list: PrayerPlaceList?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var handledUntil: Int?
    private var locatedAt: Int?
    private var running = false

    private static let tick: TimeInterval = 5
    /// The notice stays while the adzan plays: the recording is a little under three minutes.
    private static let adzanNotice: TimeInterval = 200

    private init() {
        player.onFinish = { [weak self] in self?.adzanEnded() }
    }

    /// The preferences changed, or the app came up.
    func syncWithPreferences() {
        guard PrayerSupport.isEnabled() else { stop(); return }
        if list == nil { list = Self.bundledPlaces() }
        resolvePlace()
        guard !running else { refresh(); return }
        running = true
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.look() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.look() }
        look()
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate(); timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        PrayerLocationService.shared.cancel()
        stopAdzan()
        handledUntil = nil
        locatedAt = nil
        locationStatus = .idle
        next = nil
        countdown = nil
    }

    // MARK: Choosing the place

    /// A place picked by hand: the Mac stops following its location.
    func choosePlace(_ id: String) {
        guard list?.find(id) != nil else { return }
        UserDefaults.standard.set(false, forKey: DefaultsKey.prayerFollowLocation)
        UserDefaults.standard.set(id, forKey: DefaultsKey.prayerPlace)
        resolvePlace()
        refresh()
    }

    func setFollowsLocation(_ follows: Bool) {
        UserDefaults.standard.set(follows, forKey: DefaultsKey.prayerFollowLocation)
        if follows { locatedAt = nil; look() }
    }

    /// Ask macOS where the Mac is now (Settings' button).
    func locateNow() {
        locatedAt = nil
        locate()
    }

    var places: [PrayerPlace] { list?.places ?? [] }

    func search(_ query: String, limit: Int = 8) -> [PrayerPlace] { list?.search(query, limit: limit) ?? [] }

    /// The saved place, or while there is none, the one the Mac's time zone suggests.
    private func resolvePlace() {
        let saved = PrayerSupport.placeID(in: .standard).flatMap { list?.find($0) }
        let suggested = PrayerPlaceList.suggestedPlaceID(
            utcOffsetMinutes: TimeZone.current.secondsFromGMT() / 60).flatMap { list?.find($0) }
        let resolved = saved ?? suggested
        if resolved != place { place = resolved }
    }

    private func locate() {
        guard locationStatus != .asking else { return }
        locationStatus = .asking
        locatedAt = Self.now()
        PrayerLocationService.shared.locate { [weak self] found in self?.located(found) }
    }

    /// The nearest listed place becomes the place. The point is not kept.
    private func located(_ found: PrayerLocated) {
        guard running else { return }
        switch found {
        case .denied: locationStatus = .denied
        case .unknown: locationStatus = .unknown
        case let .at(latitude, longitude):
            guard let nearest = list?.place(near: latitude, longitude: longitude) else {
                locationStatus = .unsupported
                return
            }
            locationStatus = .found
            UserDefaults.standard.set(nearest.id, forKey: DefaultsKey.prayerPlace)
            resolvePlace()
            refresh()
        }
    }

    // MARK: Watching

    private static func now() -> Int { Int(Date().timeIntervalSince1970) }

    private var site: PrayerSite? { place?.site }

    /// Each tick and each wake: the prayers that just came, and the location
    /// asked again every few hours while the Mac follows it.
    private func look() {
        guard running else { return }
        let now = Self.now()
        if PrayerSupport.needsLocation(follow: PrayerSupport.followsLocation(), locatedAt: locatedAt, now: now) {
            locate()
        }
        guard let site else { refresh(); return }
        let tick = PrayerSchedule.advance(site, handledUntil: handledUntil, now: now)
        handledUntil = tick.handledUntil
        for fire in tick.fires { announce(fire) }
        refresh(now: now)
    }

    /// What the island and Settings show about the next prayer.
    private func refresh(now: Int = PrayerService.now()) {
        guard let site else {
            if next != nil { next = nil }
            if countdown != nil { countdown = nil }
            return
        }
        let following = PrayerEngine.nextPrayer(site, after: now)
        if following != next { next = following }
        let counting = PrayerEngine.countdown(site, at: now, beforeMinutes: PrayerSupport.remindBeforeMinutes())
        if counting != countdown { countdown = counting }
    }

    // MARK: A prayer's time

    /// A prayer's time came: the chosen sound plays and the island says so.
    /// Quiet when it is late (after a sleep) or a full-screen app hides the island.
    private func announce(_ fire: PrayerFire) {
        deliver(fire.moment, ring: fire.due == .ring && !NotchService.shared.hiddenInFullscreen)
    }

    private func deliver(_ moment: PrayerMoment, ring: Bool) {
        guard let site else { return }
        play(PrayerSupport.playback(moment.prayer, sound: PrayerSupport.sound(), ring: ring))
        NotchService.shared.show(NotchNotice(
            event: .prayer, title: moment.prayer.name,
            detail: PrayerSupport.detail(moment, site: site, placeLabel: place?.label ?? ""),
            symbol: adzanPlaying ? "speaker.wave.2.fill" : "moon.stars.fill",
            lasts: adzanPlaying ? Self.adzanNotice : nil))
    }

    private func play(_ playback: PrayerPlayback) {
        switch playback {
        case .adzan:
            pauseMusic()
            if player.playAdzan() { adzanPlaying = true } else { player.playTone() }
        case .tone:
            player.playTone()
        case .silent:
            break
        }
    }

    /// Music that plays pauses when the adzan starts, and stays paused.
    private func pauseMusic() {
        guard PrayerSupport.pausesMusic(), NotchMusicService.shared.playback?.isPlaying == true else { return }
        NotchMusicService.shared.send(.toggle)
    }

    func stopAdzan() {
        player.stop()
        if adzanPlaying { adzanPlaying = false }
    }

    private func adzanEnded() {
        adzanPlaying = false
        NotchService.shared.endPrayerNotice()
    }

    /// Settings' test button: what an ordinary prayer's time does, sound and notice.
    func test() {
        guard let site else { return }
        let now = Self.now()
        deliver(PrayerMoment(prayer: .ashar, at: now, end: now, day: site.localDay(now)), ring: true)
    }

    // MARK: Files

    private static func bundledPlaces() -> PrayerPlaceList? {
        guard let url = Bundle.main.url(forResource: "places", withExtension: "json", subdirectory: "Prayer"),
              let data = try? Data(contentsOf: url) else { return nil }
        return PrayerPlaceList.parse(data)
    }
}
