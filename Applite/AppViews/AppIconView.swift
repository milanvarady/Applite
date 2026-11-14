//
//  AppIconView.swift
//  Applite
//
//  Created by Milán Várady on 05/04/2024.
//

import SwiftUI
import Kingfisher
import Shimmer
import OSLog

struct AppIconView: View {
    @State private var iconFailed = false
    @State private var faviconURLs: [URL] = []
    @State private var faviconFailed = false
    @Environment(\.displayScale) private var displayScale
    @AppStorage(Preferences.networkProxyEnabled) private var proxyEnabled
    @AppStorage(Preferences.preferredProxyType) private var preferredProxyType

    let iconURL: URL
    /// App display name — its first letter is shown in the monogram fallback.
    let name: String
    let cacheKey: String
    var homepageURL: URL? = nil
    var size: CGFloat = 54

    private var cornerRadius: CGFloat { size * 0.2 }
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Applite", category: "AppIconView")
    @MainActor private static var cachedFaviconDownloader: ImageDownloader?

    @MainActor
    static func faviconDownloader(configuration: URLSessionConfiguration) -> ImageDownloader {
        if let downloader = cachedFaviconDownloader,
           NSDictionary(dictionary: downloader.sessionConfiguration.connectionProxyDictionary ?? [:])
            .isEqual(to: configuration.connectionProxyDictionary ?? [:]) {
            return downloader
        }
        let downloader = ImageDownloader(name: "website-favicons")
        downloader.downloadTimeout = 8
        downloader.sessionConfiguration = configuration
        cachedFaviconDownloader = downloader
        return downloader
    }

    private var proxyPreferenceID: [String] { [String(proxyEnabled), preferredProxyType.rawValue] }

    var body: some View {
        Group {
            if iconFailed {
                if let url = faviconURLs.first, !faviconFailed {
                    KFImage.url(url, cacheKey: "website-favicon-\(url.absoluteString)")
                        .alternativeSources(faviconURLs.dropFirst().map {
                            .network(KF.ImageResource(downloadURL: $0, cacheKey: "website-favicon-\($0.absoluteString)"))
                        })
                        .downloader(Self.faviconDownloader(configuration: Self.websiteConfiguration()))
                        .setProcessor(DownsamplingImageProcessor(size: CGSize(width: size * displayScale, height: size * displayScale)))
                        .resizable()
                        .placeholder { monogram }
                        .fade(duration: 0.25)
                        .onFailure { error in
                            Self.logger.info("Website icons failed for \(cacheKey): \(error.localizedDescription)")
                            faviconFailed = true
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .id(proxyPreferenceID)
                } else {
                    monogram
                }
            } else {
                KFImage.url(iconURL, cacheKey: cacheKey)
                    .resizable()
                    .placeholder {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.gray)
                            .shimmering()
                    }
                    .fade(duration: 0.25)
                    .onFailure { error in
                        Self.logger.info("Primary app icon failed for \(cacheKey): \(error.localizedDescription)")
                        iconFailed = true
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .frame(width: size, height: size)
        .task(id: [iconFailed ? homepageURL?.absoluteString ?? "" : ""] + proxyPreferenceID) {
            guard iconFailed, let homepageURL else { return }
            let urls = await FaviconResolver.shared.candidates(for: homepageURL, configuration: Self.websiteConfiguration())
            guard !Task.isCancelled else { return }
            faviconURLs = urls
            faviconFailed = false
        }
    }

    private static func websiteConfiguration() -> URLSessionConfiguration {
        let configuration = NetworkProxyManager.getURLSessionConfiguration()
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 12
        return configuration
    }

    /// Offline last resort while website icons load, or when every image source fails.
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
