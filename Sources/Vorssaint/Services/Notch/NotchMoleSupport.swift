// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A running Mole scan or cleanup as a live activity of the closed island: its
/// mark on the left and, on the right, what it has found so far. It is there
/// only while Mole works, and a click opens its page for the section being
/// scanned and the rest of the detail.
enum NotchMoleSupport {
    static let symbol = "pawprint.fill"

    /// Only on an island that is on, for a Mole that is installed as a feature.
    static func showsActivity(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.mole.isAvailable(in: defaults)
    }

    /// The reading right of the camera, from the bytes found so far.
    static func reading(_ progress: MoleProgress?) -> String {
        MoleSupport.shortSize(progress?.foundBytes ?? 0)
    }

    /// The wider of the two sides, the mark or the reading, with the timer's
    /// clearance from the silhouette's curve and air beside the camera.
    static func stripWing(reading: String, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let text = (NotchAgentSupport.readingShape(reading) as NSString)
            .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: textSize, weight: .medium)])
            .width.rounded(.up)
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let mark = NotchKeepAwakeSupport.symbolWidth(symbol, size: iconSize)
            + provisional.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
        return max(text + provisional.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0), mark)
            + NotchTimerSupport.stripCameraGap
    }
}
