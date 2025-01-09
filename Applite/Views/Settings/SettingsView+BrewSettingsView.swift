//
//  SettingsView+BrewSettingsView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SettingsView {
    struct BrewSettingsView: View {
        @AppStorage(Preferences.customUserBrewPath.rawValue) var customUserBrewPath: String = "/opt/homebrew/bin/brew"
        @AppStorage(Preferences.brewPathOption.rawValue) var brewPathOption = BrewPaths.PathOption.appPath.rawValue
        @AppStorage(Preferences.includeCasksFromTaps.rawValue) var includeCasksFromTaps: Bool = true
        @AppStorage(Preferences.noQuarantine.rawValue) var noQuarantine: Bool = false

        @State var isSelectedBrewPathValid = false

        /// Brew installation option before making changes
        @State var previousBrewOption: Int = 0

        @State var relaunchNeeded: Bool = false

        var body: some View {
            VStack(alignment: .leading) {
                pathSettings
                divider

                tapSettings
                divider

                appdirSettings
                divider

                noQuarantineSettings

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
                    .onChange(of: brewPathOption) { newValue in
                        relaunchNeeded = previousBrewOption != newValue
                    }

                Text("Currently selected brew path is invalid", comment: "Settings invalid brew path message")
                    .foregroundColor(.red)
                    .opacity(isSelectedBrewPathValid ? 0 : 1)
            }
        }

        var tapSettings: some View {
            VStack(alignment: .leading) {
                Text("Taps", comment: "Brew settings tap section title")
                    .bold()
                
                Toggle("Include Casks from Taps", isOn: $includeCasksFromTaps)
                    .onChange(of: includeCasksFromTaps) { _ in
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

        var noQuarantineSettings: some View {
            VStack(alignment: .leading) {
                Text("Other Flags", comment: "Brew settings command line flags section title")
                    .bold()

                Toggle(isOn: $noQuarantine) {
                    Text("No Quarantine", comment: "Brew no quarantine flag toggle title")
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
