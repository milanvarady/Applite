//
//  SettingsView+GeneralSettings.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SettingsView {
    struct GeneralSettingsView: View {
        @EnvironmentObject var iCloudSyncManager: ICloudSyncManager

        @AppStorage(Preferences.colorSchemePreference.rawValue) var colorSchemePreference: ColorSchemePreference = .system
        @AppStorage(Preferences.catalogUpdateFrequency.rawValue) var catalogUpdateFrequency: CatalogUpdateFrequency = .everyAppLaunch
        @AppStorage(Preferences.notificationSuccess.rawValue) var notificationOnSuccess: Bool = false
        @AppStorage(Preferences.notificationFailure.rawValue) var notificationOnFailure: Bool = true
        @AppStorage(Preferences.iCloudSyncEnabled.rawValue) var iCloudSyncEnabled: Bool = false

        /// Needed for a workaround for changing the color scheme
        @State var fixingColor = false
        @State var showClearConfirmation = false

        var body: some View {
            VStack(alignment: .leading) {
                Text("Appearance", comment: "Appearnace settings title")
                    .bold()

                Picker("Color Scheme:", selection: $colorSchemePreference) {
                    ForEach(ColorSchemePreference.allCases) { color in
                        Text(color.description)
                    }
                }
                .pickerStyle(.segmented)

                Divider()
                    .padding(.vertical)

                Text("App Catalog", comment: "Catalog settings title")
                    .bold()

                Picker("Fetch app catalog every:", selection: $catalogUpdateFrequency) {
                    ForEach(CatalogUpdateFrequency.allCases) { freq in
                        Text(freq.description)
                    }
                }

                Divider()
                    .padding(.vertical)

                Text("Notifications", comment: "Notification settings title")
                    .bold()

                Toggle("Task completions", isOn: $notificationOnSuccess)
                Toggle("Task errors", isOn: $notificationOnFailure)

                Divider()
                    .padding(.vertical)

                Text("iCloud", comment: "iCloud settings title")
                    .bold()

                Toggle("Sync App History to iCloud", isOn: $iCloudSyncEnabled)

                HStack {
                    Button("Clear All App History") {
                        showClearConfirmation = true
                    }
                    .disabled(!iCloudSyncEnabled)
                    .alert("Clear App History", isPresented: $showClearConfirmation) {
                        Button("Clear", role: .destructive) {
                            iCloudSyncManager.clearAll()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This will remove your app history from all devices. Are you sure?")
                    }
                }
            }
            .padding()
            .onChange(of: colorSchemePreference) {
                // Don't remove this!
                // This is here because changing the .preferredColorScheme view modifier is bugged
                // When it's set back to nil, parts of the UI don't default back to the system color scheme
                if $0 == .system && !fixingColor {
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
}
