//
//  DetailView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

struct DetailView: View {
    @Environment(CaskManager.self) var caskManager
    @Binding var selection: SidebarItem?
    @Binding var modifyingBrew: Bool

    var body: some View {
        switch selection {
        case .home:
            DiscoverView(navigationSelection: $selection)

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

        case .none:
            EmptyView()
        }
    }
}

struct BrokenInstallView: View {
    @Environment(CaskManager.self) var caskManager

    var body: some View {
        VStack(alignment: .center) {
            Text(DependencyManager.brokenPathOrInstallMessage)

            AsyncButton {
                await caskManager.loadData()
            } label: {
                Label("Retry load", systemImage: "arrow.clockwise.circle")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 600)
    }
}
