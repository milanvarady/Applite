//
//  DiscoverSectionView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct DiscoverSectionView: View {
    let category: CategoryLoadResult
    @Binding var navigationSelection: SidebarItem

    @Environment(CaskManager.self) var caskManager

    /// Index of the leading visible column in the horizontal scroll view.
    /// Updated by SwiftUI as the user scrolls; mutated by the arrow buttons.
    @State var scrollPosition: Int? = 0

    /// Width of the scroll view, observed via `GeometryReader`. Used by the arrow
    /// buttons to clamp `scrollPosition` to the last achievable leading index —
    /// `count - 1` overshoots when several columns fit on screen, leaving
    /// "phantom" positions you have to click back through before motion resumes.
    @State var scrollViewWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading) {
            categoryHeader

            appRowAndControls
                .frame(height: AppView.dimensions.height * 2 + 20)
        }
    }
}
