import Foundation
import ImageIO

private final class FaviconResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var callbacks: [@Sendable () -> Void] = []

    func submit(_ callback: @escaping @Sendable () -> Void) {
        lock.lock()
        if released {
            lock.unlock()
            callback()
        } else {
            callbacks.append(callback)
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        released = true
        let pending = callbacks
        callbacks = []
        lock.unlock()
        pending.forEach { $0() }
    }
}

private final class FaviconFixtures: @unchecked Sendable {
    struct Response: Sendable {
        let body: Data
        let mime: String
        let status: Int
        let finalURL: URL?
        let gate: FaviconResponseGate?
        let failBody: Bool
    }

    private let lock = NSLock()
    private var responses: [URL: Response] = [:]
    private var requests: [URL: Int] = [:]

    func set(
        _ url: URL, html: String, mime: String = "text/html", status: Int = 200,
        finalURL: URL? = nil, gate: FaviconResponseGate? = nil, failBody: Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }
        responses[url] = Response(body: Data(html.utf8), mime: mime, status: status, finalURL: finalURL, gate: gate, failBody: failBody)
    }

    func take(_ url: URL) -> Response? {
        lock.lock()
        defer { lock.unlock() }
        requests[url, default: 0] += 1
        return responses[url]
    }

    func count(_ url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests[url, default: 0]
    }
}

private final class FaviconURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = FaviconFixtures()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let fixture = Self.fixtures.take(url),
              let response = HTTPURLResponse(
                url: fixture.finalURL ?? url, statusCode: fixture.status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": fixture.mime]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let complete: @Sendable () -> Void = { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: fixture.body)
            if fixture.failBody {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in
                    client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                }
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        if let gate = fixture.gate {
            gate.submit(complete)
        } else {
            complete()
        }
    }

    override func stopLoading() {}
}

