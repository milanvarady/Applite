//
//  DiscoverSectionView+Placeholder.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI
import Shimmer

extension DiscoverSectionView {
    /// Two placeholder app views on top of each other for the discover app row
    struct PlaceholderAppGroup: View {
        var body: some View {
            VStack {
                PlaceholderAppView()
                    .shimmering()
                    .frame(width: AppView.dimensions.width, height: AppView.dimensions.height)

                PlaceholderAppView()
                    .shimmering()
                    .frame(width: AppView.dimensions.width, height: AppView.dimensions.height)
            }
        }
    }
}
