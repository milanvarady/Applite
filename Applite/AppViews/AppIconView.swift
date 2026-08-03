//
//  AppIconView.swift
//  Applite
//
//  Created by Milán Várady on 05/04/2024.
//

import SwiftUI
import Kingfisher
import Shimmer

struct AppIconView: View {
    @State private var iconFailed = false

    let iconURL: URL
    /// App display name — its first letter is shown in the monogram fallback.
    let name: String
    let cacheKey: String
    var size: CGFloat = 54

    private var cornerRadius: CGFloat { size * 0.2 }

    var body: some View {
        Group {
            if iconFailed {
                monogram
            } else {
                KFImage.url(iconURL, cacheKey: cacheKey)
                    .resizable()
                    .placeholder {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.gray)
                            .shimmering()
                    }
                    .fade(duration: 0.25)
                    .onFailure { _ in iconFailed = true }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }

    /// Deterministic letter-on-color tile shown when the remote icon can't be loaded. Replaces the
    /// old third-party favicon fallback: no network round-trip, no privacy leak, works offline, and
    /// reads as intentional rather than a broken image.
    private var monogram: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(monogramColor)
            .overlay {
                Text(monogramLetter)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
    }

    private var monogramLetter: String {
        name.first.map { String($0).uppercased() } ?? "?"
    }

    /// Stable, pleasant color seeded from the cache key so a given app always gets the same tile.
    private var monogramColor: Color {
        let hash = cacheKey.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 31) &+ UInt64($1.value) }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.6)
    }
}

#Preview {
    HStack(spacing: 16) {
        // Working icon
        AppIconView(
            iconURL: URL(string: "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/firefox.png")!,
            name: "Firefox",
            cacheKey: "caskflow-firefox"
        )
        // Monogram fallback (unresolvable URL)
        AppIconView(
            iconURL: URL(string: "https://example.invalid/nope.png")!,
            name: "Some App",
            cacheKey: "caskflow-some-app"
        )
    }
    .padding()
}
