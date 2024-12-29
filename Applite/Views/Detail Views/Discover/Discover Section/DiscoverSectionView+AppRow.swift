//
//  DiscoverSectionView+AppRow.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension DiscoverSectionView {
    var appRowAndControls: some View {
        ScrollViewReader { proxy in
            HStack {
                // Backward button
                scrollButton(
                    icon: "chevron.compact.left",
                    proxy: proxy,
                    direction: -
                )
                .opacity(scrollOffset <= 0 ? 0.2 : 1)

                // App row
                appRow

                .coordinateSpace(name: "\(category.id)Scroll")

                // Forward button
                scrollButton(
                    icon: "chevron.compact.right",
                    proxy: proxy,
                    direction: +
                )
                .padding(.leading, 15)
            }
        }
    }

    private var appRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                if caskData.casksByCategoryCoupled[category.id]?.count ?? 0 > 0 {
                    ForEach(Array((caskData.casksByCategoryCoupled[category.id]?.enumerated())!), id: \.offset) { index, casks in
                        VStack {
                            ForEach(casks) { cask in
                                AppView(cask: cask, role: .installAndManage)
                                    .frame(width: AppView.dimensions.width, height: AppView.dimensions.height)
                            }

                            Spacer()
                        }
                        .id(index)
                    }
                } else {
                    // Placeholders
                    ForEach(0..<6) { _ in
                        PlaceholderAppGroup()
                    }
                }
            }.background(GeometryReader { geometry in
                Color.clear.preference(key: ViewOffsetKey.self,
                                       value: -geometry.frame(in: .named("\(category.id)Scroll")).origin.x)
            })
            .onPreferenceChange(ViewOffsetKey.self) { value in
                Task { @MainActor in
                    scrollOffset = value
                }
            }
        }
    }

    func scrollButton(icon: String, proxy: ScrollViewProxy, direction: (CGFloat, CGFloat) -> CGFloat) -> some View {
        // Calculate new scroll position
        let appViewWidthWithPadding = AppView.dimensions.width + AppView.dimensions.spacing
        let newScrollOffset = direction(scrollOffset, appViewWidthWithPadding)
        let scrollTo: Int = Int((newScrollOffset / appViewWidthWithPadding).rounded())
        let scrollUpperBound = category.casks.count - 1
        let scrollToClamped = min(max(scrollTo, 0), scrollUpperBound)

        return Button {
            withAnimation(.spring()) {
                proxy.scrollTo(scrollToClamped, anchor: .leading)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 38))
        }
        .buttonStyle(.plain)
    }
}
