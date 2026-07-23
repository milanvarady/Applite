//
//  OpenAndManageView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

/// Button used in the Download section, launches, uninstalls or reinstalls the app
struct OpenAndManageView: View {
    var cask: CaskViewModel
    let deleteButton: Bool

    @State private var showAppNotFoundAlert = false

    var body: some View {
        // Lauch app
        AsyncButton("Open") {
            // Handle the failure here rather than through ButtonKit's `.onButtonStateError`.
            // That handler re-fires on every re-render while the button stays in its sticky
            // `.errored` state, so dismissing the alert (which re-renders this view) would
            // immediately re-present it in an endless loop.
            do {
                try await cask.launchApp()
            } catch {
                showAppNotFoundAlert = true
            }
        }
        .font(.system(size: 14))
        .buttonStyle(.bordered)
        .clipShape(Capsule())
        .asyncButtonStyle(.none)
        .alert("Applite couldn't open \(cask.name)", isPresented: $showAppNotFoundAlert) {
        } message: {
            Text(
                "Applite couldn't find \(cask.name) on your Mac. It may be installed under a different name — try opening it from Spotlight (⌘ Space) or your Applications folder.",
                comment: "Shown when Applite can't locate an installed app's bundle to launch it"
            )
        }

        if deleteButton {
            UninstallButton(cask: cask)
        }
    }
}
