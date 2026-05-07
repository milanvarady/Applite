//
//  UpdateView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI

/// Update section
struct UpdateView: View {
    var casks: [CaskViewModel]

    @Environment(CaskManager.self) var caskManager

    @State var searchText = ""
    @State var isUpdatingAll = false
    @State var updateAllButtonRotation = 0.0

    @State var showingGreedyUpdateConfirm = false
    @State var loadAlert = AlertManager()

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
            if casks.isEmpty {
                updateUnavailable
                    .padding(.vertical)

                Spacer()
            } else {
                // App grid
                AppGridView(casks: filteredCasks, appRole: .update)
                    .overlay(alignment: .bottom) {
                        if filteredCasks.count > 1 {
                            updateAllButton
                                .shadow(radius: 8)
                                .padding(.vertical)
                        }
                    }
            }
        }
        .navigationTitle("Update")
        .modify { view in
            if #available(macOS 26.0, *) {
                view.searchable(text: $searchText, placement: .toolbarPrincipal)
            } else {
                view.searchable(text: $searchText, placement: .toolbar)
            }
        }
        .toolbar {
            ToolbarItems(loadAlert: $loadAlert)
        }
        .alertManager($loadAlert)
    }
}

struct UpdateView_Previews: PreviewProvider {
    static var previews: some View {
        UpdateView(casks: Array(repeating: .dummy, count: 8))
            .frame(width: 500, height: 400)
    }
}
