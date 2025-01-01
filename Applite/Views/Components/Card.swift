//
//  Card.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import SwiftUI

/// A reusabe view that adds a rounded rectange background shadow
struct Card<Content: View>: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let paddig: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(paddig)
            .frame(width: cardWidth, height: cardHeight)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 3)
    }
}
