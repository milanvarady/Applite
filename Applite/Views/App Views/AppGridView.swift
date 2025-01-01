//
//  AppGridView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 03..
//

import SwiftUI

/// Displays a list of ``Cask`` objects in a flexible grid
///
/// - Parameters:
///   - casks: List of ``Cask`` object to display
///   - appRole: Role of the casks displayed
struct AppGridView: View {
    let casks: [Cask]
    var appRole: AppRole
    
    let columns = [
        GridItem(.adaptive(minimum: 320))
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            if appRole == .installed {
                AppliteAppView()
            }
            
            ForEach(casks) { cask in
                // Filter out self
                if cask.info.id != "applite" {
                    AppView(cask: cask, role: appRole)
                }
            }
        }
    }
}

#Preview {
    AppGridView(casks: Array(repeating: .dummy, count: 8), appRole: .installAndManage)
}
