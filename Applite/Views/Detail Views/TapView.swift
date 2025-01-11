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
            ScrollView {
                TapAppGridView(caskCollection: tap.caskCollection)
            }
        }
    }

    private struct TapAppGridView: View {
        @ObservedObject var caskCollection: SearchableCaskCollection
        @State var searchText = ""

        var body: some View {
            AppGridView(casks: caskCollection.casksMatchingSearch, appRole: .installAndManage)
                .padding()
                .searchable(text: $searchText, placement: .toolbar)
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
