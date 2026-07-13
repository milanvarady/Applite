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

    @State var caskManager = CaskManager()
    
    @AppStorage(Preferences.colorSchemePreference) var colorSchemePreference

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

        // Setup network proxy for Kingfisher
        KingfisherManager.shared.downloader.sessionConfiguration = NetworkProxyManager.getURLSessionConfiguration()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(caskManager)
                .environment(\.updater, updaterController.updater)
                .frame(minWidth: 970, minHeight: 520)
                .preferredColorScheme(selectedColorScheme)
                // Give the app delegate the live manager so it can stop running
                // tasks on quit. Direct reference — no `NSApp.delegate as?` cast
                // or timing fragility.
                .onAppear { appDelegate.caskManager = caskManager }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandsMenu(updaterController: updaterController, caskManager: caskManager)
        }
        
        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(caskManager)
                .preferredColorScheme(selectedColorScheme)
        }
        .windowResizability(.contentSize)
        
        Window("Uninstall Applite", id: "uninstall-self") {
            UninstallView()
                .frame(width: 480, height: 520)
                .preferredColorScheme(selectedColorScheme)
        }
        .windowResizability(.contentSize)

        WindowGroup("Terminal Output", for: String.self) { $errorString in
            ErrorWindowView(errorString: errorString ?? "N/a")
        }
        .defaultSize(width: 600, height: 400)

        WindowGroup("Cask Info", for: CaskAdditionalInfo.self) { $info in
            CaskInfoWindowView(info: info ?? .dummy)
        }
        .windowResizability(.contentSize)
    }
}
