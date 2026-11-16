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
import OSLog

@main
struct AppliteApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var appDelegate

    @State var caskManager: CaskManager
    @State private var settingsNavigation = SettingsNavigation()

    private static var instanceLock: SingleInstanceLock?
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppLaunch")
    
    @AppStorage(Preferences.colorSchemePreference) var colorSchemePreference

    /// Sparkle update controller
    private let updaterController: SPUStandardUpdaterController

    /// One observable bridge over the updater, shared by the menu bar, Settings and the self-card
    /// so all three see the same live state.
    private let updaterModel: UpdaterViewModel
    
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
        Self.enforceSingleInstance()
        _caskManager = State(initialValue: CaskManager())
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterModel = UpdaterViewModel(updater: updaterController.updater)

        // Setup network proxy for Kingfisher
        KingfisherManager.shared.downloader.sessionConfiguration = NetworkProxyManager.getURLSessionConfiguration()
    }
    
    var body: some Scene {
        Window("Applite", id: "main") {
            MainWindowView(applicationDelegate: appDelegate)
                .environment(caskManager)
                .environment(settingsNavigation)
                .environment(\.updater, updaterModel)
                .frame(minWidth: 970, minHeight: 520)
                .preferredColorScheme(selectedColorScheme)
                // Give the app delegate the live manager so it can stop running
                // tasks on quit. Direct reference — no `NSApp.delegate as?` cast
                // or timing fragility.
                .onAppear { appDelegate.caskManager = caskManager }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandsMenu(updater: updaterModel, caskManager: caskManager, settingsNavigation: settingsNavigation)
        }
        
        Settings {
            SettingsView(updater: updaterModel, navigation: settingsNavigation)
                .environment(caskManager)
                .preferredColorScheme(selectedColorScheme)
        }
        .windowResizability(.contentSize)
        
        WindowGroup("Terminal Output", for: String.self) { $errorString in
            ErrorWindowView(errorString: errorString ?? "N/a")
        }
        .defaultSize(width: 600, height: 400)

    }

    private static func enforceSingleInstance() {
        do {
            try AppPaths.createApplicationSupportIfNeeded()
            let lock = try SingleInstanceLock(at: AppPaths.applicationSupport.appending(path: "instance.lock"))
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
                .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
                .sorted { ($0.launchDate ?? .distantFuture) < ($1.launchDate ?? .distantFuture) }

            // Older releases do not own the lock. Respect a fully launched older copy too,
            // but do not yield ownership to another copy that is still starting.
            if let existing = peers.first(where: { !lock.isPrimary || $0.isFinishedLaunching }) {
                guard let url = existing.bundleURL, NSWorkspace.shared.open(url) else {
                    throw LaunchError.reopenFailed
                }
                exit(EXIT_SUCCESS)
            }

            guard lock.isPrimary else { throw LaunchError.alreadyStarting }
            instanceLock = lock
        } catch {
            logger.error("Single-instance startup failed: \(error.localizedDescription)")
            let alert = NSAlert(error: error)
            alert.messageText = String(localized: "Couldn't start Applite")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            exit(EXIT_FAILURE)
        }
    }

    private enum LaunchError: LocalizedError {
        case reopenFailed
        case alreadyStarting

        var errorDescription: String? {
            switch self {
            case .reopenFailed:
                String(localized: "Applite is already running, but its window couldn't be opened. Select Applite in the Dock.")
            case .alreadyStarting:
                String(localized: "Applite is already starting. Please try again in a moment.")
            }
        }
    }
}