@main
enum FaviconResolverTests {
    static func main() async throws {
        let page = URL(string: "https://example.invalid/docs/app")!
        let html = """
        <HEAD>
        <!-- <link rel=icon href="comment.png"> -->
        <script>const text = '<link rel=icon href="script.png">';</script>
        <link HREF='logo.png?theme=dark&amp;size=64' REL='shortcut ICON'>
        <link href="//static.example.invalid/touch.png" rel=apple-touch-icon>
        <link rel=icon href="file:///tmp/not-an-icon.png">
        <link rel=icon href="data:image/png;base64,AA==">
        <link rel=icon href="https://fixture:password@example.invalid/private.ico">
        <link rel=icon href='logo.png?theme=dark&#38;size=64'>
        <base href="/assets/">
        </HEAD><link rel=icon href="body.png">
        """
        precondition(FaviconResolver.candidates(in: html, pageURL: page).map(\.absoluteString) == [
            "https://example.invalid/assets/logo.png?theme=dark&size=64",
            "https://static.example.invalid/touch.png",
            "https://example.invalid/favicon.ico"
        ])
        let ranked = """
        <link rel=icon type=image/svg+xml href=/vector.svg>
        <link rel=apple-touch-icon href=/touch.png>
        <link rel=icon href=/first.png>
        <link rel=icon href=/second.ico>
        <link rel=icon href=/third.png>
        """
        precondition(FaviconResolver.candidates(in: ranked, pageURL: page).map(\.path) == [
            "/first.png", "/second.ico", "/third.png", "/favicon.ico"
        ])
        precondition(FaviconResolver.candidates(in: "<link rel=icon href=/favicon.ico>", pageURL: page).count == 1)
        precondition(FaviconResolver.candidates(in: "", pageURL: URL(fileURLWithPath: "/tmp/fixture")).isEmpty)
        let misleadingHead = """
        <head><!-- </head> --><script>const text = "</head>";</script>
        <style>.example::after { content: "</head>"; }</style>
        <base target="_blank"><base href="/assets/">
        <link rel=icon href="app.png"></head><link rel=icon href="/body.png">
        """
        precondition(FaviconResolver.candidates(in: misleadingHead, pageURL: page).map(\.path) == [
            "/assets/app.png", "/favicon.ico"
        ], "Head-like text in ignored regions and target-only bases must not hide a valid icon")
        let quotedHead = """
        <head><meta content="The </head> element"><link rel=icon href="/right.png">
        </head><link rel=icon href="/wrong.png">
        """
        precondition(FaviconResolver.candidates(in: quotedHead, pageURL: page).map(\.path) == [
            "/right.png", "/favicon.ico"
        ], "Head-like text inside quoted attributes must not close the head")
        let quotedTags = """
        <head><meta content='<base href="https://other.invalid/"><link rel="icon" href="/wrong.png">'>
        <link rel=icon href="right.png"></head>
        """
        precondition(FaviconResolver.candidates(in: quotedTags, pageURL: page).map(\.absoluteString) == [
            "https://example.invalid/docs/right.png", "https://example.invalid/favicon.ico"
        ], "Tag-like text in quoted attributes must not alter icon discovery")
        let quotedIgnoredMarkers = """
        <head><meta content="Use <script> and <!-- comment --> markup">
        <link rel=icon href="/assets/real.png"></head>
        """
        precondition(FaviconResolver.candidates(in: quotedIgnoredMarkers, pageURL: page).map(\.path) == [
            "/assets/real.png", "/favicon.ico"
        ], "Ignored-region markers inside quoted attributes must not hide valid icon links")
        let references = """
        <base href="&#47;assets&#x2f;">
        <link rel=icon href="favicon&copy;.png?x=1&amp;y=&quot;q&quot;">
        <link rel=icon href="&sol;other&sol;icon&period;png">
        """
        let decoded = FaviconResolver.candidates(in: references, pageURL: page)
        precondition(decoded.first?.path == "/assets/favicon\u{00a9}.png")
        precondition(decoded.first?.query == "x=1&y=%22q%22")
        precondition(decoded.dropFirst().first?.path == "/other/icon.png")
        precondition(FaviconResolver.candidates(
            in: "<link rel=icon href='javascript&#58;alert(1)'>", pageURL: page
        ).map(\.path) == ["/favicon.ico"], "Decoded URLs must still pass scheme checks")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconURLProtocol.self]
        configuration.urlCache = nil
        let resolver = FaviconResolver()
        let redirected = URL(string: "https://new.example.invalid/releases/latest/")!
        let brokenBody = URL(string: "https://example.invalid/broken-body")!
        FaviconURLProtocol.fixtures.set(brokenBody, html: "x", finalURL: redirected, failBody: true)
        let bodyFallback = await resolver.candidates(for: brokenBody, configuration: configuration)
        precondition(bodyFallback.map(\.absoluteString) == ["https://new.example.invalid/favicon.ico"],
                     "A response-body failure must retain the final response origin")
        FaviconURLProtocol.fixtures.set(page, html: "<link rel=icon href=logo.png>", finalURL: redirected)
        async let first = resolver.candidates(for: page, configuration: configuration)
        async let second = resolver.candidates(for: page, configuration: configuration)
        let results = await (first, second)
        precondition(results.0 == results.1)
        precondition(results.0.first?.absoluteString == "https://new.example.invalid/releases/latest/logo.png")
        _ = await resolver.candidates(for: page, configuration: configuration)
        precondition(FaviconURLProtocol.fixtures.count(page) == 1, "Concurrent and cached callers must share discovery")
        let httpProxy = URLSessionConfiguration.ephemeral
        httpProxy.protocolClasses = [FaviconURLProtocol.self]
        httpProxy.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 8079]
        let socksProxy = URLSessionConfiguration.ephemeral
        socksProxy.protocolClasses = [FaviconURLProtocol.self]
        socksProxy.connectionProxyDictionary = ["SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 1089]
        let changedProxy = URL(string: "https://proxy.example.invalid/app")!
        FaviconURLProtocol.fixtures.set(changedProxy, html: "", status: 503)
        let oldProxyResult = await resolver.candidates(for: changedProxy, configuration: httpProxy)
        precondition(oldProxyResult.map(\.path) == ["/favicon.ico"])
        FaviconURLProtocol.fixtures.set(changedProxy, html: "<link rel=icon href=/assets/recovered.png>")
        let newProxyResult = await resolver.candidates(for: changedProxy, configuration: socksProxy)
        precondition(newProxyResult.first?.path == "/assets/recovered.png"
                     && FaviconURLProtocol.fixtures.count(changedProxy) == 2,
                     "A failed proxy result must not poison discovery after the effective proxy changes")
        let pendingURL = URL(string: "https://pending-proxy.example.invalid/app")!
        let gate = FaviconResponseGate()
        FaviconURLProtocol.fixtures.set(pendingURL, html: "", status: 503, gate: gate)
        let oldRequest = Task { await resolver.candidates(for: pendingURL, configuration: httpProxy) }
        let oldDeadline = Date().addingTimeInterval(2)
        while FaviconURLProtocol.fixtures.count(pendingURL) == 0 && Date() < oldDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(FaviconURLProtocol.fixtures.count(pendingURL) == 1)
        FaviconURLProtocol.fixtures.set(pendingURL, html: "<link rel=icon href=/assets/new-route.png>")
        let newRequest = Task { await resolver.candidates(for: pendingURL, configuration: socksProxy) }
        let newDeadline = Date().addingTimeInterval(2)
        while FaviconURLProtocol.fixtures.count(pendingURL) < 2 && Date() < newDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        gate.release()
        let oldURLs = await oldRequest.value
        let newURLs = await newRequest.value
        precondition(oldURLs.map(\.path) == ["/favicon.ico"] && newURLs.first?.path == "/assets/new-route.png",
                     "A new proxy lookup must not join an in-flight old route")
        let retainedNewURLs = await resolver.candidates(for: pendingURL, configuration: socksProxy)
        precondition(retainedNewURLs == newURLs && FaviconURLProtocol.fixtures.count(pendingURL) == 2,
                     "An old route finishing last must not overwrite the new route's cached candidates")

        for (path, mime, status) in [
            ("missing", "text/html", 404), ("not-html", "application/octet-stream", 200)
        ] {
            let url = URL(string: "https://example.invalid/\(path)")!
            FaviconURLProtocol.fixtures.set(url, html: "<link rel=icon href=/wrong.png>", mime: mime, status: status)
            let urls = await resolver.candidates(for: url, configuration: configuration)
            precondition(urls.map(\.path) == ["/favicon.ico"])
            let redirectedURL = URL(string: "https://example.invalid/redirected-\(path)")!
            FaviconURLProtocol.fixtures.set(
                redirectedURL, html: "", mime: mime, status: status, finalURL: redirected
            )
            let redirectedFallback = await resolver.candidates(for: redirectedURL, configuration: configuration)
            precondition(redirectedFallback.map(\.absoluteString) == ["https://new.example.invalid/favicon.ico"],
                         "An unusable redirected response must still use the final origin's root favicon")
        }
        let offline = URL(string: "https://offline.example.invalid/app")!
        let offlineURLs = await resolver.candidates(for: offline, configuration: configuration)
        precondition(offlineURLs.map(\.absoluteString) == ["https://offline.example.invalid/favicon.ico"])

        let huge = URL(string: "https://large.example.invalid/app")!
        let prefix = String(repeating: " ", count: FaviconResolver.maximumHTMLBytes)
        FaviconURLProtocol.fixtures.set(huge, html: prefix + "<link rel=icon href=/beyond-limit.png>")
        let bounded = await resolver.candidates(for: huge, configuration: configuration)
        precondition(bounded.map(\.path) == ["/favicon.ico"], "Do not parse bytes beyond the HTML budget")
        let malformedTagHTML = String(repeating: "<", count: 8_192)
        let malformedTagStart = ProcessInfo.processInfo.systemUptime
        let malformedTagCandidates = FaviconResolver.candidates(in: malformedTagHTML, pageURL: page)
        let malformedTagDuration = ProcessInfo.processInfo.systemUptime - malformedTagStart
        precondition(malformedTagCandidates.map(\.path) == ["/favicon.ico"] && malformedTagDuration < 1,
                     "An unterminated tag must stop parsing without repeatedly rescanning its suffix")
        for (name, opening, closing) in [
            ("script", "<script>", "</script>"), ("style", "<style>", "</style>"), ("comment", "<!--", "-->")
        ] {
            let url = URL(string: "https://example.invalid/cutoff-\(name)")!
            let head = "<head><link rel=icon href=real.png>" + opening
                + "<base href=https://ignored.example.invalid/><link rel=icon href=/fake.png>"
            let padding = String(repeating: "x", count: FaviconResolver.maximumHTMLBytes - head.utf8.count)
            FaviconURLProtocol.fixtures.set(url, html: head + padding + closing + "</head>")
            let urls = await resolver.candidates(for: url, configuration: configuration)
            precondition(urls.map(\.absoluteString) == [
                "https://example.invalid/real.png", "https://example.invalid/favicon.ico"
            ], "A byte-budget cutoff inside \(name) must not expose literal metadata text")
        }
        let invalid = URL(string: "ftp://example.invalid/app")!
        let invalidURLs = await resolver.candidates(for: invalid, configuration: configuration)
        precondition(invalidURLs.isEmpty && FaviconURLProtocol.fixtures.count(invalid) == 0)

        print("PASS: favicon discovery, redirect/base resolution, safe schemes, deduplication, cache/coalescing, failures, and 128 KiB HTML limit")
        if CommandLine.arguments.contains("--live") {
            try await liveCopilotCheck()
        }
    }

    private static func liveCopilotCheck() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let primary = URL(string: "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/copilot-cli.png")!
        let (_, primaryResponse) = try await session.data(from: primary)
        let homepage = URL(string: "https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli")!
        let urls = await FaviconResolver().candidates(for: homepage, configuration: configuration)
        guard let url = urls.first else { preconditionFailure("Copilot CLI must resolve a website icon") }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            preconditionFailure("The live fallback must download and decode as an image")
        }
        print("LIVE: primary HTTP \((primaryResponse as? HTTPURLResponse)?.statusCode ?? 0); fallback \(url.absoluteString), decoded \(image.width)x\(image.height)")
    }
}
