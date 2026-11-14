// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Prayer page of the open island. On the left, the next prayer and the
/// time to it in hours, minutes and seconds, with its time and the place.
/// On the right, today on one arc: the five prayers as dots from Subuh to
/// Isya, the sun (Terbit to Maghrib) or the moon where the day stands now,
/// the part of the day gone brighter than the part to come, and each
/// prayer's name and time under its dot. Above the arc: Imsak and Terbit.
///
/// The countdown ticks once a second, and only while the page is on screen.
struct NotchPrayerView: View {
    @ObservedObject private var prayer = PrayerService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    private var text: PrayerStrings { FeatureStrings.prayer(l10n.language) }

    private static let tint = Color.mint
    private static let sun = Color.orange
    private static let moon = Color(red: 0.73, green: 0.68, blue: 0.97)

    var body: some View {
        Group {
            if prayer.place == nil {
                NotchEmptyView(symbol: NotchPrayerSupport.symbol, message: text.place)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    page(now: Int(timeline.date.timeIntervalSince1970))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchBand(trailing: {
            if prayer.adzanPlaying {
                NotchIconButton(symbol: "speaker.slash", title: text.stop) { prayer.stopAdzan() }
            }
            if !preview {
                NotchIconButton(symbol: "gearshape", title: l10n.s.menuSettings) {
                    NotchService.shared.perform {
                        SettingsRouter.shared.request(AppFeature.prayer.settingsDestination)
                        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
                    }
                }
            }
        })
    }

    @ViewBuilder private func page(now: Int) -> some View {
        if let today = prayer.today(now: Date(timeIntervalSince1970: TimeInterval(now))) {
            let next = PrayerEngine.nextPrayer(today.site, after: now)
            HStack(alignment: .top, spacing: 12) {
                summary(next: next, site: today.site, now: now)
                    .frame(width: 150, alignment: .leading)
                day(today.times, site: today.site, next: next, now: now)
            }
        }
    }

    // MARK: The next prayer

    private func summary(next: PrayerMoment?, site: PrayerSite, now: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let next {
                Text(next.prayer.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.tint)
                Text(NotchPrayerSupport.countdownText(seconds: next.at - now))
                    .font(.system(size: 26, weight: .medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                Text(site.hhmm(next.at))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
            Text(prayer.place?.label ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Today on its arc

    private func day(_ times: PrayerDayTimes, site: PrayerSite, next: PrayerMoment?, now: Int) -> some View {
        let at = Prayer.allCases.map(times.prayer)
        let midnight = site.localDay(now) * 86_400 - site.offset * 60
        let here = NotchPrayerSupport.dayPosition(now: now, midnight: midnight, at: at)
        let nextIndex = next.flatMap { Prayer.allCases.firstIndex(of: $0.prayer) }
        let isDay = (times.terbit..<times.maghrib).contains(now)
        return VStack(spacing: 0) {
            Text("Imsak \(site.hhmm(times.imsak)) · Terbit \(site.hhmm(times.terbit))")
                .font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Canvas { context, size in
                Self.drawArc(&context, size: size, here: here, nextIndex: nextIndex, at: at, now: now, isDay: isDay)
            }
            .frame(height: 46)
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(Array(Prayer.allCases.enumerated()), id: \.offset) { index, item in
                    let isNext = nextIndex == index
                    // The next prayer may be tomorrow's Subuh, after Isya: its time then.
                    let time = isNext ? (next?.at ?? at[index]) : at[index]
                    let past = !isNext && time <= now
                    VStack(spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 10, weight: isNext ? .semibold : .regular))
                            .foregroundStyle(isNext ? Self.tint : .white.opacity(past ? 0.4 : 0.6))
                        Text(site.hhmm(time))
                            .font(.system(size: 11, weight: isNext ? .semibold : .regular)).monospacedDigit()
                            .foregroundStyle(.white.opacity(past ? 0.4 : 1))
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static func drawArc(_ context: inout GraphicsContext, size: CGSize, here: Double, nextIndex: Int?,
                                at: [Int], now: Int, isDay: Bool) {
        let endY = size.height - 8, topY: CGFloat = 8
        func point(_ position: Double) -> CGPoint {
            CGPoint(x: position * size.width, y: endY - (endY - topY) * sin(.pi * position))
        }
        func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        // The dotted line, kept clear of the prayers' dots and of the sun or moon.
        let count = max(2, Int((size.width / 6).rounded()))
        for index in 0...count {
            let position = Double(index) / Double(count)
            func near(_ other: Double, _ distance: CGFloat) -> Bool { abs(other - position) * size.width < distance }
            if NotchPrayerSupport.slots.contains(where: { near($0, 11) }) || near(here, 12) { continue }
            context.fill(circle(point(position), 1.15), with: .color(.white.opacity(position <= here ? 0.42 : 0.16)))
        }
        for (index, slot) in NotchPrayerSupport.slots.enumerated() where index != nextIndex {
            context.fill(circle(point(slot), 3.5), with: .color(.white.opacity(at[index] <= now ? 0.3 : 0.62)))
        }
        // Where the day stands: the sun from Terbit to Maghrib, else the moon.
        let mark = point(here)
        let color = isDay ? sun : moon
        context.fill(circle(mark, 8), with: .color(color.opacity(0.22)))
        context.fill(circle(mark, isDay ? 5 : 4), with: .color(color))
        // The next prayer's ring goes over the sun, which arrives in it.
        if let nextIndex {
            let center = point(NotchPrayerSupport.slots[nextIndex])
            context.stroke(circle(center, 9.5), with: .color(tint), lineWidth: 1.5)
            if abs(center.x - mark.x) > 9.5 { context.fill(circle(center, 3), with: .color(tint)) }
        }
    }
}
