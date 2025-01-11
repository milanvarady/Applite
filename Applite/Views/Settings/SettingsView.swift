//
//  SettingsView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 12. 29..
//

import SwiftUI
import AppKit
import Sparkle

public enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: Self { self }

    var description: LocalizedStringKey {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }
}

/// Settings pane
struct SettingsView: View {
    let updater: SPUUpdater

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            BrewSettingsView()
                .tabItem {
                    Label("Brew", systemImage: "mug")
                }

            UpdateSettingsView(updater: updater)
                .tabItem {
                    Label("Updates", systemImage: "arrow.clockwise")
                }

            ProxySettingsView()
                .tabItem {
                    Label("Proxy", systemImage: "network.badge.shield.half.filled")
                }

            UninstallView()
                .tabItem {
                    Label("Uninstall", systemImage: "trash")
                }
        }
        .labelStyle(.titleAndIcon)
        .presentedWindowToolbarStyle(.expanded)
        .contentShape(Rectangle())
        .onTapGesture {
            // Deselect textfield when clicking away
            Task { @MainActor in
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .frame(width: 400)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(updater: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater)
    }
}
