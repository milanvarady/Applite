//
//  AllSetView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

/// Page shown when setup is complete
struct AllSetView: View {
    @AppStorage(Preferences.setupComplete) var setupComplete

    var body: some View {
        Text("All set!", comment: "Setup done message")
            .font(.appliteLargeTitle)
            .padding(.top, 40)

        Button("Start Using Applite") {
            setupComplete = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }
}
