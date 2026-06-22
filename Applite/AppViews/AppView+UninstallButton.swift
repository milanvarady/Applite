//
//  AppView+UninstallButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    struct UninstallButton: View {
        var cask: CaskViewModel
        @Environment(CaskManager.self) var caskManager

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
