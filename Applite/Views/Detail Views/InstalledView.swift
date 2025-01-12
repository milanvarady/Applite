//
//  InstalledView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import DebouncedOnChange

/// Shows installed apps, where the user can open and uninstall them
struct InstalledView: View {
    @ObservedObject var caskCollection: SearchableCaskCollection

    @State var searchText = ""

    var body: some View {
        VStack {
            AppGridView(casks: caskCollection.casksMatchingSearch, appRole: .installed)
        }
        .searchable(text: $searchText, placement: .toolbar)
        .task(id: searchText, debounceTime: .seconds(0.2)) {
            await caskCollection.search(query: searchText)
        }
    }
}

struct InstalledView_Previews: PreviewProvider {
    static var previews: some View {
        InstalledView(
            caskCollection: .init(casks: Array(repeating: .dummy, count: 8))
        )
    }
}
