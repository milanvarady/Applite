//
//  TapView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.09.
//

import SwiftUI

struct TapView: View {
    let tap: TapViewModel

    var body: some View {
        VStack(alignment: .leading) {
            // Tap name
            Group {
                Text(tap.title)
                    .font(.appliteMediumTitle)
                    .padding(.bottom, -20)

                Divider()
            }
            .padding()

            // Apps
            TapAppGridView(caskCollection: tap.caskCollection)
        }
        .navigationTitle(tap.title)
    }

    private struct TapAppGridView: View {
        @ObservedObject var caskCollection: SearchableCaskCollection
        @State var searchText = ""

        var body: some View {
            AppGridView(casks: caskCollection.casksMatchingSearch, appRole: .installAndManage)
                .modify { view in
                    if #available(macOS 26.0, *) {
                        view.searchable(text: $searchText, placement: .toolbarPrincipal)
                    } else {
                        view.searchable(text: $searchText, placement: .toolbar)
                    }
                }
                .task(id: searchText, debounceTime: .seconds(0.2)) {
                    await caskCollection.search(query: searchText)
                }
        }
    }
}

#Preview {
    TapView(
        tap: .init(tapId: "test", caskCollection: .init(casks: []))
    )
}
