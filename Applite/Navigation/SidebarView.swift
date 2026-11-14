//
//  SidebarView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct SidebarView: View {
    @Environment(CaskManager.self) var caskManager
    @Binding var selection: SidebarItem?
    let onActivate: (SidebarItem) -> Void
    
    var body: some View {
        List(selection: $selection) {
            Divider()
            
            sidebarItem(.home) {
                Label("Discover", systemImage: "star")
            }
            
            sidebarItem(.updates) {
                Label("Updates", systemImage: "square.and.arrow.down")
            }
            .badge(caskManager.outdatedCount)
            
            sidebarItem(.installed) {
                Label("Installed", systemImage: "externaldrive.badge.checkmark")
            }
            .badge(caskManager.locallyInstalledCount)
            
            sidebarItem(.activeTasks) {
                Label("Active Tasks", systemImage: "gearshape")
            }
            .badge(caskManager.activeTasks.count)
            
            sidebarItem(.appMigration) {
                Label("App Migration", systemImage: "square.and.arrow.up.on.square")
            }
            
            Section("Categories") {
                ForEach(caskManager.categories) { category in
                    sidebarItem(.appCategory(id: category.id)) {
                        Label(category.localizedName, systemImage: category.sfSymbol)
                    }
                }
            }
            
            if !caskManager.taps.isEmpty {
                Section("Taps") {
                    ForEach(caskManager.taps) { tap in
                        sidebarItem(.tap(tap: tap)) {
                            Label(tap.title, systemImage: "spigot")
                                .truncationMode(.head)
                        }
                    }
                }
            }
            
            Section("Homebrew") {
                sidebarItem(.brew) {
                    Label("Manage Homebrew", systemImage: "mug")
                }
            }
        }
    }

    private func sidebarItem<Content: View>(
        _ item: SidebarItem, @ViewBuilder label: () -> Content
    ) -> some View {
        Button {
            onActivate(item)
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tag(item)
    }
}
