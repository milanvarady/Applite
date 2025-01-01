//
//  AppMigrationView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.30.
//

import SwiftUI

struct AppMigrationView: View {
    let width: CGFloat = 620
    let columnSpacing: CGFloat = 40

    var cardWidth: CGFloat {
        (width - columnSpacing) / 2
    }
    let cardHeight: CGFloat = 220
    let cardPadding: CGFloat = 24

    var body: some View {
        VStack {
            titleAndDescription
                .padding(.vertical, 40)

            HStack(spacing: columnSpacing) {
                Card(cardWidth: cardWidth, cardHeight: cardHeight, paddig: cardPadding) {
                    ExportView()
                }

                Card(cardWidth: cardWidth, cardHeight: cardHeight, paddig: cardPadding) {
                    ImportView()
                }
            }

            Spacer()
        }
        .frame(maxWidth: width)
    }

    var titleAndDescription: some View {
        VStack(alignment: .leading) {
            Text("App Migration")
                .font(.appliteMediumTitle)
                .padding(.bottom, 2)

            Text("Export all of your currently installed apps to a file. Import the file to another device to install them all. Useful when setting up a new Mac.")
        }
    }
}

#Preview {
    AppMigrationView()
}
