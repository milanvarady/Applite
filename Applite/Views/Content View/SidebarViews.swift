//
//  ContentView+SidebarViews.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct SidebarViews: View {
    @Environment(CaskManager.self) var caskManager
    @Binding var selection: SidebarItem?
    
    var body: some View {
        List(selection: $selection) {
            Divider()
            
            Label("Discover", systemImage: "house.fill")
                .tag(SidebarItem.home)
            
            Label("Updates", systemImage: "arrow.clockwise.circle.fill")
                .badge(caskManager.outdatedViewModels.count)
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
                    Label(category.localizedName, systemImage: category.sfSymbol)
                        .tag(SidebarItem.appCategory(id: category.id))
                }
            }
            
            if !caskManager.taps.isEmpty {
                Section("Taps") {
                    ForEach(caskManager.taps) { tap in
                        Label(tap.title, systemImage: "spigot")
                            .tag(SidebarItem.tap(tap: tap))
                            .truncationMode(.head)
                    }
                }
            }
            
            Section("Homebrew") {
                Label("Manage Homebrew", systemImage: "mug")
                    .tag(SidebarItem.brew)
            }
        }
    }
}
