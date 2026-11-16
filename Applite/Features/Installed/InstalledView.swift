//
//  InstalledView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI

/// Shows installed apps, where the user can open and uninstall them
struct InstalledView: View {
    var casks: [CaskViewModel]
    var externalOnly = false

    @Environment(CaskManager.self) private var caskManager

    @State var searchText = ""

    /// Filtered casks based on local search text
    var filteredCasks: [CaskViewModel] {
        if searchText.isEmpty {
            return casks
        }
        let query = searchText.lowercased()
        return casks.filter {
            $0.name.lowercased().contains(query) || $0.token.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack {
            if externalOnly && casks.isEmpty && caskManager.isResolvingInstalledState {
                ProgressView()
            } else if externalOnly && casks.isEmpty {
                ContentUnavailableView(
                    "No externally installed apps detected.",
                    systemImage: "app.badge.checkmark"
                )
            } else if !searchText.isEmpty && filteredCasks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                AppGridView(casks: filteredCasks, appRole: externalOnly ? .installAndManage : .installed)
            }
        }
        .navigationTitle(externalOnly ? Text("Installed externally") : Text("Installed"))
        .searchable(text: $searchText, placement: .toolbar)
    }
}

#Preview {
    InstalledView(casks: Array(repeating: .dummy, count: 8))
}
