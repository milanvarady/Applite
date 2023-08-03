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
        .frame(width: 400, height: 260)
    }
}

fileprivate struct GeneralSettingsView: View {
    @AppStorage("colorSchemePreference") var colorSchemePreference: ColorSchemePreference = .system
    @AppStorage("notificationSuccess") var notificationOnSuccess: Bool = false
    @AppStorage("notificationFailure") var notificationOnFailure: Bool = true
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Appearance")
                .bold()
            
            Picker("Color Scheme:", selection: $colorSchemePreference) {
                
                ForEach(ColorSchemePreference.allCases) { color in
                    Text(color.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            
            Divider()
                .padding(.vertical)
            
            Text("Notifications")
                .bold()

            Toggle("Task completions", isOn: $notificationOnSuccess)
            Toggle("Task errors", isOn: $notificationOnFailure)
            
            Spacer()
        }
        .padding()
    }
}

fileprivate struct BrewPathView: View {
    @AppStorage("customUserBrewPath") var customUserBrewPath: String = "/opt/homebrew/bin/brew"
    @AppStorage("brewPathOption") var brewPathOption = BrewPaths.PathOption.appPath.rawValue
    
    @State var isSelectedBrewPathValid = false
    
    /// Brew installation option before making changes
    @State var previousBrewOption: Int = 0
    
    var body: some View {
        VStack {
            Text("Brew Executable Path")
                .bold()
            
            BrewPathSelectorView(isSelectedPathValid: $isSelectedBrewPathValid)
                .padding(.bottom, 4)
            
            Text("Currently selected brew path is invalid")
                .foregroundColor(.red)
                .opacity(isSelectedBrewPathValid ? 0 : 1)
            
            if previousBrewOption != brewPathOption && isSelectedBrewPathValid {
                Text("Brew path has been modified. Restart app for changes to take effect.")
                    .foregroundColor(.red)
                
                Button("Relaunch", role: .destructive) {
                    Task {
                        await shell("/usr/bin/osascript -e 'tell application \"\(Bundle.main.appName)\" to quit' && sleep 2 && open \"/Applications/\(Bundle.main.appName).app\"")
                    }
                }
            }
        }
        .padding()
        .onAppear {
            previousBrewOption = BrewPaths.selectedBrewOption.rawValue
        }
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
            CheckForUpdatesView(updater: updater)
            
            Text("Current app version: \(Bundle.main.version) (\(Bundle.main.buildNumber))")
                .font(.system(.body, weight: .light))
                .foregroundColor(.secondary)
            
            Spacer()
                .frame(height: 30)
            
            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }
            
            Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
        }.padding()
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
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(updater: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater)
    }
}
