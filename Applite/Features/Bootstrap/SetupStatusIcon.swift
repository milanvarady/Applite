//
//  SetupStatusIcon.swift
//  Applite
//
//  Created by Milán Várady on 2025.07.09.
//

import SwiftUI

/// The morphing status glyph at the top of `ComponentsInstallView`.
///
/// Extracted into its own view on purpose: it takes only `phase`, so SwiftUI re-renders it *only*
/// when the phase changes — NOT on every streamed `statusLine` update the parent observes. That
/// keeps the repeating animation from restarting and keeps the `.replace` glyph morph clean.
struct SetupStatusIcon: View {
    let phase: HomebrewBootstrap.Phase

    /// Drives the breathing animation. We use a manual `scaleEffect` + `repeatForever` rather than
    /// `.symbolEffect(.pulse)`: pulse only fades opacity (barely visible on a filled glyph), and
    /// `.symbolEffect(.bounce, isActive:)` is macOS 15+. Starts `false` and flips on in `.onAppear`
    /// so the `false → true` change actually kicks the repeat-forever animation off.
    @State private var breathing = false

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 42))
            .foregroundStyle(iconColor)
            // Cross-fade/replace between the download, checkmark, and warning glyphs.
            .contentTransition(.symbolEffect(.replace))
            // Gentle continuous scale pulse while installing. `scaleEffect` is a render transform,
            // so it never changes layout or clips against the fixed icon slot.
            .scaleEffect(breathing ? 1.14 : 1.0)
            // Replace/color morph on phase change.
            .animation(.smooth, value: phase)
            // Breathing: repeat-forever while active, a quick non-repeating settle when it stops.
            .animation(
                breathing
                    ? .easeInOut(duration: 0.75).repeatForever(autoreverses: true)
                    : .easeOut(duration: 0.25),
                value: breathing
            )
            .onAppear { breathing = isInstalling }
            .onChange(of: isInstalling) { _, installing in breathing = installing }
    }

    private var iconName: String {
        switch phase {
        case .installed: "checkmark.circle.fill"
        case .failed, .brewMissing: "exclamationmark.triangle.fill"
        default: "arrow.down.circle.fill"
        }
    }

    private var iconColor: Color {
        switch phase {
        case .installed: .green
        case .failed, .brewMissing: .orange
        default: .accentColor
        }
    }

    private var isInstalling: Bool {
        switch phase {
        case .installed, .failed, .brewMissing: false
        default: true
        }
    }
}
