import Foundation
import OSLog

actor FaviconResolver {
    static let shared = FaviconResolver()

    private struct Cached {
        let urls: [URL]
        let expires: Date
    }

    private struct RequestKey: Hashable {
        let homepage: URL
        let proxy: NSDictionary
    }

    private var cache: [RequestKey: Cached] = [:]
    private var pending: [RequestKey: Task<[URL], Never>] = [:]
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Applite",
        category: "FaviconResolver"
    )
    static let maximumHTMLBytes = 128 * 1024

    func candidates(for homepage: URL, configuration: URLSessionConfiguration) async -> [URL] {
        guard let homepage = Self.httpURL(homepage) else {
            Self.logger.info("Skipping favicon discovery for an unsupported homepage URL")
            return []
        }
        let key = RequestKey(homepage: homepage, proxy: NSDictionary(dictionary: configuration.connectionProxyDictionary ?? [:]))
        if let cached = cache[key], cached.expires > Date() {
            return cached.urls
        }
        if let task = pending[key] {
            return await task.value
        }

        let task = Task { await Self.discover(homepage, configuration: configuration) }
        pending[key] = task
        let urls = await task.value
        pending[key] = nil
        if cache.count >= 256, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[key] = Cached(urls: urls, expires: Date().addingTimeInterval(300))
        return urls
    }

    private static func discover(_ homepage: URL, configuration: URLSessionConfiguration) async -> [URL] {
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: homepage, timeoutInterval: 8)
        request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false

        var pageURL = homepage
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            pageURL = response.url.flatMap(httpURL) ?? homepage
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  response.mimeType == "text/html" || response.mimeType == "application/xhtml+xml" else {
                logger.info("Favicon homepage did not return usable HTML: \(homepage.absoluteString)")
                return candidates(in: "", pageURL: pageURL)
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maximumHTMLBytes { break }
            }
            return candidates(in: String(decoding: data, as: UTF8.self), pageURL: pageURL)
        } catch {
            logger.info("Favicon discovery failed for \(homepage.absoluteString): \(error.localizedDescription)")
            return candidates(in: "", pageURL: pageURL)
        }
    }

    static func candidates(in html: String, pageURL: URL) -> [URL] {
        guard let pageURL = httpURL(pageURL) else { return [] }
        let tags = html.matches(of: #/(?is)<!--.*?(?:-->|$)|<script\b(?:[^"'<>]|"[^"]*"|'[^']*')*>.*?(?:</script\s*>|$)|<style\b(?:[^"'<>]|"[^"]*"|'[^']*')*>.*?(?:</style\s*>|$)|<(?:[^"'<>]|"[^"]*"|'[^']*')*>/#)
            .prefix { $0.0.wholeMatch(of: #/(?i)</head\s*>/#) == nil }
            .compactMap { $0.0.wholeMatch(of: #/(?is)<(link|base)\b(?:[^"'<>]|"[^"]*"|'[^']*')*>/#) }
        var baseURL = pageURL
        if let base = tags.first(where: {
            $0.1.lowercased() == "base" && attributes(in: String($0.0))["href"] != nil
        }),
           let href = attributes(in: String(base.0))["href"],
           let resolved = URL(string: href, relativeTo: pageURL)?.absoluteURL,
           let url = httpURL(resolved) {
            baseURL = url
        }
        var icons: [(url: URL, priority: Int)] = []
        for tag in tags where tag.1.lowercased() == "link" {
            let attributes = attributes(in: String(tag.0))
            let rel = Set((attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            guard rel.contains("icon") || rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed"),
                  let href = attributes["href"],
                  let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  let url = httpURL(resolved) else { continue }
            let svg = attributes["type"]?.lowercased() == "image/svg+xml" || url.pathExtension.lowercased() == "svg"
            let priority = svg ? 2 : (rel.contains("icon") ? 0 : 1)
            icons.append((url, priority))
        }
        var result: [URL] = []
        var seen: Set<URL> = []
        for icon in icons.enumerated().sorted(by: {
            $0.element.priority == $1.element.priority
                ? $0.offset < $1.offset
                : $0.element.priority < $1.element.priority
        }) where seen.insert(icon.element.url).inserted {
            result.append(icon.element.url)
            if result.count == 3 { break }
        }
        if let root = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL,
           seen.insert(root).inserted {
            result.append(root)
        }
        return result
    }

    private static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for attribute in tag.matches(of: #/([a-zA-Z][\w:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/#) {
            if let value = attribute.2 ?? attribute.3 ?? attribute.4,
               let decoded = decodedAttribute(String(value)) {
                result[attribute.1.lowercased()] = decoded
            }
        }
        return result
    }

    private static func decodedAttribute(_ value: String) -> String? {
        guard value.contains("&") else { return value }
        let punctuation = [
            "sol": 47, "bsol": 92, "colon": 58, "period": 46, "quest": 63, "num": 35,
            "equals": 61, "percnt": 37, "commat": 64, "plus": 43, "lowbar": 95,
            "lpar": 40, "rpar": 41, "comma": 44, "semi": 59, "apos": 39, "excl": 33,
            "dollar": 36, "ast": 42, "Tab": 9, "NewLine": 10
        ]
        let references = value.replacing(#/&([A-Za-z][A-Za-z0-9]+);/#) { match in
            punctuation[String(match.1)].map { "&#\($0);" } ?? String(match.0)
        }
        let escaped = references.replacingOccurrences(of: "\"", with: "&#34;")
            .replacingOccurrences(of: "<", with: "&#60;")
        do {
            // An inert link gives Foundation's HTML decoder an attribute context without loading entities.
            let document = try XMLDocument(
                xmlString: "<html><body><a href=\"\(escaped)\">icon</a></body></html>",
                options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]
            )
            guard let decoded = try document.nodes(forXPath: "//@href").first?.stringValue else {
                logger.info("Favicon attribute could not be decoded")
                return nil
            }
            return decoded
        } catch {
            logger.info("Favicon attribute decoding failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func httpURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        components.fragment = nil
        return components.url
    }
}
