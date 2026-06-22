//
//  AppView+IconAndDescriptionView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    struct IconAndDescriptionView: View {
        var cask: CaskViewModel
        @AppStorage("showToken") var showToken: Bool = false
        @Environment(\.openURL) private var openURL
        
        var body: some View {
            HStack {
                if let iconURL = URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(cask.token)/AppIcon.png"),
                   let faviconURL = URL(string: "https://icon.horse/icon/\(cask.homepage?.host ?? "")") {
                    AppIconView(
                        iconURL: iconURL,
                        faviconURL: faviconURL,
                        cacheKey: cask.token
                    )
                    .padding(.leading, 5)
                }

                // Name and description
                VStack(alignment: .leading) {
                    Button {
                        // Cmd+click is reserved for opening the homepage (handled
                        // by the outer simultaneousGesture); don't also toggle the token.
                        guard !NSEvent.modifierFlags.contains(.command) else { return }
                        showToken.toggle()
                    } label: {
                        Text(showToken ? cask.token : cask.name)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .buttonStyle(.plain)

                    Text(cask.descriptionText)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture()
                    .modifiers(.command)
                    .onEnded {
                        if let url = cask.homepage {
                            openURL(url)
                        }
                    }
            )
        }
    }
}
