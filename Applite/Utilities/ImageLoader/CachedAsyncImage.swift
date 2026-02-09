//
//  CachedAsyncImage.swift
//  Applite
//
//  Created by Milán Várady on 2025.
//

import SwiftUI

/// A SwiftUI view that loads and caches images asynchronously with proxy support
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL
    let cacheKey: String
    var onFailure: (() -> Void)?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .animation(.easeIn(duration: 0.25), value: image != nil)
        .task(id: url) {
            do {
                let loaded = try await ImageLoader.shared.loadImage(from: url, cacheKey: cacheKey)
                self.image = loaded
            } catch {
                loadFailed = true
                onFailure?()
            }
        }
    }
}

extension CachedAsyncImage {
    func onFailure(_ handler: @escaping () -> Void) -> CachedAsyncImage {
        var copy = self
        copy.onFailure = handler
        return copy
    }
}
