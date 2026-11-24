// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The closed island while Mole scans or cleans: its box left of the camera
/// and, on the right, the size found so far. A click opens Mole's page, which
/// names the section being scanned. The wings are as wide as the wider side.
struct NotchMoleStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var mole = MoleService.shared

    var body: some View {
        NotchStripHold(NotchMoleSupport.reading(mole.progress), shows: mole.busy != nil) { strip(reading: $0) }
    }

    private func strip(reading: String) -> some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = NotchTimerSupport.stripIconSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        return Button { NotchMoleStrip.openPage() } label: {
            HStack(spacing: 0) {
                Group {
                    if wing >= 28 {
                        Image(systemName: NotchMoleSupport.symbol)
                            .font(.system(size: iconSize, weight: .medium))
                    }
                }
                .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2))
                .frame(width: wing, height: height, alignment: .leading)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                Group {
                    if wing >= 42 {
                        Text(reading)
                            .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.65)
                            // A reading that gains a character, like 9.9M
                            // becoming 10M, resizes the wings; the service
                            // measures the same reading.
                            .onChange(of: NotchAgentSupport.readingShape(reading)) { _, _ in
                                DispatchQueue.main.async { service.refreshPresentation() }
                            }
                    }
                }
                .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
                .frame(width: wing, height: height, alignment: .trailing)
            }
            .foregroundStyle(.teal)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mole")
        .accessibilityValue(reading)
        .accessibilityIdentifier("notch.mole")
    }

    /// Mole's own page in Settings: the island has no page for it.
    static func openPage() {
        SettingsRouter.shared.page = .mole
        appDelegate()?.openSettingsWindow()
    }
}
