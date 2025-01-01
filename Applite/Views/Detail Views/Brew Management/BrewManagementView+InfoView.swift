//
//  BrewManagementView+InfoView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI

extension BrewManagementView {
    struct InfoView: View {
        let cardWidth: CGFloat
        let cardPadding: CGFloat
        let cardHeight: CGFloat = 120

        // These will be loaded in asynchronously
        @State var homebrewVersion = "loading..."
        @State var numberOfCasks = "loading..."

        var body: some View {
            VStack(alignment: .leading) {
                Text("Info")
                    .font(.appliteSmallTitle)

                HStack {
                    infoCard(title: "Homebrew Version", info: homebrewVersion)

                    infoCard(title: "Apps Installed", info: numberOfCasks)
                }
            }
            .task {
                // Get version
                guard let versionOutput = try? await Shell.runBrewCommand(["--version"]),
                      let version = versionOutput.firstMatch(of: /Homebrew ([\d\.]+)/),
                      let casksInstalled = try? await Shell.runAsync("\(BrewPaths.currentBrewExecutable) list --cask | wc -w") else {

                    homebrewVersion = "Error"
                    numberOfCasks = "Error"
                    return
                }

                homebrewVersion = String(version.1)
                numberOfCasks = casksInstalled.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        private func infoCard(title: LocalizedStringKey, info: String) -> some View {
            Card(cardWidth: cardWidth, cardHeight: cardHeight, paddig: cardPadding) {
                VStack {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))

                    Text(info)
                        .font(.system(size: 52, weight: .thin))

                    Spacer()
                }
            }
        }
    }
}
