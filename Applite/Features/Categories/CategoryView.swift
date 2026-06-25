//
//  CategoryView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 11. 02..
//

import SwiftUI
import Shimmer

/// Detail view used in the category section
struct CategoryView: View {
    let category: CategoryLoadResult

    @AppStorage(Preferences.categorySortOption) private var sortOption

    private let placeholderColumns = [GridItem(.adaptive(minimum: 320))]

    var body: some View {
        VStack(alignment: .leading) {
            // Category name
            Text(category.localizedName)
                .font(.appliteSmallTitle)
                .padding(.bottom, -20)
                .padding()

            if category.casks.isEmpty {
                placeholderGrid
                    .transition(.opacity)
            } else {
                AppGridView(casks: category.sortedCasks(by: sortOption), appRole: .installAndManage)
                    .id(category.id)
                    .transition(.opacity)
            }
        }
        .navigationTitle(category.name)
        .toolbar {
            CategorySortingToolbar()
        }
    }

    private var placeholderGrid: some View {
        ScrollView {
            LazyVGrid(columns: placeholderColumns, spacing: 20) {
                ForEach(0..<8, id: \.self) { _ in
                    PlaceholderAppView()
                        .shimmering()
                }
            }
            .padding()
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    CategoryView(category:
        CategoryLoadResult(
            id: "Test",
            sfSymbol: "star",
            casks: Array(repeating: .dummy, count: 8)
        )
    )
}
