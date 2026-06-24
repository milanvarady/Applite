//
//  ToolbarItems.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

struct ToolbarItems: ToolbarContent {
    @Environment(CaskManager.self) var caskManager
    var loadAlert: AlertManager
    
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem {
                GreedyUpgradeToggle()
                    .padding(.horizontal)
                    .toggleStyle(.checkbox)
            }

            ToolbarSpacer()

            ToolbarItem {
                refreshButton
            }
        } else {
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
    }

    private var refreshButton: some View {
        AsyncButton("Refresh", systemImage: "arrow.clockwise") {
            try await caskManager.refreshOutdated()
        }
        .onButtonStateError { error in
            loadAlert.show(title: "Failed to refresh updates", message: error.error.localizedDescription)
        }
    }
}
