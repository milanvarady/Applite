//
//  AppView+IconAndDescriptionView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    var iconAndDescriptionView: some View {
        HStack {
            if let iconURL = URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(cask.info.token)/AppIcon.png"),
               let faviconURL = URL(string: "https://icon.horse/icon/\(cask.info.homepageURL?.host ?? "")") {
                AppIconView(
                    iconURL: iconURL,
                    faviconURL: faviconURL,
                    cacheKey: cask.info.token
                )
                .padding(.leading, 5)
            }

            // Name and description
            VStack(alignment: .leading) {
                Text(cask.info.name)
                    .font(.system(size: 16, weight: .bold))

                Text(cask.info.description)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
