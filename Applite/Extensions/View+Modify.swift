//
//  View+Modify.swift
//  Applite
//
//  Created by Milán Várady on 2025.10.10.
//

import SwiftUI

extension View {
    func modify<T: View>(@ViewBuilder _ modifier: (Self) -> T) -> some View {
        return modifier(self)
    }
}

