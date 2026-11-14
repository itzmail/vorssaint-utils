// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island in the minutes before a prayer: the moon left of the
/// camera and, on the right, the minutes left. Both open Controls. The wings
/// are as wide as the wider side needs.
struct NotchPrayerStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var prayer = PrayerService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        // The countdown ends before the strip has left.
        NotchStripHold(prayer.countdown, shows: prayer.countdown != nil) { countdown in
            if let countdown { strip(countdown) }
        }
    }

    private func strip(_ countdown: PrayerCountdown) -> some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let text = NotchPrayerSupport.compactText(minutes: countdown.minutes,
                                                  locale: Locale(identifier: l10n.language.rawValue))
        return Button { service.openActivity(NotchCompactActivity.prayer.module) } label: {
            HStack(spacing: 0) {
                Group {
                    if wing >= 28 {
                        Image(systemName: NotchPrayerSupport.symbol)
                            .font(.system(size: iconSize, weight: .medium))
                    }
                }
                .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2))
                .frame(width: wing, height: height, alignment: .leading)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                Group {
                    if wing >= 42 {
                        Text(text)
                            .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.65)
                            // A reading that gains or loses a character, like 10m
                            // becoming 9m, resizes the wings; the service measures the same.
                            .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                                DispatchQueue.main.async { service.refreshPresentation() }
                            }
                    }
                }
                // Digits carry no descenders, so their ink is about the cap height.
                .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                .frame(width: wing, height: height, alignment: .trailing)
            }
            .foregroundStyle(.mint)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FeatureStrings.prayer(l10n.language).title)
        .accessibilityValue(Self.spoken(countdown, language: l10n.language))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityIdentifier("notch.prayer")
    }

    /// "Ashar in 8 min", read aloud.
    static func spoken(_ countdown: PrayerCountdown, language: AppLanguage) -> String {
        FeatureStrings.prayer(language).spokenText(prayer: countdown.moment.prayer.name, minutes: countdown.minutes)
    }
}
