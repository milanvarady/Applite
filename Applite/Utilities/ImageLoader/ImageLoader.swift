//
//  ImageLoader.swift
//  Applite
//
//  Created by Milán Várady on 2025.
//

import Foundation
import AppKit
import OSLog

/// Singleton actor that handles image downloading and caching with proxy support
actor ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let memoryCache = NSCache<NSString, NSImage>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ImageLoader")

    private init() {
        let config = NetworkProxyManager.getURLSessionConfiguration()
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,  // 50 MB memory
            diskCapacity: 200 * 1024 * 1024,    // 200 MB disk
            diskPath: "dev.aerolite.Applite.ImageCache"
        )
        self.session = URLSession(configuration: config)
        memoryCache.countLimit = 500
    }

    func loadImage(from url: URL, cacheKey: String) async throws -> NSImage {
        let key = cacheKey as NSString

        // Check memory cache first
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // Download
        let (data, _) = try await session.data(from: url)

        guard let image = NSImage(data: data) else {
            throw ImageLoaderError.invalidImageData
        }

        // Store in memory cache
        memoryCache.setObject(image, forKey: key)

        return image
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

enum ImageLoaderError: LocalizedError {
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Failed to decode image data"
        }
    }
}
