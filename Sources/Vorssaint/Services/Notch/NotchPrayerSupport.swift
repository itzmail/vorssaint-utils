// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The minutes before a prayer as a live activity of the closed island: the
/// moon on the left of the camera and the time left on the right, in the
/// timer strip's shapes. It shows while the feature counts down at all.
enum NotchPrayerSupport {
    static let symbol = "moon.stars.fill"

    // MARK: The page

    /// The page's height: the next prayer beside today's arc.
    static let pageHeight: CGFloat = 128
    /// The prayers sit at the middles of five equal slots along the arc; the
    /// night before Subuh and after Isya runs out to its ends.
    static let slots: [Double] = [0.1, 0.3, 0.5, 0.7, 0.9]

    /// Where `now` sits along the day's arc, 0 (the place's midnight) to 1
    /// (the next midnight): each prayer at the middle of its slot, the time
    /// between two prayers spread evenly between their dots.
    static func dayPosition(now: Int, midnight: Int, at: [Int]) -> Double {
        let marks = [(midnight, 0.0)] + zip(at, slots).map { ($0, $1) } + [(midnight + 86_400, 1.0)]
        for (from, to) in zip(marks, marks.dropFirst()) where now < to.0 {
            let part = Double(now - from.0) / Double(max(1, to.0 - from.0))
            return from.1 + (to.1 - from.1) * min(1, max(0, part))
        }
        return 1
    }

    /// "01:24:59": hours, minutes and seconds to go.
    static func countdownText(seconds: Int) -> String {
        let left = max(0, seconds)
        return String(format: "%02d:%02d:%02d", left / 3600, left / 60 % 60, left % 60)
    }

    static func showsActivity(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && PrayerSupport.isEnabled(in: defaults)
            && PrayerSupport.remindBeforeMinutes(in: defaults) > 0
    }

    /// The timer strip's shapes, "8m" and "1h".
    static func compactText(minutes: Int, locale: Locale) -> String {
        let minutes = max(1, minutes)
        guard minutes >= 60 else { return NotchTimerSupport.compactText(TimeInterval(minutes * 60), locale: locale) }
        return NotchTimerSupport.hoursText(hours: minutes / 60, minutes: minutes % 60)
    }

    /// The wider of the two sides, the moon or the time left, drawn as the
    /// strip draws them, with the timer's clearance from the silhouette's
    /// curve and air beside the camera.
    static func stripWing(minutes: Int, locale: Locale, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let reading = (NotchAgentSupport.readingShape(compactText(minutes: minutes, locale: locale)) as NSString)
            .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: textSize, weight: .medium)])
            .width.rounded(.up)
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let mark = NotchKeepAwakeSupport.symbolWidth(symbol, size: iconSize)
            + provisional.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
        return max(reading + provisional.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0), mark)
            + NotchTimerSupport.stripCameraGap
    }
}
