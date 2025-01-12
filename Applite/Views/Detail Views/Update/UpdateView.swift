//
//  UpdateView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI

/// Update section
struct UpdateView: View {
    @ObservedObject var caskCollection: SearchableCaskCollection

    @EnvironmentObject var caskManager: CaskManager

    @State var searchText = ""
    @State var refreshing = false
    @State var isUpdatingAll = false
    @State var updateAllButtonRotation = 0.0
    
    @State var showingGreedyUpdateConfirm = false
    @StateObject var loadAlert = AlertManager()

    var body: some View {
        VStack {
            if caskCollection.casks.isEmpty {
                updateUnavailable
                    .padding(.vertical)

                Spacer()
            } else {
                // App grid
                AppGridView(casks: caskCollection.casksMatchingSearch, appRole: .update)
                    .overlay(alignment: .bottom) {
                        if caskCollection.casksMatchingSearch.count > 1 {
                            updateAllButton
                                .shadow(radius: 8)
                                .padding(.vertical)
                        }
                    }
            }
        }
        .searchable(text: $searchText, placement: .toolbar)
        .task(id: searchText, debounceTime: .seconds(0.2)) {
            await caskCollection.search(query: searchText)
        }
        .toolbar {
            toolbarItems
        }
        .alertManager(loadAlert)
    }
}

struct UpdateView_Previews: PreviewProvider {
    static var previews: some View {
        UpdateView(
            caskCollection: .init(casks: Array(repeating: .dummy, count: 8))
        )
        .frame(width: 500, height: 400)
        .environmentObject(CaskManager())
    }
}
