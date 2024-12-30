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
                DownloadView(navigationSelection: $selection, searchText: $searchTextSubmitted)
            } else {
                // Broken install
                VStack(alignment: .center) {
                    Text(DependencyManager.brokenPathOrIstallMessage)
                    
                    Button {
                        Task {
                            await loadCasks()
                        }
                    } label: {
                        Label("Retry load", systemImage: "arrow.clockwise.circle")
                    }
                    .bigButton()
                    .disabled(false)
                }
                .frame(maxWidth: 600)
            }
            
        case .updates:
            UpdateView()
            
        case .installed:
            InstalledView()
            
        case .activeTasks:
            ActiveTasksView()
            
        case .appMigration:
            AppMigrationView()
            
        case .appCategory(let categoryId):
            if let category = categories.first(where: { $0.id == categoryId }) {
                CategoryView(category: category)
            } else {
                Text("No Selection")
            }
            
        case .brew:
            BrewManagementView(modifyingBrew: $modifyingBrew)
        }
    }
}
