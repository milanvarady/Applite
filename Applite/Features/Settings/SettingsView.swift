//
//  SettingsView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 12. 29..
//

import SwiftUI
import AppKit
import Sparkle

public enum ColorSchemePreference: String, CaseIterable, Identifiable, Sendable {
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
    let updater: UpdaterViewModel
    @Bindable var navigation: SettingsNavigation

    /// This window's alert surface. Settings is its own scene, so it can't be served by the alert
    /// `ContentView` presents — one manager per window, bound at that window's root (F5/P3-5).
    /// Panes that trigger work owned by `CaskManager` hand this to it as the error surface.
    @State private var alert = AlertManager()

    var body: some View {
        TabView(selection: $navigation.selection) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsNavigation.Pane.general)

            BrewSettingsView(alert: alert)
                .tabItem {
                    Label("Brew", systemImage: "mug")
                }
                .tag(SettingsNavigation.Pane.brew)

            UpdateSettingsView(updater: updater)
                .tabItem {
                    Label("Updates", systemImage: "arrow.clockwise")
                }
                .tag(SettingsNavigation.Pane.updates)

            ProxySettingsView()
                .tabItem {
                    Label("Proxy", systemImage: "network.badge.shield.half.filled")
                }
                .tag(SettingsNavigation.Pane.proxy)

            MirrorsView()
                .tabItem {
                    Label("Mirrors", systemImage: "arrow.left.arrow.right")
                }
                .tag(SettingsNavigation.Pane.mirrors)

            UninstallView()
                .tabItem {
                    Label("Uninstall", systemImage: "trash")
                }
                .tag(SettingsNavigation.Pane.uninstall)
        }
        .labelStyle(.titleAndIcon)
        .alertManager(alert)
        .presentedWindowToolbarStyle(.expanded)
        .contentShape(Rectangle())
        .onTapGesture {
            // Deselect textfield when clicking away
            Task { @MainActor in
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .frame(width: 500, height: 460)
    }
}

#Preview {
    SettingsView(
        updater: UpdaterViewModel(
            updater: SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            ).updater
        ),
        navigation: SettingsNavigation()
    )
}
