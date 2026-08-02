//
//  DownloadButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

/// Install pill shown on app cards when the app isn't installed yet.
struct DownloadButton: View {
    var cask: CaskViewModel

    @Environment(CaskManager.self) var caskManager

    // Alerts
    @State var showCaveatsAndWarnings = false

    var body: some View {
        /// Install button
        Button {
            if cask.warning != nil {
                // Show download confirmation
                showCaveatsAndWarnings = true
                return
            }

            caskManager.install(cask)
        } label: {
            Label("Install", systemImage: "arrow.down")
        }
        .cardActionPill()
        .disabled(cask.warning?.isDisabled ?? false)
        .alert(cask.warning?.title ?? "", isPresented: $showCaveatsAndWarnings) {
            Button("Download Anyway") {
                caskManager.install(cask)
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            if let warning = cask.warning {
                switch warning {
                case .hasCaveat(let caveat):
                    Text(caveat)
                case .deprecated(let date, let reason):
                    Text("**This app is deprecated**\n**Reason:** \(reason)\n**Date:** \(date)")
                case .disabled(let date, let reason):
                    Text("**This app is disabled**\n**Reason:** \(reason)\n**Date:** \(date)")
                }
            }
        }
    }
}
