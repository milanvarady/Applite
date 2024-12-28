//
//  DiscoverSectionView+CategoryHeader.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension DiscoverSectionView {
    var categoryHeader: some View {
        HStack(alignment: .bottom) {
            Image(systemName: category.sfSymbol)
                .font(.system(size: 24))

            Text(LocalizedStringKey(category.id))
                .font(.system(size: 24, weight: .bold))

            Button("See All") {
                navigationSelection = category.id
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            .padding(.bottom, 3)
        }
    }
}
