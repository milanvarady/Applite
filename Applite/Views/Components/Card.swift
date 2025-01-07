//
//  Card.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import SwiftUI

/// A reusabe view that adds a rounded rectange background shadow
struct Card<Content: View>: View {
    let paddig: CGFloat
    @ViewBuilder let content: Content

    init(paddig: CGFloat = 5, content: () -> Content) {
        self.paddig = paddig
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Take available space
            .padding(paddig)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 3)
    }
}
