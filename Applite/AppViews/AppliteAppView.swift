//
//  AppliteAppView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 07. 29..
//

import SwiftUI
import Sparkle

/// This view is included in the installed section so users can update and uninstall Applite itself
struct AppliteAppView: View {
    @Environment(\.openWindow) var openWindow
    /// The app-wide Sparkle updater, injected from `AppliteApp` (see ``UpdaterEnvironmentKey``).
    @Environment(\.updater) private var updater

    var body: some View {
        HStack {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
                .padding(.leading, 5)
            
            // Name and description
            VStack(alignment: .leading) {
                Text("Applite", comment: "Applite app card title")
                    .font(.system(size: 16, weight: .bold))
                
                Text("This app", comment: "Applite app card description")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let updater {
                Button("Check for Updates", action: updater.checkForUpdates)
//                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
            }

            Button {
                openWindow(id: "uninstall-self")
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .frame(width: AppView.dimensions.width, height: AppView.dimensions.height)
    }
}

#Preview {
    AppliteAppView()
        .environment(
            \.updater,
            SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
        )
}
