//
//  SettingsView+Uninstaller.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SettingsView {
    struct UninstallView: View {
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
}
