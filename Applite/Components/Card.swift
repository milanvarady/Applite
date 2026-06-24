//
//  Card.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import SwiftUI

/// A reusable view that adds a rounded rectangle background shadow
struct Card<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = 5, content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Take available space
            .padding(padding)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 3)
    }
}
