//
//  CategoryView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 11. 02..
//

import SwiftUI

/// Detail view used in the category section
struct CategoryView: View {
    let category: Category
    @EnvironmentObject var caskData: CaskData

    var body: some View {
        VStack(alignment: .leading) {
            // Category name
            Group {
                Text(LocalizedStringKey(category.id))
                    .font(.system(size: 42, weight: .bold))
                    .padding(.bottom, -20)
                
                Divider()
            }
            .padding()
            
            // Apps
            ScrollView {
                AppGridView(casks: caskData.casksByCategory[category.id] ?? [], appRole: .installAndManage)
            }
        }
        
    }
}

struct CategoryView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryView(category: categories[0])
    }
}
