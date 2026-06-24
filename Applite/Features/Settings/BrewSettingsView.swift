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

    @AppStorage(Preferences.customUserBrewPath.rawValue) var customUserBrewPath: String = "/opt/homebrew/bin/brew"
    @AppStorage(Preferences.brewPathOption.rawValue) var brewPathOption = BrewPaths.PathOption.appPath.rawValue
    @AppStorage(Preferences.includeCasksFromTaps.rawValue) var includeCasksFromTaps: Bool = true
    @AppStorage(Preferences.noQuarantine.rawValue) var noQuarantine: Bool = false

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
        VStack(alignment: .leading) {
            pathSettings
            divider

            tapSettings
            divider

            appdirSettings
            divider

            otherFlags

            refreshCatalogPrompt
                .padding(.top)
        }
        .onAppear {
            previousBrewOption = BrewPaths.selectedBrewOption.rawValue
            previousIncludeCasksFromTaps = includeCasksFromTaps
        }
        .padding()
    }

    var divider: some View {
        Divider()
            .padding(.vertical, 8)
    }

    var pathSettings: some View {
        VStack(alignment: .leading) {
            Text("Brew Executable Path", comment: "Settings brew path selector")
                .bold()

            BrewPathSelectorView(isSelectedPathValid: $isSelectedBrewPathValid)

            Text("Currently selected brew path is invalid", comment: "Settings invalid brew path message")
                .foregroundStyle(.red)
                .opacity(isSelectedBrewPathValid ? 0 : 1)
        }
    }

    /// Prompt asking the user to refresh the catalog after a setting that
    /// affects the catalog (brew path or tap inclusion) has changed. Reserves
    /// a fixed height so the form doesn't jump when it appears.
    var refreshCatalogPrompt: some View {
        HStack {
            Image(systemName: "exclamationmark.arrow.circlepath")
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
        .frame(height: 32)
        .opacity(needsRefresh ? 1 : 0)
    }

    var tapSettings: some View {
        VStack(alignment: .leading) {
            Text("Taps", comment: "Brew settings tap section title")
                .bold()

            Toggle("Include Casks from Taps", isOn: $includeCasksFromTaps)
        }
    }

    var appdirSettings: some View {
        VStack(alignment: .leading) {
            Text("Appdir", comment: "Brew settings appdir section title")
                .bold()

            AppdirSelectorView()
        }
    }

    var otherFlags: some View {
        VStack(alignment: .leading) {
            Text("Other Flags", comment: "Brew settings command line flags section title")
                .bold()

            GreedyUpgradeToggle()

            HStack {
                Toggle(isOn: $noQuarantine) {
                    Text("No Quarantine", comment: "Brew no quarantine flag toggle title")
                }

                InfoPopup(text: "Bypasses the Apple Gatekeeper check, which can be useful if the app is from an unregistered developer. **Use it at your own risk!**")
            }
        }
    }

}
