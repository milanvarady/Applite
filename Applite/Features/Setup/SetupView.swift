//
//  SetupView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 03..
//

import SwiftUI
import AppKit

/// This view is shown when first launching the app. It welcomes the user and installs dependencies (Homebrew, Xcode Command Line Tools).
struct SetupView: View {
    enum SetupPage {
        case welcome
        case appliteBrewInfo
        case appliteBrewInstall
        case brewPathDetected
        case brewPathSelection
        case allSet
    }

    struct PageLink: Identifiable, Hashable {
        let title: LocalizedStringKey
        let page: SetupPage

        var id: SetupPage { page }

        func hash(into hasher: inout Hasher) {
            hasher.combine(page)
        }
    }

    @State var page: SetupPage = .welcome

    @State var detectedBrewInstallation: BrewPaths.PathOption? = nil

    @State var isBrewPathValid = false
    @State var isBrewInstallDone = false

    var body: some View {
        VStack {
            switch page {
            case .welcome:
                Welcome()
                    .transition(.push(from: .trailing))

                Spacer()

                pageControlButtons(
                    nextPage: detectedBrewInstallation == nil ? .appliteBrewInfo : .brewPathDetected
                )

            case .appliteBrewInfo:
                AppliteBrewInfoView(page: $page)
                    .transition(.push(from: .trailing))

                pageControlButtons(
                    nextPage: .appliteBrewInstall,
                    additionalLinks: [PageLink(title: "I already have brew installed", page: .brewPathSelection)]
                )

            case .appliteBrewInstall:
                AppliteBrewInstall(isDone: $isBrewInstallDone)
                    .transition(.push(from: .trailing))

                Spacer()

                pageControlButtons(
                    nextPage: .allSet,
                    canContinue: isBrewInstallDone
                )

            case .brewPathDetected:
                BrewPathDetectedView(page: $page)
                    .transition(.push(from: .trailing))

                pageControlButtons(
                    nextPage: .allSet,
                    additionalLinks: [
                        PageLink(title: "Use different brew path", page: .brewPathSelection),
                        PageLink(title: "Install separate brew for Applite", page: .appliteBrewInstall)
                    ]
                )

            case .brewPathSelection:
                BrewPathSelection(isBrewPathValid: $isBrewPathValid)
                    .transition(.push(from: .trailing))

                pageControlButtons(nextPage: .allSet, canContinue: isBrewPathValid)

            case .allSet:
                AllSet()
                    .transition(.push(from: .trailing))
            }
        }
        .task {
            detectedBrewInstallation = await DependencyManager.detectHomebrew(setPathOption: true)
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
                .keyboardShortcut(.defaultAction)
            }
            .padding(.trailing)
            .padding(.bottom, 8)
        }
    }
}

#Preview {
    SetupView()
        .frame(width: 600, height: 400)
}
