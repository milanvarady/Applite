//
//  SetupView+BrewPathDetectedView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.07.
//

import SwiftUI

extension SetupView {
    struct BrewPathDetectedView: View {
        @Binding var page: SetupPage

        var body: some View {
            VStack {
                Spacer()

                Text("Brew Installation Detected", comment: "Setup brew path detected view title")
                    .font(.appliteSmallTitle)
                    .padding(.bottom)

                Text("A brew installation was detected at:", comment: "Setup brew path detected view text")

                Card {
                    HStack {
                        Image(systemName: "mug")
                        Text(BrewPaths.currentBrewDirectory.path(percentEncoded: false))
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                .frame(maxWidth: 200, maxHeight: 20)
                .padding(.bottom)

                Text("Continue to use detected installation or select another option below.", comment: "Setup brew path detected view text")

                Spacer()
            }
            .frame(maxWidth: 500)
        }
    }
}
