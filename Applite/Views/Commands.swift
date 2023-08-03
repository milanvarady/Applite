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
        
        CommandGroup(before: .systemServices) {
            Button("Uninstall...") {
                openWindow(id: "uninstall-self")
            }
            
            CheckForUpdatesView(updater: updaterController.updater)
            
            Divider()
        }
        
        CommandGroup(before: .help) {
            Link("Website", destination: URL(string: "https://aerolite.dev/applite")!)
            Link("Troubleshooting", destination: URL(string: "https://aerolite.dev/applite/troubleshooting.html")!)
        }
    }
}
