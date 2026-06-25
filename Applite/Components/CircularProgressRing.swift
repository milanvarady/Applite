//
//  CircularProgressRing.swift
//  Applite
//
//  Created by Milán Várady on 2026.06.25.
//

import SwiftUI

/// A minimal, native-style determinate progress ring that follows the accent color.
///
/// Used for download progress on app cards. Renders a subtle track with an
/// accent-colored arc that fills clockwise with a rounded cap.
struct CircularProgressRing: View {
    /// Progress from 0 to 1.
    var progress: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        // Keep the rounded cap from clipping against the frame edge.
        .padding(lineWidth / 2)
    }
}

#Preview {
    CircularProgressRing(progress: 0.73)
        .frame(width: 30, height: 30)
        .padding()
}
