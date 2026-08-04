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
    @AppStorage(Preferences.includeCasksFromTaps) var includeCasksFromTaps
    @AppStorage(Preferences.annexUpdateFrequency) var annexUpdateFrequency

    /// Applite's own annex brew is the selected one.
    var isUsingAnnexBrew: Bool { brewPathOption == BrewPaths.PathOption.annex.rawValue }

    // Optimistically assume the path is valid; the async `BrewPathSelectorView` check flips it to
    // false only if it genuinely is. Starting `false` would flash the invalid-path text on the
    // first frame (before the check runs) and then animate it out.
    @State var isSelectedBrewPathValid = true

    /// Baseline of the settings as they were when the catalog was last loaded, captured from the
    /// `@AppStorage` values in `.onAppear`. `nil` until then — so `needsRefresh` is false on the
    /// first frame and the refresh banner can't flash in before a baseline exists.
    @State var previousBrewOption: Int?
    @State var previousIncludeCasksFromTaps: Bool?

    var needsRefresh: Bool {
        guard let previousBrewOption, let previousIncludeCasksFromTaps else { return false }
        return previousBrewOption != brewPathOption ||
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
            previousBrewOption = brewPathOption
            previousIncludeCasksFromTaps = includeCasksFromTaps
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
                        previousIncludeCasksFromTaps = includeCasksFromTaps
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
