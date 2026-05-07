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
            AppGridView(casks: filteredCasks, appRole: .installed)
        }
        .navigationTitle("Installed")
        .modify { view in
            if #available(macOS 26.0, *) {
                view.searchable(text: $searchText, placement: .toolbarPrincipal)
            } else {
                view.searchable(text: $searchText, placement: .toolbar)
            }
        }
    }
}

struct InstalledView_Previews: PreviewProvider {
    static var previews: some View {
        InstalledView(casks: Array(repeating: .dummy, count: 8))
    }
}
