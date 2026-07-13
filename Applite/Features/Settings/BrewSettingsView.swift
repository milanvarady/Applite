//
//  BrewSettingsView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

struct BrewSettingsView: View {
    @Environment(CaskManager.self) var caskManager

    @AppStorage(Preferences.customUserBrewPath) var customUserBrewPath
    @AppStorage(Preferences.brewPathOption) var brewPathOption
    @AppStorage(Preferences.includeCasksFromTaps) var includeCasksFromTaps
    @AppStorage(Preferences.annexUpdateFrequency) var annexUpdateFrequency

    /// Applite's own annex brew is the selected one.
    var isUsingAnnexBrew: Bool { brewPathOption == BrewPaths.PathOption.annex.rawValue }

    @State var isSelectedBrewPathValid = false

    /// Baseline of the settings as they were when the catalog was last loaded.
    /// The refresh prompt shows whenever the current selection differs from these.
    @State var previousBrewOption: Int = 0
    @State var previousIncludeCasksFromTaps: Bool = true

    var needsRefresh: Bool {
        previousBrewOption != brewPathOption ||
            previousIncludeCasksFromTaps != includeCasksFromTaps
    }

    var body: some View {
        Form {
            pathSettings
            annexUpdateSettings
            tapSettings
            appdirSettings
            otherFlags
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            refreshCatalogBanner
        }
        .animation(.default, value: needsRefresh)
        .animation(.default, value: isSelectedBrewPathValid)
        .onAppear {
            previousBrewOption = BrewPaths.selectedBrewOption.rawValue
            previousIncludeCasksFromTaps = includeCasksFromTaps
        }
    }

    var pathSettings: some View {
        Section("Brew Executable Path") {
            BrewPathSelectorView(isSelectedPathValid: $isSelectedBrewPathValid)

            if !isSelectedBrewPathValid {
                Text("Currently selected brew path is invalid", comment: "Settings invalid brew path message")
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
    }

    /// Banner asking the user to refresh the catalog after a setting that
    /// affects the catalog (brew path or tap inclusion) has changed. Pinned to
    /// the bottom of the pane via `safeAreaInset` so it stays visible even when
    /// the form is scrolled.
    @ViewBuilder
    var refreshCatalogBanner: some View {
        if needsRefresh {
            VStack(spacing: 0) {
                Divider()

                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.yellow)

                    Text("Refresh the app catalog to apply your changes")

                    Spacer()

                    AsyncButton {
                        await caskManager.loadData(forceSync: true)
                        previousBrewOption = brewPathOption
                        previousIncludeCasksFromTaps = includeCasksFromTaps
                    } label: {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                    .disabled(caskManager.isRefreshingCatalog || !isSelectedBrewPathValid)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// How often to silently re-fetch Applite's own Homebrew tarball. Only relevant when the annex
    /// is the selected brew — a user's own brew updates itself via `brew update` as usual.
    @ViewBuilder
    var annexUpdateSettings: some View {
        if isUsingAnnexBrew {
            Section("Homebrew Updates") {
                Picker(selection: $annexUpdateFrequency) {
                    ForEach(CatalogUpdateFrequency.allCases) { frequency in
                        Text(frequency.description).tag(frequency)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update Applite's Homebrew", comment: "Annex brew update frequency title")
                        Text("Applite keeps its own Homebrew current by re-downloading it periodically. Your installed apps are kept.", comment: "Annex brew update frequency description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var tapSettings: some View {
        Section("App Sources") {
            Toggle(isOn: $includeCasksFromTaps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include Third-Party Taps", comment: "Brew settings tap toggle title")
                    Text("Also show apps from Homebrew taps (third-party repositories) you've added manually. (Homebrew: `tap`)", comment: "Brew settings tap toggle description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var appdirSettings: some View {
        Section("Installation Location") {
            AppdirSelectorView()
        }
    }

    var otherFlags: some View {
        Section("Advanced") {
            GreedyUpgradeToggle()
        }
    }

}
