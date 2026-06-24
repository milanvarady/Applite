//
//  DiscoverSectionView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct DiscoverSectionView: View {
    let category: CategoryLoadResult
    @Binding var navigationSelection: SidebarItem?

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

    var categoryHeader: some View {
        HStack(alignment: .bottom) {
            let fontSize: CGFloat = 24

            Image(systemName: category.sfSymbol)
                .font(.system(size: fontSize))

            Text(category.localizedName)
                .font(.system(size: fontSize, weight: .bold))

            Button("See All") {
                navigationSelection = .appCategory(id: category.id)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.bottom, 3)
        }
    }

    var appRowAndControls: some View {
        HStack {
            // Backward button
            scrollButton(icon: "chevron.compact.left", direction: -1)
                .opacity((scrollPosition ?? 0) <= 0 ? 0.2 : 1)

            // App row
            appRow

            // Forward button
            scrollButton(icon: "chevron.compact.right", direction: 1)
                .opacity((scrollPosition ?? 0) >= maxLeadingIndex ? 0.2 : 1)
                .padding(.leading, 15)
        }
    }

    private var appRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                if category.casksCoupled.count > 0 {
                    ForEach(Array(category.casksCoupled.enumerated()), id: \.offset) { index, casks in
                        VStack {
                            ForEach(casks) { cask in
                                AppView(cask: cask, role: .installAndManage)
                                    .frame(width: AppView.dimensions.width, height: AppView.dimensions.height)
                            }

                            Spacer()
                        }
                    }
                    .transition(.opacity)
                } else {
                    // Placeholders
                    ForEach(0..<6, id: \.self) { _ in
                        PlaceholderAppGroup()
                    }
                    .transition(.opacity)
                }
            }
            .scrollTargetLayout()
            // Force a clean rebuild when transitioning placeholder → loaded so
            // `.scrollTargetLayout()` doesn't hold onto stale child identities.
            .id(category.casksCoupled.isEmpty)
        }
        .scrollTargetBehavior(.viewAligned)
        // `anchor: .leading` makes each scrollPosition change push that item to
        // the leading edge. Without it, the scroll view skips the move when the
        // target is already visible — so clicking next 3 times when 3 items
        // fit on screen would do nothing until the 4th click.
        .scrollPosition(id: $scrollPosition, anchor: .leading)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { scrollViewWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        scrollViewWidth = newWidth
                    }
            }
        )
    }

    /// The last `scrollPosition` index for which the scroll view can physically scroll.
    /// `casksCoupled.count - 1` over-shoots when several columns fit on screen — once
    /// the scroll view is at its trailing limit, further `scrollPosition` increments
    /// don't move anything and you'd have to click back through the phantom values.
    private var maxLeadingIndex: Int {
        let columnWidth = AppView.dimensions.width + AppView.dimensions.spacing
        guard columnWidth > 0, scrollViewWidth > 0 else {
            return max(0, category.casksCoupled.count - 1)
        }
        let visibleColumns = max(1, Int(scrollViewWidth / columnWidth))
        return max(0, category.casksCoupled.count - visibleColumns)
    }

    func scrollButton(icon: String, direction: Int) -> some View {
        Button {
            let new = min(max(0, (scrollPosition ?? 0) + direction), maxLeadingIndex)
            withAnimation(.spring()) {
                scrollPosition = new
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 38))
        }
        .buttonStyle(.plain)
    }
}
