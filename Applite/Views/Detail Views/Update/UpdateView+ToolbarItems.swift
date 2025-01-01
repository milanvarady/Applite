//
//  UpdateView+ToolbarItems.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension UpdateView {
    var toolbarItems: some ToolbarContent {
        ToolbarItemGroup {
            greedyUpdateButton

            // Refresh outdated casks
            if refreshing {
                SmallProgressView()
            } else {
                refreshButton
            }
        }
    }

    private var greedyUpdateButton: some View {
        Button {
            showingGreedyUpdateConfirm = true
        } label: {
            Label("Show All Updates", systemImage: "eye")
        }
        .labelStyle(.titleAndIcon)
        .alert("Notice", isPresented: $showingGreedyUpdateConfirm) {
            Button("Show All") {
                Task {
                    do {
                        try await caskManager.refreshOutdated(greedy: true)
                    } catch {
                        loadAlert.show(title: "Failed to load updates", message: error.localizedDescription)
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will show updates from applications that have auto-update turned off, i.e., applications that are taking care of their own updates.")
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                refreshing = true

                do {
                    try await caskManager.refreshOutdated(greedy: true)
                } catch {
                    loadAlert.show(title: "Failed to refresh updates", message: error.localizedDescription)
                }

                refreshing = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
    }
}
