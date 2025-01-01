//
//  CategoryView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 11. 02..
//

import SwiftUI

/// Detail view used in the category section
struct CategoryView: View {
    let category: CategoryViewModel

    var body: some View {
        VStack(alignment: .leading) {
            // Category name
            Group {
                Text(category.name)
                    .font(.appliteMediumTitle)
                    .padding(.bottom, -20)
                
                Divider()
            }
            .padding()
            
            // Apps
            ScrollView {
                AppGridView(casks: category.casks, appRole: .installAndManage)
            }
        }
        
    }
}

#Preview {
    CategoryView(category:
        .init(
            name: "Test",
            sfSymbol: "star",
            casks: Array(repeating: .dummy, count: 8),
            casksCoupled: [Array(repeating: .dummy, count: 8)]
        )
    )
}
