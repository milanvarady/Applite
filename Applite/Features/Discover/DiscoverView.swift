//
//  DiscoverView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI

/// Shows apps in categories
struct DiscoverView: View {
    @Environment(CaskManager.self) var caskManager
    @Binding var navigationSelection: SidebarItem?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                Text("Discover", comment: "Discover view title")
                    .font(.appliteMediumTitle)
                    .padding(.bottom)

                ForEach(caskManager.categories) { category in
                    DiscoverSectionView(category: category, navigationSelection: $navigationSelection)

                    Divider()
                        .padding(.vertical, 20)
                }
            }
            .padding()
        }
    }
}

#Preview {
    DiscoverView(navigationSelection: .constant(.home as SidebarItem?))
}
