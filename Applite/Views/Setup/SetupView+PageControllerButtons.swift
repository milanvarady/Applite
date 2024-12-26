//
//  SetupView+PageControllerButtons.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SetupView {
    /// Adds a Back and Continue button to the bottom of the page
    ///
    /// - Parameters:
    ///   - page: Page binding so it can change the current page
    ///   - canContinue: Controls whether it can go to the next page yet or not
    ///   - pageAfter: Page when clicking on Continue
    ///   - pageBefore: Page when clicking on Back
    ///
    /// - Returns: ``View``
    struct PageControlButtons: View {
        @Binding var page: Pages
        @Binding var pushDirection: PushDirection
        let canContinue: Bool
        let pageAfter: Pages
        let pageBefore: Pages?

        var body: some View {
            Spacer()

            Divider()

            HStack {
                Spacer()

                if let pageBefore {
                    Button("Back") {
                        pushDirection = .backward
                        withAnimation {
                            page = pageBefore
                        }
                    }
                    .bigButton(backgroundColor: Color(red: 0.7, green: 0.7, blue: 0.7))
                }

                Button("Continue") {
                    pushDirection = .forward
                    withAnimation {
                        page = pageAfter
                    }
                }
                .disabled(!canContinue)
                .bigButton(backgroundColor: canContinue ? .accentColor : .gray)
            }
            .padding(.trailing)
            .padding(.bottom, 8)
        }
    }
}
