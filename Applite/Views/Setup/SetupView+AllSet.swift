//
//  SetupView+AllSet.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SetupView {
    /// Page shown when setup is complete
    struct AllSet: View {
        @AppStorage(Preferences.setupComplete.rawValue) var setupComplete = false

        var body: some View {
            Text("All set!", comment: "Setup done message")
                .font(.appliteLargeTitle)
                .padding(.top, 40)

            Button("Start Using Applite") {
                setupComplete = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
