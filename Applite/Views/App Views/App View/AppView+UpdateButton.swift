//
//  AppView+UpdateButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    struct UpdateButton: View {
        @EnvironmentObject var caskData: CaskData
        @StateObject var cask: Cask

        var body: some View {
            Button {
                Task {
                    await cask.update(caskData: caskData)
                }
            } label: {
                Image(systemName: "arrow.uturn.down.circle.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(.blue)
        }
    }
}
