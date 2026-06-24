//
//  AppGridView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 03..
//

import SwiftUI

/// Displays a list of ``CaskViewModel`` objects in a flexible grid
///
/// - Parameters:
///   - casks: List of ``CaskViewModel`` objects to display
///   - appRole: Role of the casks displayed
struct AppGridView: View {
    let casks: [CaskViewModel]
    var appRole: AppRole

    let columns = [
        GridItem(.adaptive(minimum: 320))
    ]

    var body: some View {
        // Filter out self; done once per body pass rather than as a per-row
        // conditional inside ForEach (which wraps every row in _ConditionalContent).
        let displayedCasks = casks.filter { $0.token != "applite" }

        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                if appRole == .installed {
                    AppliteAppView()
                }

                ForEach(displayedCasks) { cask in
                    AppView(cask: cask, role: appRole)
                }
            }
            .padding()
        }
    }
}

#Preview {
    AppGridView(casks: Array(repeating: .dummy, count: 8), appRole: .installAndManage)
}
