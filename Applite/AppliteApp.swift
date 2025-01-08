//
//  AppliteApp.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import Foundation
import SwiftUI
import Sparkle
import Kingfisher

@main
struct AppliteApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var appDelegate

    @StateObject var caskManager = CaskManager()
    
    @AppStorage(Preferences.colorSchemePreference.rawValue) var colorSchemePreference: ColorSchemePreference = .system
    @AppStorage(Preferences.setupComplete.rawValue) var setupComplete: Bool = false
    
    /// Sparkle update controller
    private let updaterController: SPUStandardUpdaterController
    
    var selectedColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
    
    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Setup network proxy for Kinfisher
        KingfisherManager.shared.downloader.sessionConfiguration = NetworkProxyManager.getURLSessionConfiguration()
    }
    
    var body: some Scene {
        WindowGroup {
            if setupComplete {
                ContentView()
                    .environmentObject(caskManager)
                    .frame(minWidth: 970, minHeight: 520)
                    .preferredColorScheme(selectedColorScheme)
            } else {
                SetupView()
                    .frame(width: 600, height: 400)
                    .preferredColorScheme(selectedColorScheme)
            }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandsMenu(updaterController: updaterController)
        }
        
        Settings {
            SettingsView(updater: updaterController.updater)
                .preferredColorScheme(selectedColorScheme)
        }
        .windowResizability(.contentSize)
        
        Window("Uninstall Applite", id: "uninstall-self") {
            UninstallSelfView()
                .padding()
                .preferredColorScheme(selectedColorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup("Shell Output", for: String.self) { $errorString in
            ErrorWindowView(errorString: errorString ?? "N/a")
        }

        WindowGroup("Cask Info", for: CaskAdditionalInfo.self) { $info in
            CaskInfoWindowView(info: info ?? .dummy)
        }
    }
}
