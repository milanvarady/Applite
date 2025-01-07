//
//  SetupView+PageControllerButtons.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension SetupView {
    struct PageLink: Identifiable, Hashable {
        let title: LocalizedStringKey
        let page: SetupPage

        var id: SetupPage { page }

        func hash(into hasher: inout Hasher) {
            hasher.combine(page)
        }
    }

    /// Adds a Back and Continue button to the bottom of the page
    ///
    /// - Parameters:
    ///   - page: Page binding so it can change the current page
    ///   - canContinue: Controls whether it can go to the next page yet or not
    ///   - pageAfter: Page when clicking on Continue
    ///   - pageBefore: Page when clicking on Back
    ///
    /// - Returns: ``View``
    func pageControlButtons(
        nextPage: SetupPage,
        canContinue: Bool = true,
        additionalLinks: [PageLink]? = nil
    ) -> some View {
        VStack {
            Divider()

            HStack {
                if let additionalLinks {
                    ForEach(Array(additionalLinks.enumerated()), id: \.element) { index, link in
                        Button(link.title) {
                            page = link.page
                        }
                        .buttonStyle(.link)
                        .padding(.horizontal)

                        if additionalLinks.count > 1 && index != additionalLinks.count - 1 {

                            Divider()
                                .frame(height: 20)
                        }
                    }
                }

                Spacer()

                Button("Continue") {
                    withAnimation {
                        page = nextPage
                    }
                }
                .disabled(!canContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.trailing)
            .padding(.bottom, 8)
        }
    }
}
