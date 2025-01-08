//
//  SettingsView+BrewPath.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SettingsView {
    struct BrewSettingsView: View {
        @AppStorage(Preferences.customUserBrewPath.rawValue) var customUserBrewPath: String = "/opt/homebrew/bin/brew"
        @AppStorage(Preferences.brewPathOption.rawValue) var brewPathOption = BrewPaths.PathOption.appPath.rawValue
        @AppStorage(Preferences.noQuarantine.rawValue) var noQuarantine: Bool = false

        @State var isSelectedBrewPathValid = false

        /// Brew installation option before making changes
        @State var previousBrewOption: Int = 0

        var body: some View {
            VStack(alignment: .leading) {
                Text("Brew Executable Path", comment: "Settings brew path selector")
                    .bold()

                BrewPathSelectorView(isSelectedPathValid: $isSelectedBrewPathValid)

                Text("Currently selected brew path is invalid", comment: "Settings invalid brew path message")
                    .foregroundColor(.red)
                    .opacity(isSelectedBrewPathValid ? 0 : 1)

                // Brew path changed
                if previousBrewOption != brewPathOption && isSelectedBrewPathValid {
                    Text(
                        "Brew path has been modified. Restart app for changes to take effect.",
                        comment: "Settings brew path changed message"
                    )
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)

                    Button("Relaunch", role: .destructive) {
                        Task.detached {
                            try? await Shell.runAsync("/usr/bin/osascript -e 'tell application \"Applite\" to quit' && sleep 2 && open \"\(Bundle.main.bundlePath)\"")
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                Text("Appdir", comment: "Brew settings appdir section title")
                    .bold()

                AppdirSelectorView()

                Divider()
                    .padding(.vertical, 8)

                Text("Other Flags", comment: "Brew settings command line flags section title")
                    .bold()

                Toggle(isOn: $noQuarantine) {
                    Text("No Quarantine", comment: "Brew no quarantine flag toggle title")
                }
            }
            .onAppear {
                previousBrewOption = BrewPaths.selectedBrewOption.rawValue
            }
            .padding()
        }
    }
}
