//
//  AppliteAppView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 07. 29..
//

import SwiftUI
import Sparkle

/// Optional diagnostic self-card; normal update and uninstall actions remain in the menu and Settings.
struct AppliteAppView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(SettingsNavigation.self) private var settingsNavigation
    /// The app-wide Sparkle updater, injected from `AppliteApp` (see ``UpdaterEnvironmentKey``).
    @Environment(\.updater) private var updater

    var body: some View {
        HStack {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
                .padding(.leading, 5)
            
            // Name and description
            VStack(alignment: .leading) {
                Text("Applite", comment: "Applite app card title")
                    .font(.system(size: 16, weight: .bold))
                
                Text("This app", comment: "Applite app card description")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let updater {
                Button("Check for Updates", action: updater.checkForUpdates)
                    .cardActionPill()
                    .disabled(!updater.canCheckForUpdates)
            }

            Button {
                settingsNavigation.showUninstall { openSettings() }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Uninstall Applite")
        }
        .frame(width: AppView.dimensions.width, height: AppView.dimensions.height)
    }
}

#Preview {
    AppliteAppView()
        .environment(SettingsNavigation())
        .environment(
            \.updater,
            UpdaterViewModel(
                updater: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
            )
        )
}
