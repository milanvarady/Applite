//
//  ContentView+SidebarItems.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension ContentView {
    var sidebarItems: some View {
        List(selection: $selection) {
            Divider()

            Label("Discover", systemImage: "house.fill")
                .tag("home")

            Label("Updates", systemImage: "arrow.clockwise.circle.fill")
                .badge(caskData.outdatedCasks.count)
                .tag("updates")

            Label("Installed", systemImage: "externaldrive.fill.badge.checkmark")
                .tag("installed")

            Label("Active Tasks", systemImage: "gearshape.arrow.triangle.2.circlepath")
                .badge(caskData.busyCasks.count)
                .tag("activeTasks")

            Section("Categories") {
                ForEach(categories) { category in
                    Label(LocalizedStringKey(category.id), systemImage: category.sfSymbol)
                        .tag(category.id)
                }
            }

            Section("Homebrew") {
                NavigationLink(value: "brew", label: {
                    Label("Manage Homebrew", systemImage: "mug")
                })
            }
        }
    }

}
