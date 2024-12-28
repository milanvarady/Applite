//
//  AppView+UninstallButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    struct UninstallButton: View {
        @StateObject var cask: Cask
        @EnvironmentObject var caskData: CaskData

        @State var showingError = false

        var body: some View {
            Button {
                Task {
                    await cask.uninstall(caskData: caskData)
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(.primary)
        }
    }
}
