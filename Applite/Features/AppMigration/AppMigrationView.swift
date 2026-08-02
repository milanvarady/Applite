//
//  AppMigrationView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.30.
//

import SwiftUI

struct AppMigrationView: View {
    private let width: CGFloat = 620
    private let cardPadding: CGFloat = 24
    private let cardHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            titleAndDescription
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 24)

            HStack(spacing: 32) {
                Card(padding: cardPadding) {
                    ExportAppsView()
                }

                Card(padding: cardPadding) {
                    ImportAppsView()
                }
            }
            .frame(maxHeight: cardHeight)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: width, maxHeight: .infinity)   // fill height, cap width
        .frame(maxWidth: .infinity)                     // center the column in the pane
        .padding(40)
        .navigationTitle("App Migration")
    }

    private var titleAndDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("App Migration", comment: "App Migration view title")
                .font(.appliteMediumTitle)

            Text(
                "Export your installed apps to a file, then import it on another Mac to reinstall them all — the easy way to set up a new machine.",
                comment: "App migration view description"
            )
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AppMigrationView()
}
