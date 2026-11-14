import Foundation

enum ReleaseNotesResolver {
    struct Source: Hashable, Sendable {
        let owner: String
        let repository: String
        let tags: [String]

        var historyURL: URL {
            URL(string: "https://github.com/\(owner)/\(repository)/releases")!
        }
    }

    struct Notes: Sendable {
        let tag: String
        let body: String
        let url: URL
    }

    struct Response: Sendable {
        let data: Data
        let status: Int
        let url: URL
    }

    enum Failure: LocalizedError {
        case invalidResponse
        case requestFailed(Int)
        case responseTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidResponse: String(localized: "The release notes response could not be verified.")
            case .requestFailed(let status): String(localized: "GitHub returned HTTP \(status).")
            case .responseTooLarge: String(localized: "The release notes response was too large.")
            }
        }
    }

    private struct Release: Decodable {
        let tag_name: String
        let body: String?
        let html_url: URL
        let draft: Bool
    }

    private struct APIReleaseIdentity {
        let owner: String
        let repository: String
        let tag: String
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            guard let source = response.url.flatMap(apiReleaseIdentity),
                  let destination = request.url.flatMap(apiReleaseIdentity),
                  source.tag == destination.tag else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    static func source(homepage: URL, download: URL, version: String?) -> Source? {
        let downloadComponents = githubComponents(download)
        let downloadParts = downloadComponents?.path.split(separator: "/").map(String.init) ?? []
        let releaseDownload = downloadParts.count >= 5
            && downloadParts[2] == "releases" && downloadParts[3] == "download"
        let parts: [String]
        if releaseDownload {
            parts = downloadParts
        } else if let homepage = githubComponents(homepage) {
            parts = homepage.path.split(separator: "/").map(String.init)
        } else {
            return nil
        }
        guard parts.count >= 2, validComponent(parts[0]), validComponent(parts[1]) else { return nil }
        let cleanVersion = version?.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        guard validTag(cleanVersion), cleanVersion.lowercased() != "latest" else {
            return Source(owner: parts[0], repository: parts[1], tags: [])
        }
        if releaseDownload {
            let tag = downloadParts[4]
            guard validTag(tag), normalized(tag) == normalized(cleanVersion) else {
                return Source(owner: parts[0], repository: parts[1], tags: [])
            }
            return Source(owner: parts[0], repository: parts[1], tags: [tag])
        }
        guard version == cleanVersion else {
            return Source(owner: parts[0], repository: parts[1], tags: [])
        }
        let tags = cleanVersion.hasPrefix("v") || cleanVersion.hasPrefix("V")
            ? [cleanVersion, String(cleanVersion.dropFirst())]
            : [cleanVersion, "v" + cleanVersion]
        return Source(owner: parts[0], repository: parts[1], tags: tags)
    }

    static func load(
        _ source: Source, fetch: @Sendable (URL) async throws -> Response
    ) async throws -> Notes? {
        for tag in source.tags {
            try Task.checkCancellation()
            guard let url = apiURL(source, tag: tag) else { throw Failure.invalidResponse }
            guard let requested = apiReleaseIdentity(url),
                  requested.owner.lowercased() == source.owner.lowercased(),
                  requested.repository.lowercased() == source.repository.lowercased(),
                  requested.tag == tag else {
                throw Failure.invalidResponse
            }
            let response = try await fetch(url)
            if (300..<400).contains(response.status) { return nil }
            guard let resolved = apiReleaseIdentity(response.url), resolved.tag == tag else {
                throw Failure.invalidResponse
            }
            if response.status == 404 { continue }
            guard response.status == 200 else { throw Failure.requestFailed(response.status) }
            let release = try JSONDecoder().decode(Release.self, from: response.data)
            guard !release.draft, release.tag_name == tag,
                  let components = githubComponents(release.html_url) else {
                throw Failure.invalidResponse
            }
            guard verifiedReleasePath(
                components.path, owner: resolved.owner, repository: resolved.repository, tag: tag
            ) else { return nil }
            let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Notes(tag: tag, body: body, url: release.html_url)
        }
        return nil
    }

    static func load(_ source: Source, configuration: URLSessionConfiguration) async throws -> Notes? {
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await load(source) { url in
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpShouldHandleCookies = false
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
                throw Failure.invalidResponse
            }
            if (300..<400).contains(response.statusCode) {
                return Response(data: Data(), status: response.statusCode, url: finalURL)
            }
            guard apiReleaseIdentity(finalURL) != nil else { throw Failure.invalidResponse }
            var data = Data()
            if response.statusCode == 200 {
                for try await byte in bytes {
                    guard data.count < 256 * 1024 else { throw Failure.responseTooLarge }
                    data.append(byte)
                }
            }
            return Response(data: data, status: response.statusCode, url: finalURL)
        }
    }

    private static func githubComponents(_ url: URL) -> URLComponents? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.host?.lowercased() == "github.com",
              components.user == nil, components.password == nil, components.port == nil else { return nil }
        return components
    }

    private static func isAPIURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https" && components.host?.lowercased() == "api.github.com"
            && components.user == nil && components.password == nil && components.port == nil
    }

    private static func apiReleaseIdentity(_ url: URL) -> APIReleaseIdentity? {
        guard isAPIURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.query == nil, components.fragment == nil else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 7, parts[0].isEmpty,
              parts[1] == "repos", parts[4] == "releases", parts[5] == "tags" else { return nil }
        let owner = String(parts[2])
        let repository = String(parts[3])
        let tag = String(parts[6])
        guard validComponent(owner), validComponent(repository), validTag(tag) else { return nil }
        return APIReleaseIdentity(owner: owner, repository: repository, tag: tag)
    }

    private static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-").contains($0) }
    }

    private static func validTag(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-+").contains($0)
            }
            && !normalized(value).isEmpty && value.count <= 100
    }

    private static func verifiedReleasePath(
        _ path: String, owner: String, repository: String, tag: String
    ) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return false }
        return parts[0].isEmpty
            && parts[1].lowercased() == owner.lowercased()
            && parts[2].lowercased() == repository.lowercased()
            && parts[3] == "releases" && parts[4] == "tag" && parts[5] == tag
    }

    private static func normalized(_ value: String) -> String {
        value.hasPrefix("v") || value.hasPrefix("V") ? String(value.dropFirst()) : value
    }

    private static func apiURL(_ source: Source, tag: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(source.owner)/\(source.repository)/releases/tags/\(tag)")
    }
}
