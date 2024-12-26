//
//  SetupView+BrewPathSelection.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SetupView {
    /// User can provide installed brew path here
    struct BrewPathSelection: View {
        @Binding var isBrewPathValid: Bool

        var body: some View {
            VStack(alignment: .center) {
                Spacer()

                Text("Provide Brew Executable Path")
                    .font(.system(size: 26, weight: .bold))
                    .padding(.bottom, 30)


                VStack(alignment: .leading) {
                    BrewPathSelectorView(isSelectedPathValid: $isBrewPathValid)

                    Text("Selected brew path is invalid!")
                        .foregroundColor(.red)
                        .opacity(isBrewPathValid ? 0 : 1)
                        .padding(.bottom)

                    Text("Appdir (optional)")
                        .font(.system(size: 16, weight: .bold))

                    AppdirSelectorView()
                }
                .frame(width: 500)

                Spacer()
            }
            .frame(maxWidth: 540)
            .padding()
        }
    }
}