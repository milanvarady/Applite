//
//  CategoryView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 11. 02..
//

import SwiftUI

/// Detail view used in the category section
struct CategoryView: View {
    let category: CategoryLoadResult

    var body: some View {
        VStack(alignment: .leading) {
            // Category name
            Group {
                Text(category.localizedName)
                    .font(.appliteMediumTitle)
                    .padding(.bottom, -20)

                Divider()
            }
            .padding()

            // Apps
            AppGridView(casks: category.casks, appRole: .installAndManage)
                .id(category.id)
        }
        .navigationTitle(category.name)
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
