//
//  ContentView+DetailView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

extension ContentView {
    @ViewBuilder
    var detailView: some View {
        switch selection {
        case .home:
            if !brokenInstall {
                HomeView(
                    navigationSelection: $selection,
                    searchText: $searchInput,
                    showSearchResults: $showSearchResults,
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

    private var brokenInstallView: some View {
        VStack(alignment: .center) {
            Text(DependencyManager.brokenPathOrIstallMessage)

            AsyncButton {
                await loadCasks()
            } label: {
                Label("Retry load", systemImage: "arrow.clockwise.circle")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 600)
    }
}
