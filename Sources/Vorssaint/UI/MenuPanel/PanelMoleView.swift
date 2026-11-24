// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Mole inside the menu bar panel (and the island's copy of it): the same
/// commands and live progress as the Settings page, in the panel's width.
struct PanelMoleView: View {
    @ObservedObject private var l10n = L10n.shared
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Mole", systemImage: AppFeature.mole.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    SettingsRouter.shared.page = .mole
                    appDelegate()?.openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(l10n.s.menuSettings)
                .accessibilityLabel(l10n.s.menuSettings)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(l10n.s.uninstallerCancel)
            }
            MoleView(compact: true)
        }
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
