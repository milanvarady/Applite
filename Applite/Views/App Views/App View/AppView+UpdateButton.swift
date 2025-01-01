//
//  AppView+UpdateButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    struct UpdateButton: View {
        @EnvironmentObject var caskManager: CaskManager
        @StateObject var cask: Cask

        var body: some View {
            Button {
                caskManager.update(cask)
            } label: {
                Image(systemName: "arrow.uturn.down.circle.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(.blue)
        }
    }
}
