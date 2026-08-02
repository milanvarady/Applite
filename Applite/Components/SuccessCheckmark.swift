//
//  SuccessCheckmark.swift
//  Applite
//
//  Created by Milán Várady on 2026.08.01.
//

import SwiftUI

/// A satisfying success badge for app-card actions, built from three coordinated layers:
/// a solid disc that springs in and stays, a checkmark that draws itself on top, and a lighter
/// ring that pulses outward once and fades away.
struct SuccessCheckmark: View {
    var color: Color = .green

    @State private var discScale: CGFloat = 0.001
    @State private var trim: CGFloat = 0
    @State private var pulseScale: CGFloat = 0.9
    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Pulse ring — expands past the disc edge and fades out.
            Circle()
                .stroke(color, lineWidth: 2)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            // Solid disc — grows in and stays.
            Circle()
                .fill(color)
                .scaleEffect(discScale)

            // Drawn checkmark — white for contrast, scaled with the disc so it never overflows.
            CheckmarkShape()
                .trim(from: 0, to: trim)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .scaleEffect(discScale)
                .padding(9)
        }
        .frame(width: 30, height: 30)
        .accessibilityElement()
        .accessibilityLabel(Text("Done", comment: "Accessibility label for the success checkmark"))
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                discScale = 1
            }
            withAnimation(.easeOut(duration: 0.28).delay(0.12)) {
                trim = 1
            }
            withAnimation(.easeOut(duration: 0.6)) {
                pulseScale = 1.8
                pulseOpacity = 0
            }
        }
    }
}

/// The classic short-leg / long-leg check, drawn in the unit rect so `trim` animates the draw.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0.16 * w, y: 0.53 * h))
        path.addLine(to: CGPoint(x: 0.42 * w, y: 0.76 * h))
        path.addLine(to: CGPoint(x: 0.84 * w, y: 0.28 * h))
        return path
    }
}

#Preview {
    SuccessCheckmark()
        .padding()
}
