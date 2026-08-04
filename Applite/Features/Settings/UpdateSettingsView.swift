//
//  UpdateSettingsView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct UpdateSettingsView: View {
    /// The app-wide updater bridge. Bound directly — the toggles used to be `@State` copies taken in
    /// `init`, i.e. a snapshot that never heard about a change made anywhere else (P3-19).
    @Bindable var updater: UpdaterViewModel

    var body: some View {
        Form {
            Section {
                Button(action: updater.checkForUpdates) {
                    Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!updater.canCheckForUpdates)

                LabeledContent("Current app version") {
                    Text("\(Bundle.main.version) (\(Bundle.main.buildNumber))", comment: "Update settings current app version text (version, build number)")
                }
            }

            Section {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)

                // Sparkle's own gate: it folds in the host's `SUAllowsAutomaticUpdates` Info.plist
                // key as well as the checks-for-updates setting.
                Toggle("Automatically download updates", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.allowsAutomaticUpdates)
            }
        }
        .formStyle(.grouped)
    }
}
