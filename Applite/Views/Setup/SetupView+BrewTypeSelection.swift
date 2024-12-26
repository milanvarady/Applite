//
//  SetupView+BrewTypeSelection.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SetupView {
    /// Brew installation method selection page. User can choose to use their brew if they have or create a new installation.
    struct BrewTypeSelection: View {
        @Binding var page: Pages

        var body: some View {
            VStack {
                Spacer()

                Text("Do you already have Homebrew installed?")
                    .font(.system(size: 26, weight: .bold))
                    .padding(.top, 10)
                    .padding(.bottom)

                HStack {
                    Button("Yes") {
                        page = .brewPathSelection
                        BrewPaths.selectedBrewOption = .defaultAppleSilicon
                    }
                    .bigButton()

                    Button("No (I don't know what it is)") {
                        page = .brewInstall
                        BrewPaths.selectedBrewOption = .appPath
                    }
                    .bigButton(backgroundColor: .accentColor)
                }

                Spacer()

                Text("This application uses the free and open source [Homebrew](https://brew.sh/) package manager to download and manage applications. If you already have it installed on your system, you can use it right away. If you don't have brew installed or don't know what it is, select **No**. This will create a new brew installation just for \(Bundle.main.appName).")
                    .padding(.bottom, 22)
            }
            .frame(maxWidth: 540)
            .padding()
        }
    }
}
