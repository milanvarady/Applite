//
//  AppView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI

/// App view role
enum AppRole {
    case installAndManage   // Used in the download section, or when searching
    case update             // Used in the update section
    case installed          // Used in the installed section
}

/// Shows an application's icon and provides controls for installing, updating, uninstalling and opening the app. Used all across the app.
struct AppView: View {
    /// A ``Cask`` object to display
    @ObservedObject var cask: Cask
    /// Role of the app, e.g. install, updated or uninstall
    var role: AppRole
    
    @Environment(\.openWindow) var openWindow
    
    @EnvironmentObject var caskManager: CaskManager
    
    // Alerts
    @State var failureAlertMessage = ""
    @State var showingFailureAlert = false
    
    // Success animation
    @State var successCheckmarkScale = 0.0001
    @State var keepSuccessIndicator = false
    
    /// App view dimensions, and spacing
    public static let dimensions: (width: CGFloat, height: CGFloat, spacing: CGFloat) = (width: 320, height: 80, spacing: 20)
    
    var body: some View {
        HStack {
            // Icon name and description
            iconAndDescriptionView

            // Show tap icon if from a third-party tap
            if cask.info.tap != "homebrew/cask" {
                Image(systemName: "spigot.fill")
                        .controlSize(.large)
                        .help("This app is from a third-party tap")
            }

            // Buttons
            actionsView
        }
        .buttonStyle(.plain)
        .frame(width: Self.dimensions.width, height: Self.dimensions.height)
        .alertManager(caskManager.alert)
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView(cask: Cask.dummy, role: .installAndManage)
    }
}
