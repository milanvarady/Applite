//
//  AppView+IconsAndWarnings.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.13.
//

import SwiftUI

extension AppView {
    struct IconsAndWarnings: View {
        @ObservedObject var cask: Cask

        var body: some View {
            // Show tap icon if from a third-party tap
            if cask.info.tap != "homebrew/cask" {
                InfoPopup(
                    text: "This app is from a third-party tap:\n`\(cask.info.tap)`",
                    sfSymbol: "spigot.fill"
                )
                .controlSize(.large)
            }

            if let warning = cask.info.warning {
                Group {
                    switch warning {
                    case .hasCaveat(let caveat):
                        InfoPopup(
                            text: LocalizedStringKey(caveat.cleanTerminalOutput()),
                            sfSymbol: "exclamationmark.circle",
                            extraPaddingForLines: caveat.numberOfLines
                        )

                    case .deprecated(let date, let reason):
                        InfoPopup(
                            text: "**This app is deprecated**\n**Reason:** \(reason)\n**Date:** \(date)",
                            sfSymbol: "exclamationmark.triangle.fill",
                            color: .orange
                        )

                    case .disabled(let date, let reason):
                        InfoPopup(
                            text: "**This app is disabled**\n**Reason:** \(reason)\n**Date:** \(date)",
                            sfSymbol: "exclamationmark.triangle.fill",
                            color: .red
                        )
                    }
                }
                .imageScale(.large)
            }
        }
    }
}
