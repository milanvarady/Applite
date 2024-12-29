//
//  DiscoverSectionView+OffsetKey.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension DiscoverSectionView {
    /// Preference key used to get the scroll offset of the app row
    struct ViewOffsetKey: PreferenceKey {
        typealias Value = CGFloat
        static let defaultValue = CGFloat.zero

        static func reduce(value: inout Value, nextValue: () -> Value) {
            value += nextValue()
        }
    }
}
