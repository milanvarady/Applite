//
//  DownloadButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

/// Button used in the Download section, downloads the app
struct DownloadButton: View {
    var cask: CaskViewModel

    @Environment(CaskManager.self) var caskManager

    // Alerts
    @State var showingBrewError = false
    @State var showCaveatsAndWarnings = false

    @State var buttonFill = false

    var body: some View {
        /// Download button
        Button {
            if cask.warning != nil {
                // Show download confirmation
                showCaveatsAndWarnings = true
                return
            }

            caskManager.install(cask)
        } label: {
            let isDisabled = cask.warning?.isDisabled ?? false

            Image(systemName: isDisabled ? "xmark.circle" : "arrow.down.to.line.circle\(buttonFill ? ".fill" : "")")
                .foregroundStyle(isDisabled ? Color.red : Color.primary)
                .font(.system(size: 22))
        }
        .disabled(cask.warning?.isDisabled ?? false)
        .padding(.trailing, -8)
        .onHover { isHovering in
            // Hover effect
            withAnimation(.snappy) {
                buttonFill = isHovering
            }
        }
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
        .alert("Broken Brew Path", isPresented: $showingBrewError) {} message: {
            Text(AnnexBrewManager.brokenPathOrInstallMessage)
        }
    }
}
