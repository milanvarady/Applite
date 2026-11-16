//
//  GeneralSettingsView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(Preferences.colorSchemePreference) var colorSchemePreference

    /// Needed for a workaround for changing the color scheme
    @State var fixingColor = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color Scheme:", selection: $colorSchemePreference) {
                    ForEach(ColorSchemePreference.allCases) { color in
                        Text(color.description)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .onChange(of: colorSchemePreference) { _, colorScheme in
            // Don't remove this!
            // This is here because changing the .preferredColorScheme view modifier is bugged
            // When it's set back to nil, parts of the UI don't default back to the system color scheme
            if colorScheme == .system && !fixingColor {
                // Set fixingColor to true, so we don't recursively call this function
                self.fixingColor = true

                // Get system color scheme
                let darkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"

                Task {
                    // Set color scheme to system
                    colorSchemePreference = darkMode ? .dark : .light
                    // Wait
                    try? await Task.sleep(for: .seconds(0.1))
                    // Set it back to nil (.system)
                    colorSchemePreference = .system
                    // Wait
                    try? await Task.sleep(for: .seconds(0.1))
                    // Set fixing color back to false
                    await MainActor.run { self.fixingColor = false }
                }
            }
        }
    }
}
