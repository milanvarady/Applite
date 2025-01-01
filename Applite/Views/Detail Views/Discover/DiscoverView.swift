//
//  DiscoverView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import Shimmer

/// Shows apps in categories
struct DiscoverView: View {
    @EnvironmentObject var caskManager: CaskManager
    @Binding var navigationSelection: SidebarItem
    @State var currentPage: Float = 0

    var body: some View {
        LazyVStack(alignment: .leading) {
            Text("Discover")
                .font(.appliteLargeTitle)
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

struct DiscoverView_Previews: PreviewProvider {
    static var previews: some View {
        DiscoverView(navigationSelection: .constant(.home))
            .environmentObject(CaskManager())
    }
}
