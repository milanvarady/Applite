//
//  SettingsView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 12. 29..
//

import SwiftUI
import AppKit
import Sparkle

public enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: Self { self }
}

/// Settings pane
struct SettingsView: View {
    let updater: SPUUpdater

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            BrewPathView()
                .tabItem {
                    Label("Brew Path", systemImage: "mug")
                }

            UpdateSettingsView(updater: updater)
                .tabItem {
                    Label("Updates", systemImage: "arrow.clockwise")
                }

            ProxySettingsView()
                .tabItem {
                    Label("Proxy", systemImage: "network.badge.shield.half.filled")
                }

            UninstallView()
                .tabItem {
                    Label("Uninstall", systemImage: "trash")
                }
        }
        .labelStyle(.titleAndIcon)
        .presentedWindowToolbarStyle(.expanded)

        .contentShape(Rectangle())
        .onTapGesture {
            // Deselect textfield when clicking away
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .frame(width: 400)
    }
}

fileprivate struct GeneralSettingsView: View {
    @AppStorage(Preferences.colorSchemePreference.rawValue) var colorSchemePreference: ColorSchemePreference = .system
    @AppStorage(Preferences.notificationSuccess.rawValue) var notificationOnSuccess: Bool = false
    @AppStorage(Preferences.notificationFailure.rawValue) var notificationOnFailure: Bool = true

    /// Needed for a workaround for changing the color scheme
    @State var fixingColor = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Appearance")
                .bold()

            Picker("Color Scheme:", selection: $colorSchemePreference) {
                ForEach(ColorSchemePreference.allCases) { color in
                    Text(LocalizedStringKey(color.rawValue.capitalized))
                }
            }
            .pickerStyle(.segmented)

            Divider()
                .padding(.vertical)

            Text("Notifications")
                .bold()

            Toggle("Task completions", isOn: $notificationOnSuccess)
            Toggle("Task errors", isOn: $notificationOnFailure)
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

fileprivate struct BrewPathView: View {
    @AppStorage(Preferences.customUserBrewPath.rawValue) var customUserBrewPath: String = "/opt/homebrew/bin/brew"
    @AppStorage(Preferences.brewPathOption.rawValue) var brewPathOption = BrewPaths.PathOption.appPath.rawValue

    @State var isSelectedBrewPathValid = false

    /// Brew installation option before making changes
    @State var previousBrewOption: Int = 0

    var body: some View {
        VStack(alignment: .leading) {
            Text("Brew Executable Path")
                .bold()

            BrewPathSelectorView(isSelectedPathValid: $isSelectedBrewPathValid)

            Text("Currently selected brew path is invalid")
                .foregroundColor(.red)
                .opacity(isSelectedBrewPathValid ? 0 : 1)

            // Brew path changed
            if previousBrewOption != brewPathOption && isSelectedBrewPathValid {
                Text("Brew path has been modified. Restart app for changes to take effect.")
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Relaunch", role: .destructive) {
                    Task {
                        await shell("/usr/bin/osascript -e 'tell application \"\(Bundle.main.appName)\" to quit' && sleep 2 && open \"\(Bundle.main.bundlePath)\"")
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Text("Appdir")
                .bold()
            
            AppdirSelectorView()
        }
        .onAppear {
            previousBrewOption = BrewPaths.selectedBrewOption.rawValue
        }
        .padding()
    }
}

fileprivate struct UpdateSettingsView: View {
    private let updater: SPUUpdater

    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    var body: some View {
        VStack {
            CheckForUpdatesView(updater: updater) {
                Label("Check for Updates...", systemImage: "arrow.uturn.down")
            }

            Text("Current app version: \(Bundle.main.version) (\(Bundle.main.buildNumber))")
                .font(.system(.body, weight: .light))
                .foregroundColor(.secondary)

            Spacer()
                .frame(height: 20)

            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }

            Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
        }
        .padding()
    }
}

fileprivate struct ProxySettingsView: View {
    @AppStorage(Preferences.networkProxyEnabled.rawValue) var proxyEnabled: Bool = true
    @AppStorage(Preferences.preferredProxyType.rawValue) var preferredProxyType: NetworkProxyType = .http

    var body: some View {
        VStack(alignment: .center) {
            Toggle("Use system proxy", isOn: $proxyEnabled)

            Picker("Preferred proxy protocol", selection: $preferredProxyType) {
                ForEach(NetworkProxyType.allCases, id: \.self) { proxyType in
                    Text(proxyType.displayName)
                        .tag(proxyType.rawValue)
                }
            }
            .padding(.bottom)

            Text("\(Bundle.main.appName) uses the system network proxy, but it can only use one protocol (HTTP, HTTPS, or SOCKS5). Select your preferred method.")
                .font(.system(.body, weight: .light))
                .frame(minHeight: 60)
        }
        .padding()
    }
}

fileprivate struct UninstallView: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .center) {
            Button(role: .destructive) {
                openWindow(id: "uninstall-self")
            } label: {
                Label("Uninstall", systemImage: "trash.fill")
            }
            .bigButton(foregroundColor: .white, backgroundColor: .red)

            Text("Uninstall \(Bundle.main.appName), related files and cache.")
        }
        .padding()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(updater: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater)
    }
}
