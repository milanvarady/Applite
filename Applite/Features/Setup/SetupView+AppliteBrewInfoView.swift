//
//  SetupView+AppliteBrewInfoView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.06.
//

import SwiftUI

extension SetupView {
    /// Tells the user that a custom brew installation will be installed
    struct AppliteBrewInfoView: View {
        @Binding var page: SetupPage

        var body: some View {
            VStack {
                Spacer()

                Text("Homebrew Installation", comment: "Setup Applite's brew installation info view title")
                    .font(.appliteMediumTitle)
                    .padding(.bottom, 8)

                Text(
                    "This application uses the free and open source [Homebrew](https://brew.sh/) package manager to download and manage applications. Applite has detected that you don't have brew installed, so it will create a new brew installation just for Applite under `~/Library/Application Support/Applite.`",
                    comment: "Setup Applite's brew installtion info view description"
                )

                Spacer()
            }
            .frame(maxWidth: 500)
            .padding()
        }
    }
}
