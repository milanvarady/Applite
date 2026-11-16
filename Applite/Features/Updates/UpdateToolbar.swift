//
//  UpdateToolbar.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

struct UpdateToolbar: ToolbarContent {
    @Environment(CaskManager.self) var caskManager

    var body: some ToolbarContent {
        ToolbarItem {
            refreshButton
        }
    }

    private var refreshButton: some View {
        AsyncButton("Refresh", systemImage: "arrow.clockwise") {
            // Handle the failure inside the action rather than via `.onButtonStateError`,
            // which re-fires on every re-render while the button stays in its sticky error
            // state — so dismissing the alert would immediately re-present it in a loop.
            do {
                try await caskManager.refreshOutdated()
            } catch {
                caskManager.alert.show(title: "Failed to refresh updates", message: error.localizedDescription)
            }
        }
    }
}
