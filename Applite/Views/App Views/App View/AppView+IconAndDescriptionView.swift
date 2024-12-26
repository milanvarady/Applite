//
//  AppView+IconAndDescriptionView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    var iconAndDescriptionView: some View {
        return HStack {
            if let iconURL = URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(cask.id)/AppIcon.png"),
               let faviconURL = URL(string: "https://icon.horse/icon/\(cask.homepageURL?.host ?? "")") {
                AppIconView(
                    iconURL: iconURL,
                    faviconURL: faviconURL,
                    cacheKey: cask.id
                )
                .padding(.leading, 5)
            }

            // Name and description
            VStack(alignment: .leading) {
                Text(cask.name)
                    .font(.system(size: 16, weight: .bold))

                Text(cask.description)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .alert("Broken Brew Path", isPresented: $showingBrewPathError) {
            Button("OK", role: .cancel) {
                showingBrewPathError = false
            }
        } message: {
            Text(LocalizedStringKey(DependencyManager.brokenPathOrIstallMessage))
        }
    }
}
