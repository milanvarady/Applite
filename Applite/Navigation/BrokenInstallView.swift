//
//  BrokenInstallView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

/// Shown in place of the detail pane when the selected brew path is invalid
/// (`caskManager.hasBrokenInstall`). Offers a retry that re-runs the load/recovery.
struct BrokenInstallView: View {
    @Environment(CaskManager.self) var caskManager

    var body: some View {
        VStack(alignment: .center) {
            Text(BrewPaths.brokenPathOrInstallMessage)

            AsyncButton {
                await caskManager.loadData()
            } label: {
                Label("Retry load", systemImage: "arrow.clockwise.circle")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 600)
    }
}
