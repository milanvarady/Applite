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

    /// The Settings window's alert surface, owned by `SettingsView`. Load failures triggered from
    /// here must be raised in *this* window — routed to the main window's alert they'd present
    /// behind Settings, or be queued against nothing at all when the main window is closed.
    let alert: AlertManager

    @AppStorage(Preferences.customUserBrewPath) var customUserBrewPath
    @AppStorage(Preferences.brewPathOption) var brewPathOption
    @AppStorage(Preferences.annexUpdateFrequency) var annexUpdateFrequency
    @AppStorage(Preferences.appdirOn) private var appdirOn
    @AppStorage(Preferences.appdirPath) private var appdirPath

    /// Applite's own annex brew is the selected one.
    var isUsingAnnexBrew: Bool { brewPathOption == BrewPaths.PathOption.annex.rawValue }

    // Optimistically assume the path is valid; the async `BrewPathSelectorView` check flips it to
    // false only if it genuinely is. Starting `false` would flash the invalid-path text on the
    // first frame (before the check runs) and then animate it out.
    @State var isSelectedBrewPathValid = true

    /// Captured on appearance so the refresh banner cannot flash on the first frame.
    @State var previousBrewOption: Int?

    var needsRefresh: Bool {
        guard let previousBrewOption else { return false }
        return previousBrewOption != brewPathOption
    }

    var body: some View {
        Form {
            pathSettings
            annexUpdateSettings
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            refreshCatalogBanner
        }
        .animation(.default, value: needsRefresh)
        .animation(.default, value: isSelectedBrewPathValid)
        .onAppear {
            previousBrewOption = brewPathOption
        }
        .onChange(of: [String(brewPathOption), customUserBrewPath, String(appdirOn), appdirPath]) { _, _ in
            caskManager.applyExternalAppDetectionSetting(debounce: true, surfacingErrorsIn: alert)
        }
    }

    var pathSettings: some View {
        Section("Brew Executable Path") {
            BrewPathSelectorView(isSelectedPathValid: $isSelectedBrewPathValid)

            if !isSelectedBrewPathValid {
                HStack {
                    Text("Currently selected brew path is invalid", comment: "Settings invalid brew path message")
                        .foregroundStyle(.red)

                    Spacer(minLength: 8)

                    // Recovery has to be reachable from where the problem is reported. `loadData`
                    // validates the selection, re-runs `bootstrap` to recover when it's invalid, and
                    // leaves `bootstrap.phase` to surface a brew that's genuinely unusable — the same
                    // recovery ⌘R performs. Without this the only way out of a bad path was a menu
                    // item a non-technical user won't find (P3-7).
                    AsyncButton {
                        await caskManager.loadData(surfacingErrorsIn: alert)
                        isSelectedBrewPathValid = await BrewPaths.isSelectedBrewPathValid()
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// Banner asking the user to refresh the catalog after a setting that
    /// affects the catalog (brew path) has changed. Pinned to
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
                        let loaded = await caskManager.loadData(forceSync: true, surfacingErrorsIn: alert)
                        // Recovery may have repointed the selection (detected brew / reinstalled
                        // annex), so re-poll rather than leaving a stale ✗ next to a path that works.
                        isSelectedBrewPathValid = await BrewPaths.isSelectedBrewPathValid()
                        // Only retire the banner if the refresh actually happened. With a broken
                        // brew this button is (correctly) still enabled, but `loadData` drops its
                        // error on that path — clearing the baselines anyway made the prompt vanish
                        // as though the change had been applied when nothing was fetched.
                        guard loaded else { return }
                        previousBrewOption = brewPathOption
                    } label: {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                    // Not gated on path validity: `loadData` *is* the recovery for a bad path, so
                    // disabling it here disabled the fix on exactly the fault it fixes (P3-7).
                    .disabled(caskManager.isRefreshingCatalog)
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

}
