//
//  TapView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.09.
//

import SwiftUI

struct TapView: View {
    let tap: TapLoadResult

    @State var searchText = ""

    /// Filtered casks based on local search text
    var filteredCasks: [CaskViewModel] {
        if searchText.isEmpty {
            return tap.casks
        }
        let query = searchText.lowercased()
        return tap.casks.filter {
            $0.name.lowercased().contains(query) || $0.token.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            // Tap name
            Text(tap.title)
                .font(.appliteSmallTitle)
                .padding(.bottom, -20)
                .padding()

            // Apps
            AppGridView(casks: filteredCasks, appRole: .installAndManage)
        }
        .navigationTitle(tap.title)
        .searchable(text: $searchText, placement: .toolbar)
    }
}

#Preview {
    TapView(
        tap: TapLoadResult(id: "test/tap", casks: [])
    )
}
