//
//  UpdateView+ToolbarItems.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

extension UpdateView {
    var toolbarItems: some ToolbarContent {
        ToolbarItemGroup {
            greedyUpdateButton
            refreshButton
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
            AsyncButton("Show All") {
                try await caskManager.refreshOutdated()
            }
            .onButtonError { error in
                loadAlert.show(title: "Failed to load updates", message: error.localizedDescription)
            }
            .asyncButtonStyle(.none)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will show updates from applications that have auto-update turned off, i.e., applications that are taking care of their own updates.",
                comment: "Greedy update check alert message"
            )
        }
    }

    private var refreshButton: some View {
        AsyncButton {
            try await caskManager.refreshOutdated()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .onButtonError { error in
            loadAlert.show(title: "Failed to refresh updates", message: error.localizedDescription)
        }
    }
}
