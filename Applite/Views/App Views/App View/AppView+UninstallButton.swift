//
//  AppView+UninstallButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    struct UninstallButton: View {
        @ObservedObject var cask: Cask
        @EnvironmentObject var caskManager: CaskManager

        @State var showingError = false

        var body: some View {
            Button {
                caskManager.uninstall(cask)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(.primary)
        }
    }
}
