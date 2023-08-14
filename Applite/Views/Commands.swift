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
    
    @Environment(\.openWindow) var openWindow
    
    var body: some Commands {
        SidebarCommands()
        
        CommandGroup(replacing: .appInfo) {
                        Button("About \(Bundle.main.appName)") {
                            NSApplication.shared.orderFrontStandardAboutPanel(
                                options: [
                                    NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                        string: "MIT Licence",
                                        attributes: [
                                            NSAttributedString.Key.font: NSFont.systemFont(
                                                ofSize: NSFont.smallSystemFontSize)
                                        ]
                                    ),
                                    NSApplication.AboutPanelOptionKey(
                                        rawValue: "Copyright"
                                    ): "© 2023 Milán Várady"
                                ]
                            )
                        }
                    }
        
        CommandGroup(before: .systemServices) {
            Button("Uninstall...") {
                openWindow(id: "uninstall-self")
            }
            
            CheckForUpdatesView(updater: updaterController.updater) {
                Text("Check for Updates...")
            }
            
            Divider()
        }
        
        CommandGroup(replacing: .help) {
            Link("Website", destination: URL(string: "https://aerolite.dev/applite")!)
            Link("Troubleshooting", destination: URL(string: "https://aerolite.dev/applite/troubleshooting.html")!)
            Link("Github", destination: URL(string: "https://github.com/milanvarady/Applite")!)
            Link("Discord", destination: URL(string: "https://discord.gg/ZgB6pRE8Qx")!)
        }
    }
}
