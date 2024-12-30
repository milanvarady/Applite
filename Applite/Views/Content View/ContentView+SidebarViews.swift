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
                .badge(caskData.outdatedCasks.count)
                .tag(SidebarItem.updates)

            Label("Installed", systemImage: "externaldrive.fill.badge.checkmark")
                .tag(SidebarItem.installed)

            Label("Active Tasks", systemImage: "gearshape.arrow.triangle.2.circlepath")
                .badge(caskData.busyCasks.count)
                .tag(SidebarItem.activeTasks)

            Label("App Migration", systemImage: "square.and.arrow.up.on.square")
                .tag(SidebarItem.appMigration)

            Section("Categories") {
                ForEach(categories) { category in
                    Label(LocalizedStringKey(category.id), systemImage: category.sfSymbol)
                        .tag(SidebarItem.appCategory(categoryId: category.id))
                }
            }

            Section("Homebrew") {
                Label("Manage Homebrew", systemImage: "mug")
                    .tag(SidebarItem.brew)
            }
        }
    }

}
