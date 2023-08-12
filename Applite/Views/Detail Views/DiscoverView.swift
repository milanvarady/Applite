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
    @Binding var navigationSelection: String
    @State var currentPage: Float = 0

    var body: some View {
        LazyVStack(alignment: .leading) {
            Text("Discover")
                .font(.system(size: 52, weight: .bold))
                .padding(.bottom)

            ForEach(categories) { category in
                DiscoverSection(category: category, navigationSelection: $navigationSelection)

                Divider()
                    .padding(.vertical, 20)
            }
        }
        .padding()
    }
}

/// Category section
private struct DiscoverSection: View {
    let category: Category
    @Binding var navigationSelection: String

    @EnvironmentObject var caskData: CaskData
    
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading) {
            // Category header
            HStack(alignment: .bottom) {
                Image(systemName: category.sfSymbol)
                    .font(.system(size: 24))

                Text(NSLocalizedString(category.id, comment: "String Category"))
                    .font(.system(size: 24, weight: .bold))

                Button("See All") {
                    navigationSelection = category.id
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                .padding(.bottom, 3)
            }
            
            // App row
            ScrollViewReader { proxy in
                // Backward button
                HStack {
                    Button(action: {
                        let appViewWidthWithPadding = AppView.dimensions.width + AppView.dimensions.spacing
                        let scrollTo: Int = Int(((scrollOffset - appViewWidthWithPadding) / appViewWidthWithPadding).rounded())
                        
                        withAnimation(.spring()) {
                            proxy.scrollTo(max(scrollTo, 0), anchor: .leading)
                        }
                    }) {
                        Image(systemName: "chevron.compact.left")
                            .font(.system(size: 38))
                    }
                    .buttonStyle(.plain)
                    .opacity(scrollOffset <= 0 ? 0.2 : 1)
                    
                    // App row
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
                        .onPreferenceChange(ViewOffsetKey.self) { scrollOffset = $0 }
                    }
                    .coordinateSpace(name: "\(category.id)Scroll")
                    
                    // Forward button
                    Button {
                        let appViewWidthWithPadding = AppView.dimensions.width + AppView.dimensions.spacing
                        let scrollTo: Int = Int(((scrollOffset + appViewWidthWithPadding) / appViewWidthWithPadding).rounded())
                        
                        withAnimation(.spring()) {
                            proxy.scrollTo(min(scrollTo, category.casks.count - 1), anchor: .leading)
                        }
                    } label: {
                        Image(systemName: "chevron.compact.right")
                            .font(.system(size: 38))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 15)
                }
            }
            .frame(height: AppView.dimensions.height * 2 + 20)
        }
    }
    
    /// Preference key used to get the scroll offset of the app row
    private struct ViewOffsetKey: PreferenceKey {
        typealias Value = CGFloat
        static var defaultValue = CGFloat.zero
        
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value += nextValue()
        }
    }
    
    /// Two placeholder app views on top of each other for the discover app row
    private struct PlaceholderAppGroup: View {
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

struct DiscoverView_Previews: PreviewProvider {
    static var previews: some View {
        DiscoverView(navigationSelection: .constant(""))
            .environmentObject(CaskData())
    }
}
