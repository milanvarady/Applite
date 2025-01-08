//
//  BrewManagementView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 09..
//

import SwiftUI
import OSLog

/// Displays info and provides tools to manage brew installation
struct BrewManagementView: View {
    @Binding var modifyingBrew: Bool
    
    static let logger = Logger()

    let width: CGFloat = 640
    let columnSpacing: CGFloat = 40

    var cardWidth: CGFloat {
        (width - columnSpacing) / 2
    }
    let cardPadding: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack {
                VStack(alignment: .leading) {
                    titleAndDescription

                    InfoView(cardWidth: cardWidth, cardPadding: cardPadding)
                        .padding(.vertical, 16)

                    ActionsView(modifyingBrew: $modifyingBrew, cardWidth: cardWidth, cardPadding: cardPadding)
                    
                    Spacer()
                }
                .frame(width: width)
                .padding(12)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var titleAndDescription: some View {
        VStack(alignment: .leading) {
            Text("Manage Homebrew", comment: "Manage Homebrew view title")
                .font(.appliteMediumTitle)
                .padding(.bottom, 2)

            Text(
                "This application uses the [Homebrew](https://brew.sh/) (brew for short) package manager to download apps. Homebrew is a free and open source command line utility that can download useful developer tools as well as desktop applications.",
                comment: "Manage Homebrew view description"
            )
        }
    }
}

struct BrewManagementView_Previews: PreviewProvider {
    static var previews: some View {
        BrewManagementView(modifyingBrew: .constant(false))
    }
}
