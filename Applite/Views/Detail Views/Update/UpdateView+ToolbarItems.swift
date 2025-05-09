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
            HStack {
                GreedyUpgradeToggle()
                    .toggleStyle(.checkbox)

                Spacer()
                    .frame(width: 16)

                refreshButton

                Spacer()
                    .frame(width: 8)
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private var refreshButton: some View {
        AsyncButton("Refresh", systemImage: "arrow.clockwise") {
            try await caskManager.refreshOutdated()
        }
        .onButtonError { error in
            loadAlert.show(title: "Failed to refresh updates", message: error.localizedDescription)
        }
    }
}
