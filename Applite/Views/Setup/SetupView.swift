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
    enum Pages {
        case welcome,
             brewTypeSelection,
             brewPathSelection,
             brewInstall,
             allSet
    }
    
    @State var page: Pages = .welcome
    
    @State var isBrewPathValid = false
    @State var isBrewInstallDone = false

    enum PushDirection {
        case forward, backward
    }

    @State var pushDirection: PushDirection = .forward

    var body: some View {
        VStack {
            switch page {
            case .welcome:
                Welcome()
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))
                
                PageControlButtons(
                    page: $page,
                    pushDirection: $pushDirection,
                    canContinue: true,
                    pageAfter: .brewTypeSelection,
                    pageBefore: nil
                )

            case .brewTypeSelection:
                BrewTypeSelection(page: $page)
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))

            case .brewPathSelection:
                BrewPathSelection(isBrewPathValid: $isBrewPathValid)
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))
                
                PageControlButtons(
                    page: $page,
                    pushDirection: $pushDirection,
                    canContinue: isBrewPathValid,
                    pageAfter: .allSet,
                    pageBefore: .brewTypeSelection
                )

            case .brewInstall:
                BrewInstall(isDone: $isBrewInstallDone)
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))
                
                PageControlButtons(
                    page: $page,
                    pushDirection: $pushDirection,
                    canContinue: isBrewInstallDone,
                    pageAfter: .allSet,
                    pageBefore: nil
                )

            case .allSet:
                AllSet()
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))
            }
        }
    }
}

struct SetupView_Previews: PreviewProvider {
    static var previews: some View {
        SetupView()
            .frame(width: 600, height: 400)
    }
}
