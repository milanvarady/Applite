//
//  SettingsView+BrewSettingsView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import ButtonKit

extension SettingsView {
    struct BrewSettingsView: View {
        @Environment(CaskManager.self) var caskManager

        @AppStorage(Preferences.customUserBrewPath.rawValue) var customUserBrewPath: String = "/opt/homebrew/bin/brew"
        @AppStorage(Preferences.brewPathOption.rawValue) var brewPathOption = BrewPaths.PathOption.appPath.rawValue
        @AppStorage(Preferences.includeCasksFromTaps.rawValue) var includeCasksFromTaps: Bool = true
        @AppStorage(Preferences.noQuarantine.rawValue) var noQuarantine: Bool = false

        @State var isSelectedBrewPathValid = false

        /// Brew installation option before making changes
        @State var previousBrewOption: Int = 0

        /// True when the user picked a different brew path from the one in effect.
        /// Drives the inline refresh prompt under the path selector.
        @State var pathChangedSinceLastLoad: Bool = false

        @State var relaunchNeeded: Bool = false

        var body: some View {
            VStack(alignment: .leading) {
                pathSettings
                divider

                tapSettings
                divider

                appdirSettings
                divider

                otherFlags

                if relaunchNeeded {
                    relauchAppPrompt
                        .padding(.top)
                }
            }
            .onAppear {
                previousBrewOption = BrewPaths.selectedBrewOption.rawValue
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
                    .onChange(of: brewPathOption) { _, newValue in
                        pathChangedSinceLastLoad = previousBrewOption != newValue
                    }

                Text("Currently selected brew path is invalid", comment: "Settings invalid brew path message")
                    .foregroundColor(.red)
                    .opacity(isSelectedBrewPathValid ? 0 : 1)

                refreshCatalogPrompt
            }
        }

        /// Inline prompt that asks the user to refresh the catalog after picking a different
        /// brew path. Reserves a fixed height so the form doesn't jump when the prompt appears.
        var refreshCatalogPrompt: some View {
            HStack {
                Image(systemName: "arrow.clockwise.circle")
                    .imageScale(.large)
                    .foregroundStyle(.blue)

                Text("Refresh to apply new brew path")

                Spacer()

                AsyncButton {
                    await caskManager.loadData(forceSync: true)
                    
                    // Treat the now-loaded option as the baseline so the prompt
                    // hides until the user changes the selection again.
                    previousBrewOption = brewPathOption
                    pathChangedSinceLastLoad = false
                } label: {
                    Label("Refresh Catalog", systemImage: "arrow.clockwise")
                }
                .disabled(caskManager.isRefreshingCatalog || !isSelectedBrewPathValid)
            }
            .frame(height: 32)
            .opacity(pathChangedSinceLastLoad ? 1 : 0)
            .padding(.top, 4)
        }

        var tapSettings: some View {
            VStack(alignment: .leading) {
                Text("Taps", comment: "Brew settings tap section title")
                    .bold()
                
                Toggle("Include Casks from Taps", isOn: $includeCasksFromTaps)
                    .onChange(of: includeCasksFromTaps) {
                        relaunchNeeded = true
                    }
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

        var relauchAppPrompt: some View {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .imageScale(.large)
                        .foregroundStyle(.orange)

                    Text("Restart Applite for changes to take effect.", comment: "Brew settings relaunch app prompt")
                }

                Button(role: .destructive) {
                    relaunchNeeded = false
                    
                    Task.detached {
                        try? await Shell.runAsync("/usr/bin/osascript -e 'tell application \"Applite\" to quit' && sleep 3 && open \"\(Bundle.main.bundlePath)\"")
                    }
                } label: {
                    Label("Relaunch", systemImage: "arrow.trianglehead.clockwise.rotate.90")
                }
                .controlSize(.large)
            }
        }
    }
}
