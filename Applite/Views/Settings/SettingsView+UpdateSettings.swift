//
//  SettingsView+UpdateSettings.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import Sparkle

extension SettingsView {
    struct UpdateSettingsView: View {
        private let updater: SPUUpdater

        @State private var automaticallyChecksForUpdates: Bool
        @State private var automaticallyDownloadsUpdates: Bool

        init(updater: SPUUpdater) {
            self.updater = updater
            self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        }

        var body: some View {
            VStack {
                CheckForUpdatesView(updater: updater) {
                    Label("Check for Updates...", systemImage: "arrow.uturn.down")
                }

                Text("Current app version: \(Bundle.main.version) (\(Bundle.main.buildNumber))", comment: "Update settings current app version text (version, build number)")
                    .font(.system(.body, weight: .light))
                    .foregroundColor(.secondary)

                Spacer()
                    .frame(height: 20)

                Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }

                Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                    .disabled(!automaticallyChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { newValue in
                        updater.automaticallyDownloadsUpdates = newValue
                    }
            }
            .padding()
        }
    }
}
