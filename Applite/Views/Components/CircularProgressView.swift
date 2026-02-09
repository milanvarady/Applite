//
//  CircularProgressView.swift
//  Applite
//
//  Created by Milán Várady on 2025.
//

import SwiftUI

/// A circular progress indicator that displays a percentage
struct CircularProgressView: View {
    let progress: Double
    var lineWidth: CGFloat = 4
    var font: Font = .system(size: 14, weight: .black)

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(.gray.opacity(0.3), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .foregroundStyle(.tint)
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: progress)

            // Percentage text
            Text("\(Int(progress * 100))%")
                .font(font)
        }
    }
}
