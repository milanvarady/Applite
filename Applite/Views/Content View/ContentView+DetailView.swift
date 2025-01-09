//
//  ContentView+DetailView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension ContentView {
    @ViewBuilder
    var detailView: some View {
        switch selection {
        case .home:
            if !brokenInstall {
                DownloadView(
                    navigationSelection: $selection,
                    searchText: $searchText,
                    caskCollection: caskManager.allCasks
                )
            } else {
                brokenInstallView
            }
            
        case .updates:
            UpdateView(caskCollection: caskManager.outdatedCasks)

        case .installed:
            InstalledView(caskCollection: caskManager.installedCasks)
            
        case .activeTasks:
            ActiveTasksView()
            
        case .appMigration:
            AppMigrationView()
            
        case .appCategory(let category):
            CategoryView(category: category)

        case .tap(let tap):
            TapView(tap: tap)
            
        case .brew:
            BrewManagementView(modifyingBrew: $modifyingBrew)
        }
    }

    var brokenInstallView: some View {
        VStack(alignment: .center) {
            Text(DependencyManager.brokenPathOrIstallMessage)

            Button {
                Task {
                    await loadCasks()
                }
            } label: {
                Label("Retry load", systemImage: "arrow.clockwise.circle")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 600)
    }
}
