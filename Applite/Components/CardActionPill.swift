//
//  CardActionPill.swift
//  Applite
//
//  Created by Milán Várady on 2026.08.01.
//

import SwiftUI
import AppKit

extension View {
    /// Standard app-card action-pill styling: a calm accent-tinted capsule at rest that
    /// fills solid on hover (App Store style). Works on plain `Button` and ButtonKit's
    /// `AsyncButton` alike — apply it instead of a `.buttonStyle`.
    func cardActionPill() -> some View {
        modifier(CardActionPillModifier())
    }
}

/// Owns the hover state and applies the ``CardPillButtonStyle``.
private struct CardActionPillModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(CardPillButtonStyle(isHovering: hovering))
            .onHover { hovering = $0 }
    }
}

/// Capsule action pill: accent text on a faint accent wash at rest, white text on a solid
/// accent fill when hovered. Dims when disabled and nudges on press.
private struct CardPillButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(configuration: configuration, isHovering: isHovering)
    }

    private struct PillLabel: View {
        let configuration: Configuration
        let isHovering: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let active = isHovering && isEnabled

            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor.contrastingLabel : Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(active
                              ? AnyShapeStyle(Color.accentColor)
                              : AnyShapeStyle(Color.accentColor.opacity(0.15)))
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.snappy(duration: 0.15), value: isHovering)
                .animation(.snappy(duration: 0.1), value: configuration.isPressed)
        }
    }
}

private extension Color {
    /// Black or white — whichever stays legible when `self` is used as a solid fill.
    /// Keeps the hovered pill's label readable for light macOS accent colors (e.g. yellow),
    /// where a hardcoded white would wash out.
    var contrastingLabel: Color {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * srgb.redComponent
                      + 0.587 * srgb.greenComponent
                      + 0.114 * srgb.blueComponent
        return luminance > 0.6 ? .black : .white
    }
}
