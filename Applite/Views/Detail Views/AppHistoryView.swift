//
//  AppHistoryView.swift
//  Applite
//
//  Created on 2026.02.09.
//

import SwiftUI

/// Shows previously installed apps that are not currently installed, for easy reinstallation
struct AppHistoryView: View {
    @EnvironmentObject var caskManager: CaskManager
    @EnvironmentObject var iCloudSyncManager: ICloudSyncManager
    @AppStorage(Preferences.iCloudSyncEnabled.rawValue) var iCloudSyncEnabled: Bool = false

    @Environment(\.openURL) var openURL

    private var notInstalledCasks: [Cask] {
        iCloudSyncManager.previouslyInstalledCaskIds.compactMap { id in
            guard let cask = caskManager.casks[id], !cask.isInstalled else { return nil }
            return cask
        }
        .sorted()
    }

    var body: some View {
        VStack {
            if !iCloudSyncEnabled {
                disabledView
            } else if notInstalledCasks.isEmpty {
                Text("All previously installed apps are currently installed.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320))], spacing: 20) {
                        ForEach(notInstalledCasks) { cask in
                            AppView(cask: cask, role: .installAndManage)
                                .contextMenu {
                                    Button("Remove from History") {
                                        iCloudSyncManager.removeCask(cask.id)
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("App History")
    }

    private var disabledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("App History")
                .font(.title2)
                .bold()

            Text("Keep track of apps you've installed across all your Macs. Enable iCloud sync in Settings to automatically remember your apps for easy reinstallation.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
