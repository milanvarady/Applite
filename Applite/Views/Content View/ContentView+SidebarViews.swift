//
//  ContentView+SidebarViews.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension ContentView {
    var sidebarViews: some View {
        List(selection: $selection) {
            Divider()

            Label("Discover", systemImage: "house.fill")
                .tag(SidebarItem.home)

            Label("Updates", systemImage: "arrow.clockwise.circle.fill")
                .badge(caskManager.outdatedCasks.count)
                .tag(SidebarItem.updates)

            Label("Installed", systemImage: "externaldrive.fill.badge.checkmark")
                .tag(SidebarItem.installed)

            Label("Active Tasks", systemImage: "gearshape.arrow.triangle.2.circlepath")
                .badge(caskManager.activeTasks.count)
                .tag(SidebarItem.activeTasks)

            Label("App Migration", systemImage: "square.and.arrow.up.on.square")
                .tag(SidebarItem.appMigration)

            Section("Categories") {
                ForEach(caskManager.categories) { category in
                    Label(LocalizedStringKey(category.name), systemImage: category.sfSymbol)
                        .tag(SidebarItem.appCategory(category: category))
                }
            }

            Section("Homebrew") {
                Label("Manage Homebrew", systemImage: "mug")
                    .tag(SidebarItem.brew)
            }
        }
    }

}
