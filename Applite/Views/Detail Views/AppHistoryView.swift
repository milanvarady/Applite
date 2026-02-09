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

    private var notInstalledCasks: [Cask] {
        iCloudSyncManager.previouslyInstalledCaskIds.compactMap { id in
            guard let cask = caskManager.casks[id], !cask.isInstalled else { return nil }
            return cask
        }
        .sorted()
    }

    var body: some View {
        VStack {
            if notInstalledCasks.isEmpty {
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
}
