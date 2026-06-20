//
//  Commands.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 11..
//

import SwiftUI
import Sparkle

struct CommandsMenu: Commands {
    let updaterController: SPUStandardUpdaterController
    let caskManager: CaskManager

    @Environment(\.openWindow) var openWindow

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .appInfo) {
            Divider()

            Button("Refresh App Catalog") {
                Task {
                    do {
                        try await caskManager.refreshCatalog()
                    } catch {
                        caskManager.loadAlert.show(error: error, title: "Failed to refresh catalog")
                    }
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(caskManager.isRefreshingCatalog)
        }

        CommandGroup(before: .systemServices) {
            Button("Uninstall Applite...") {
                openWindow(id: "uninstall-self")
            }

            CheckForUpdatesView(updater: updaterController.updater) {
                Text("Check for Updates...", comment: "Check for update menu bar item")
            }

            Divider()
        }

        CommandGroup(replacing: .newItem) {}
        
        
        CommandGroup(replacing: .help) {
            Link("Website", destination: URL(string: "https://aerolite.dev/applite")!)
            Link("Troubleshooting", destination: URL(string: "https://aerolite.dev/applite/troubleshooting.html")!)
            Link("GitHub", destination: URL(string: "https://github.com/milanvarady/Applite")!)
            Link("Discord", destination: URL(string: "https://discord.gg/MpDMH9cPbK")!)
            Link("Sponsor", destination: URL(string: "https://www.paypal.com/donate/?hosted_button_id=ZMDZSRG9CRY2Y")!)
        }
    }
}
