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
                HomeView(navigationSelection: $selection)
            } else {
                brokenInstallView
            }

        case .updates:
            UpdateView(casks: caskManager.outdatedViewModels)

        case .installed:
            InstalledView(casks: caskManager.installedViewModels)

        case .activeTasks:
            ActiveTasksView()

        case .appMigration:
            AppMigrationView()

        case .appCategory(let id):
            // Look up the freshest CategoryLoadResult by id so we re-render with
            // resolved casks once stage 1 finishes (the selection enum captured the
            // placeholder version at click time).
            if let category = caskManager.categories.first(where: { $0.id == id }) {
                CategoryView(category: category)
            }

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
