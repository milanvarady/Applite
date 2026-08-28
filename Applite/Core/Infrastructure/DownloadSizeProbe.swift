//
//  DownloadSizeProbe.swift
//  Applite
//
//  Created by Milán Várady on 2026. 08. 28..
//

import Foundation
import OSLog

/// Asks a cask's download host how large its artifact is.
///
/// Homebrew does not record download sizes — neither the JSON API nor `brew info` carries one,
/// because a cask URL is not required to point at a stable static file. The only way to get a
/// size is to ask the server, so this makes the same request `brew install` would make moments
/// later, minus the body.
///
/// Two strategies, tried in order:
/// 1. `HEAD` and read `Content-Length` — answers the large majority of casks.
/// 2. A one-byte ranged `GET` and read the total out of `Content-Range` — recovers hosts that
///    answer `HEAD` with a bodyless `200` and no length.
///
/// Together they resolved 149 of a random 150 non-git casks; the one miss was a cask whose
/// upstream release asset had been deleted (a genuine `404`). What legitimately comes up empty
/// is mirror-selector URLs, which serve an HTML chooser rather than a file. Callers get `nil` and
/// should omit the size rather than show a zero.
///
/// This is only ever driven by an explicit user action (opening Get Info); it must not be used to
/// bulk-annotate a list, which would fan out a request per cask to a different vendor each time.
enum DownloadSizeProbe {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DownloadSizeProbe.self)
    )

    /// Long enough for a slow vendor host, short enough that the row doesn't spin forever.
    private static let timeout: TimeInterval = 10

    /// The size in bytes of the file `url` points at, or `nil` if the host won't say.
    static func size(of url: URL) async -> Int64? {
        // Git-clone casks (`url` ends in `.git`, always paired with a `branch` url spec) have no
        // downloadable artifact at all — 516 casks in the catalog. Don't even ask.
        guard url.pathExtension != "git" else { return nil }

        // One session for both strategies, invalidated on the way out. A `URLSession` retains
        // itself until told otherwise, so building one per request would strand two of them
        // every time Get Info is opened. It stays per-probe rather than a shared `static` so
        // that a proxy the user configures mid-session is picked up on the next probe.
        let session = URLSession(configuration: NetworkProxyManager.getURLSessionConfiguration())
        defer { session.finishTasksAndInvalidate() }

        if let size = await headSize(of: url, session: session) {
            return size
        }

        return await rangeSize(of: url, session: session)
    }

    // MARK: - Strategies

    /// `HEAD` the URL and trust `Content-Length`.
    private static func headSize(of url: URL, session: URLSession) async -> Int64? {
        var request = probeRequest(for: url)
        request.httpMethod = "HEAD"

        guard let (_, urlResponse) = try? await session.data(for: request),
              let response = urlResponse as? HTTPURLResponse,
              isDownload(response) else {
            return nil
        }

        return positive(response.expectedContentLength)
    }

    /// Ask for the first byte and read the total size out of `Content-Range`.
    ///
    /// Uses `bytes(for:)` rather than `data(for:)` so that a host which ignores `Range` and starts
    /// streaming the whole file is cancelled after its headers arrive instead of being downloaded
    /// in full — some of these artifacts are several hundred megabytes.
    private static func rangeSize(of url: URL, session: URLSession) async -> Int64? {
        var request = probeRequest(for: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        guard let (stream, urlResponse) = try? await session.bytes(for: request) else {
            return nil
        }

        // The body is only fetched as the sequence is iterated; never iterate it.
        defer { stream.task.cancel() }

        guard let response = urlResponse as? HTTPURLResponse, isDownload(response) else {
            return nil
        }

        // "bytes 0-0/975580733" — the total is what we're after. Some hosts send the header
        // alongside a 200 instead of a 206, so the status isn't worth being strict about.
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let totalField = range.split(separator: "/").last,
           let total = Int64(totalField),
           let size = positive(total) {
            return size
        }

        // Past this point Content-Range was missing or unparseable — `bytes 0-0/*` is legal when
        // the host doesn't know the total. On a 206 the length describes the single byte we asked
        // for, so reading it would report "1 byte"; only a 200 (a host that ignored Range and
        // started sending the whole file) carries a length worth having.
        guard response.statusCode != 206 else { return nil }

        return positive(response.expectedContentLength)
    }

    // MARK: - Helpers

    /// A request that asks for the artifact exactly as it will be stored on disk.
    ///
    /// `Accept-Encoding: identity` is the load-bearing part. URLSession advertises `gzip, deflate,
    /// br` by default, and a host that takes it up describes the *compressed transfer* in
    /// `Content-Length` — CFNetwork then reports `-1` rather than a length that would mean the
    /// wrong thing. Postman's CDN is one such host: identical request, `-1` with the default
    /// header and the true 152 MB with this one.
    private static func probeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    /// Whether the response looks like the artifact itself rather than a page about it.
    ///
    /// Mirror-selector URLs (Apache's `closer.lua`) answer `200` with a few kilobytes of HTML;
    /// reporting that as the download size would be far worse than reporting nothing.
    private static func isDownload(_ response: HTTPURLResponse) -> Bool {
        guard (200..<300).contains(response.statusCode) else {
            logger.info("Size probe got HTTP \(response.statusCode) for \(response.url?.absoluteString ?? "?")")
            return false
        }

        return response.mimeType?.hasPrefix("text/html") != true
    }

    /// `expectedContentLength` is `-1` when unknown, and some hosts answer `HEAD` with a `0`.
    private static func positive(_ length: Int64) -> Int64? {
        length > 0 ? length : nil
    }
}
