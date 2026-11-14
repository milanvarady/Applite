import Foundation
import GRDB
import os
@testable import Applite

private final class ReleaseNotesURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.path.contains("/oversized/") {
            client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 256 * 1024 + 1))
        } else {
            let json = """
            {"tag_name":"v1.2.3","body":"network fixture","html_url":"https://github.com/example/project/releases/tag/v1.2.3","draft":false}
            """
            client?.urlProtocol(self, didLoad: Data(json.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
enum ExternalInstallTests {
    private static func writeRecordedArtifacts(
        caskroom: URL, token: String, version: String, source: String
    ) throws {
        let directory = caskroom.appendingPathComponent(".metadata/\(version)/20260101000000/Casks")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["artifacts": [["app": [source]]]])
        try data.write(to: directory.appendingPathComponent("\(token).json"))
    }

    @MainActor
    static func main() async throws {
        precondition(Bundle.main.bundleIdentifier == "dev.applite.ExternalInstallTests")
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: "dev.applite.ExternalInstallTests")
        defer { defaults.removePersistentDomain(forName: "dev.applite.ExternalInstallTests") }
        testInstalledListOptions()
        let configuredHTTP = NetworkProxyManager.sessionConfiguration(
            proxy: NetworkProxyConfiguration(type: .http, host: "127.0.0.1", port: 8080)
        )
        let proxyValues = configuredHTTP.connectionProxyDictionary ?? [:]
        precondition(proxyValues[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1
                     && proxyValues[kCFNetworkProxiesHTTPSProxy as String] as? String == "127.0.0.1"
                     && proxyValues[kCFNetworkProxiesHTTPSPort as String] as? Int == 8080,
                     "An HTTP proxy must tunnel HTTPS requests through the same endpoint")
        let configuredDownloader = AppIconView.faviconDownloader(configuration: configuredHTTP)
        precondition(NSDictionary(dictionary: configuredDownloader.sessionConfiguration.connectionProxyDictionary ?? [:])
            .isEqual(to: proxyValues), "Favicon downloads must use the HTTPS tunnel configuration")
        let httpProxy = URLSessionConfiguration.ephemeral
        httpProxy.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 8080]
        let originalDownloader = AppIconView.faviconDownloader(configuration: httpProxy)
        precondition(originalDownloader === AppIconView.faviconDownloader(configuration: httpProxy))
        let socksProxy = URLSessionConfiguration.ephemeral
        socksProxy.connectionProxyDictionary = ["SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 1080]
        let refreshedDownloader = AppIconView.faviconDownloader(configuration: socksProxy)
        precondition(originalDownloader !== refreshedDownloader)
        precondition(NSDictionary(dictionary: refreshedDownloader.sessionConfiguration.connectionProxyDictionary ?? [:])
            .isEqual(to: socksProxy.connectionProxyDictionary ?? [:]),
                     "Favicon image downloads must use the current effective proxy, without restarting")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try! fm.removeItem(at: root) }
        try testInstalledAppMetadata(root: root)
        try testManagedMetadataResolution(root: root)

        let systemApps = root.appendingPathComponent("Applications", isDirectory: true)
        let userApps = root.appendingPathComponent("User Applications", isDirectory: true)
        let customApps = root.appendingPathComponent("Custom Applications", isDirectory: true)
        let directories = [systemApps, userApps, customApps]
        for directory in directories {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func testReleaseNotes() async throws {
            let homepage = URL(string: "https://github.com/example/project")!
            let download = URL(string: "https://github.com/example/project/releases/download/v1.2.3/App.dmg")!
            let source = ReleaseNotesResolver.source(homepage: homepage, download: download, version: "1.2.3,42")!
            precondition(source.tags == ["v1.2.3"])
            precondition(ReleaseNotesResolver.source(homepage: homepage, download: download, version: "2.0")?.tags == [])
            precondition(ReleaseNotesResolver.source(homepage: homepage, download: download, version: "latest")?.tags == [])
            precondition(ReleaseNotesResolver.source(
                homepage: URL(string: "https://github.com.evil.test/example/project")!,
                download: URL(string: "https://example.test/app.dmg")!, version: "1.0"
            ) == nil)
            let homepageSource = ReleaseNotesResolver.source(
                homepage: homepage, download: URL(string: "https://example.test/app.dmg")!, version: "1.2.3"
            )!
            let plusSource = ReleaseNotesResolver.source(
                homepage: homepage,
                download: URL(string: "https://github.com/example/project/releases/download/v1.2.3+456/App.dmg")!,
                version: "1.2.3+456"
            )!
            precondition(plusSource.tags == ["v1.2.3+456"])
            let plusNotes = try await ReleaseNotesResolver.load(plusSource) { url in
                let json = """
                {"tag_name":"v1.2.3+456","body":"build","html_url":"https://github.com/Example/Project/releases/tag/v1.2.3+456","draft":false}
                """
                return .init(data: Data(json.utf8), status: 200, url: url)
            }
            precondition(plusNotes?.tag == "v1.2.3+456")
            for path in ["Example/Other/releases/tag/v1.2.3+456",
                         "Example/Project/releases/tag/V1.2.3+456",
                         "Example/Project/RELEASES/tag/v1.2.3+456"] {
                do {
                    _ = try await ReleaseNotesResolver.load(plusSource) { url in
                        let json = """
                        {"tag_name":"v1.2.3+456","body":"wrong","html_url":"https://github.com/\(path)","draft":false}
                        """
                        return .init(data: Data(json.utf8), status: 200, url: url)
                    }
                    preconditionFailure("Only owner and repository case may vary")
                } catch ReleaseNotesResolver.Failure.invalidResponse {}
            }
            let ambiguous = ReleaseNotesResolver.source(
                homepage: homepage, download: URL(string: "https://example.test/app.dmg")!, version: "1.2.3,42"
            )!
            let skipped = try await ReleaseNotesResolver.load(ambiguous) { _ in
                preconditionFailure("An ambiguous version must not trigger a request")
            }
            precondition(skipped == nil)
            let notes = try await ReleaseNotesResolver.load(homepageSource) { url in
                if url.lastPathComponent == "1.2.3" {
                    return .init(data: Data(), status: 404, url: url)
                }
                let json = """
                {"tag_name":"v1.2.3","body":"Changes for this version","html_url":"https://github.com/example/project/releases/tag/v1.2.3","draft":false}
                """
                return .init(data: Data(json.utf8), status: 200, url: url)
            }
            precondition(notes?.tag == "v1.2.3" && notes?.body == "Changes for this version")
            let missing = try await ReleaseNotesResolver.load(source) { url in
                .init(data: Data(), status: 404, url: url)
            }
            precondition(missing == nil)
            let empty = """
            {"tag_name":"v1.2.3","body":null,"html_url":"https://github.com/example/project/releases/tag/v1.2.3","draft":false}
            """
            let emptyNotes = try await ReleaseNotesResolver.load(source) { url in
                .init(data: Data(empty.utf8), status: 200, url: url)
            }
            precondition(emptyNotes?.body == "" && emptyNotes?.url.absoluteString == "https://github.com/example/project/releases/tag/v1.2.3")
            let unverified = """
            {"tag_name":"v1.2.3","body":"wrong","html_url":"https://evil.test/example/project/releases/tag/v1.2.3","draft":false}
            """
            do {
                _ = try await ReleaseNotesResolver.load(source) { url in
                    .init(data: Data(unverified.utf8), status: 200, url: url)
                }
                preconditionFailure("An untrusted release link must be rejected")
            } catch ReleaseNotesResolver.Failure.invalidResponse {}
            let wrongTag = """
            {"tag_name":"v9.9","body":"wrong","html_url":"https://github.com/example/project/releases/tag/v1.2.3","draft":false}
            """
            do {
                _ = try await ReleaseNotesResolver.load(source) { url in
                    .init(data: Data(wrongTag.utf8), status: 200, url: url)
                }
                preconditionFailure("A mismatched release tag must be rejected")
            } catch ReleaseNotesResolver.Failure.invalidResponse {}
            do {
                _ = try await ReleaseNotesResolver.load(source) { url in
                    .init(data: Data("invalid".utf8), status: 200, url: url)
                }
                preconditionFailure("Malformed release data must fail")
            } catch is DecodingError {}
            do {
                _ = try await ReleaseNotesResolver.load(source) { url in
                    .init(data: Data(), status: 403, url: url)
                }
                preconditionFailure("HTTP errors must not be reported as missing notes")
            } catch ReleaseNotesResolver.Failure.requestFailed(403) {}
            do {
                _ = try await ReleaseNotesResolver.load(source) { _ in
                    throw CancellationError()
                }
                preconditionFailure("Cancellation must propagate")
            } catch is CancellationError {}
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ReleaseNotesURLProtocol.self]
            configuration.connectionProxyDictionary = configuredHTTP.connectionProxyDictionary
            let fetched = try await ReleaseNotesResolver.load(source, configuration: configuration)
            precondition(fetched?.body == "network fixture")
            let oversized = ReleaseNotesResolver.Source(owner: "example", repository: "oversized", tags: ["v1.2.3"])
            do {
                _ = try await ReleaseNotesResolver.load(oversized, configuration: configuration)
                preconditionFailure("Oversized network responses must fail")
            } catch ReleaseNotesResolver.Failure.responseTooLarge {}
        }
        try await testReleaseNotes()
        let hiddenSelfApp = userApps.appendingPathComponent("Applite.app")
        try fm.createDirectory(at: hiddenSelfApp, withIntermediateDirectories: true)
        let hiddenSelfRecord = CaskRecord(
            token: "applite", fullToken: "applite", tap: "homebrew/cask", name: "Applite",
            descriptionText: "", homepageURL: nil, pkgInstaller: false,
            warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
            appBundleNames: ["Applite.app"]
        )
        let selfMatches = try await ExternalAppDetector.scan(
            catalog: [hiddenSelfRecord], directories: [userApps], managedTokens: []
        )
        let selfRegistry = CaskViewModelRegistry()
        let hiddenSelfVM = selfRegistry.viewModel(for: hiddenSelfRecord)
        selfRegistry.markExternalInstallations(appURLs: selfMatches)
        precondition(selfMatches.isEmpty && selfRegistry.externalInstalledCount == 0
                     && selfRegistry.externalInstalledViewModels.isEmpty,
                     "Hidden Applite must not produce an external badge or a blank non-empty list")
        selfRegistry.markInstalled(tokens: [hiddenSelfRecord.fullToken])
        precondition(hiddenSelfVM.isInstalled, "Self-exclusion must not rewrite actual Homebrew receipts")

        let json = """
        {
          "token": "sample", "full_token": "sample", "tap": "homebrew/cask",
          "name": ["Sample Display Name"], "homepage": "", "url": "https://example.test/app.dmg",
          "deprecated": false, "disabled": false,
          "artifacts": [
            {"app": ["Nested/Source.app", {"target": "Renamed App.app"}]},
            {"app": ["Helper.app"]},
            {"binary": ["tool"]}, {"pkg": ["Installer.pkg"]}
          ]
        }
        """
        let dto = try JSONDecoder().decode(CaskDTO.self, from: Data(json.utf8))
        let record = CaskRecord(fromDTO: dto)
        precondition(record.appBundleNames == ["Renamed App.app", "Helper.app"])
        let nestedJSON = """
        {"app":["Payload/Source.app",{"target":"Suite/Renamed.app"}]}
        """
        let nested = try JSONDecoder().decode(CaskArtifact.self, from: Data(nestedJSON.utf8))
        precondition(nested.bundleName == "Suite/Renamed.app")
        let sourceOnly = try JSONDecoder().decode(CaskArtifact.self, from: Data(#"{"app":["Payload/Source.app"]}"#.utf8))
        precondition(sourceOnly.bundleName == "Source.app")
        for unsafe in ["../Escape.app", "/Applications/Escape.app", "Suite/../Escape.app", "Suite//Escape.app"] {
            let unsafeJSON = try JSONSerialization.data(withJSONObject: ["app": ["Source.app", ["target": unsafe]]])
            let artifact = try JSONDecoder().decode(CaskArtifact.self, from: unsafeJSON)
            precondition(artifact.bundleName == nil, "Unsafe app target paths must fail verification")
        }
        let nestedApp = customApps.appendingPathComponent("Suite/Renamed.app", isDirectory: true)
        try fm.createDirectory(at: nestedApp, withIntermediateDirectories: true)
        precondition(ExternalAppDetector.appURL(
            bundleNames: [nested.bundleName!], displayName: "Unrelated", directories: directories
        ) == nestedApp, "Safe nested destination paths must be detected in the configured app directory")
        let nestedArtCraft = ArtCraftAppDetector.Snapshot(appURLs: [nestedApp])
        precondition(nestedArtCraft.matchingAppURLs(bundleNames: [nested.bundleName!], displayName: "Unrelated") == [nestedApp],
                     "Nested target paths must still match ArtCraft's bundle names")
        precondition(ExternalAppDetector.appURL(
            bundleNames: record.appBundleNames, displayName: record.name, directories: directories
        ) == nil)

        // A renamed bundle in any supported directory is found, without a brew receipt.
        for directory in directories {
            let app = directory.appendingPathComponent("Renamed App.app", isDirectory: true)
            try fm.createDirectory(at: app, withIntermediateDirectories: true)
            precondition(ExternalAppDetector.appURL(
                bundleNames: record.appBundleNames, displayName: record.name, directories: directories
            ) == app)
            try fm.removeItem(at: app)
        }

        let helper = userApps.appendingPathComponent("Helper.app", isDirectory: true)
        try fm.createDirectory(at: helper, withIntermediateDirectories: true)
        precondition(ExternalAppDetector.appURL(
            bundleNames: record.appBundleNames, displayName: record.name, directories: directories
        ) == helper)

        let displayGuess = systemApps.appendingPathComponent("\(record.name).app", isDirectory: true)
        try fm.createDirectory(at: displayGuess, withIntermediateDirectories: true)
        precondition(ExternalAppDetector.appURL(
            bundleNames: [], displayName: record.name, directories: directories
        ) == displayGuess)
        precondition(ExternalAppDetector.appURL(
            bundleNames: ["Missing.app"], displayName: record.name, directories: directories
        ) == nil, "An exact artifact must not fall back to a different display-name app")
        precondition(ExternalAppDetector.appURL(
            bundleNames: ["../Applications/\(record.name).app"], displayName: record.name, directories: directories
        ) == nil)
        try Data().write(to: customApps.appendingPathComponent("Not A Bundle.app"))
        precondition(ExternalAppDetector.appURL(
            bundleNames: ["Not A Bundle.app"], displayName: "", directories: directories
        ) == nil)

        func appRecord(_ token: String, bundle: String, tap: String = "homebrew/cask") -> CaskRecord {
            CaskRecord(
                token: token, fullToken: tap == "homebrew/cask" ? token : "\(tap)/\(token)", tap: tap,
                name: "1Password", descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: [bundle]
            )
        }
        let password = systemApps.appendingPathComponent("1Password.app", isDirectory: true)
        let nightlyApp = systemApps.appendingPathComponent("1Password Nightly.app", isDirectory: true)
        let applite = systemApps.appendingPathComponent("Applite.app", isDirectory: true)
        for app in [password, nightlyApp, applite] {
            try fm.createDirectory(at: app, withIntermediateDirectories: true)
        }
        let stable = appRecord("1password", bundle: "1Password.app")
        let beta = appRecord("1password@beta", bundle: "1Password.app")
        let nightly = appRecord("1password@nightly", bundle: "1Password.app")
        let tapped = appRecord("1password", bundle: "1Password.app", tap: "example/tap")
        let selfRecord = appRecord("applite", bundle: "Applite.app")
        let selfAlias = appRecord("applite@beta", bundle: "Applite.app")
        let candidates = [nightly, tapped, selfRecord, beta, stable, selfAlias]
        let deduplicated = try ExternalAppDetector.installations(
            catalog: candidates, managedTokens: [], directories: directories
        ).externalAppURLs
        precondition(deduplicated == [stable.fullToken: password], "One bundle must not become multiple installed channels")
        let reversedDetection = try ExternalAppDetector.installations(
            catalog: candidates.reversed(), managedTokens: [], directories: directories
        )
        precondition(reversedDetection.externalAppURLs == deduplicated, "Catalog order must not choose the channel")
        let managedBeta = try ExternalAppDetector.installations(
            catalog: candidates, managedTokens: [beta.fullToken], directories: directories
        )
        precondition(managedBeta.externalAppURLs.isEmpty, "A managed beta must suppress external stable/nightly matches of its bundle")
        let managedTap = try ExternalAppDetector.installations(
            catalog: candidates, managedTokens: [tapped.fullToken], directories: directories
        )
        precondition(managedTap.externalAppURLs.isEmpty, "A managed third-party cask owns its bundle ahead of an unmanaged official cask")

        let separateNightly = appRecord("1password@nightly", bundle: "1Password Nightly.app")
        let separate = try ExternalAppDetector.installations(
            catalog: [stable, separateNightly], managedTokens: [], directories: directories
        ).externalAppURLs
        precondition(separate == [stable.fullToken: password, separateNightly.fullToken: nightlyApp],
                     "Distinct bundles with the same display name must remain separate")
        let alias = userApps.appendingPathComponent("Password Alias.app")
        try fm.createSymbolicLink(at: alias, withDestinationURL: password)
        let aliasRecord = appRecord("1password-alias", bundle: "Password Alias.app", tap: "example/tap")
        let symlinkDetection = try ExternalAppDetector.installations(
            catalog: [aliasRecord, stable], managedTokens: [], directories: directories
        )
        precondition(symlinkDetection.externalAppURLs == [stable.fullToken: password],
                     "Symlinks to the same bundle must not create another installed app")

        let displayRegistry = CaskViewModelRegistry()
        let stableVM = displayRegistry.viewModel(for: stable)
        let nightlyVM = displayRegistry.viewModel(for: separateNightly)
        let selfVM = displayRegistry.viewModel(for: selfRecord)
        displayRegistry.markInstalled(tokens: [stable.fullToken, selfRecord.fullToken])
        displayRegistry.markExternalInstallations(appURLs: [separateNightly.fullToken: nightlyApp])
        precondition(Set(displayRegistry.locallyInstalledViewModels.map(\.fullToken)) == [stable.fullToken, separateNightly.fullToken])
        precondition(displayRegistry.locallyInstalledCount == 2)
        precondition(selfVM.isInstalled, "Self-exclusion must not change Homebrew receipts")
        displayRegistry.markExternalInstallations(appURLs: [selfRecord.fullToken: applite])
        precondition(displayRegistry.locallyInstalledViewModels == [stableVM])
        precondition(displayRegistry.locallyInstalledCount == 1 && !nightlyVM.isLocallyInstalled)
        displayRegistry.markInstalled(tokens: [])
        displayRegistry.markExternalInstallations(appURLs: [selfRecord.fullToken: applite])
        precondition(displayRegistry.locallyInstalledCount == 0, "Detected Applite must stay out of list totals")

        // Upgrade a v1 catalog in memory and verify its records and FTS triggers survive.
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator().migrate(dbQueue, upTo: "v1_initial")
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO casks (token, fullToken, tap, name, descriptionText)
                VALUES ('legacy', 'legacy', 'homebrew/cask', 'Legacy', 'Legacy app');
                INSERT INTO metadata (key, value) VALUES ('lastSyncDate', '2026-01-01');
                """)
        }
        let v2Database = try DatabaseQueue()
        try AppDatabase.migrator().migrate(v2Database, upTo: "v2_appBundleNames")
        try await v2Database.write { db in
            try record.insert(db)
            try db.execute(sql: "INSERT INTO metadata (key, value) VALUES ('lastSyncDate', '2026-01-01')")
        }
        try AppDatabase.migrator().migrate(v2Database)
        try await v2Database.read { db in
            let migrated = try CaskRecord.fetchOne(db, key: record.fullToken)
            let lastSync = try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE key = 'lastSyncDate'")
            precondition(migrated?.appBundleNames == [] && lastSync == nil,
                         "Legacy basenames must be reverified until the catalog is refreshed")
        }
        try AppDatabase.migrator().migrate(dbQueue)
        try await dbQueue.write { db in
            let legacy = try CaskRecord.fetchOne(db, key: "legacy")
            precondition(legacy?.appBundleNames == [])
            let lastSync = try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE key = 'lastSyncDate'")
            precondition(lastSync == nil)
            try record.insert(db)
            let restored = try CaskRecord.fetchOne(db, key: record.fullToken)
            precondition(restored == record)
            let searchToken = try String.fetchOne(db, sql: """
                SELECT casks.token FROM casks JOIN cask_fts ON cask_fts.rowid = casks.rowid
                WHERE cask_fts MATCH 'Sample'
                """)
            precondition(searchToken == record.token)
        }

        let registry = CaskViewModelRegistry()
        let vm = registry.viewModel(for: record)
        let sourceVM = CaskViewModel(record: record)
        precondition(sourceVM.installedManagementSourceName == nil)
        sourceVM.externalAppURL = helper
        precondition(sourceVM.installedManagementSourceName == String(localized: "Unknown"))
        sourceVM.isInstalled = true
        precondition(sourceVM.installedManagementSourceName == String(localized: "Homebrew"))
        for source in ProtectedAppInstallation.Source.allCases {
            sourceVM.protectedAppInstallation = ProtectedAppInstallation(url: helper, source: source)
            sourceVM.managementSourceOverrides = [source]
            precondition(sourceVM.installedManagementSourceName == source.name,
                         "Detected ownership must remain visible with a Homebrew receipt or an override")
        }
        sourceVM.protectedAppInstallation = ProtectedAppInstallation(appURLs: [
            .appStore: helper, .intune: helper, .setapp: helper, .artCraft: helper
        ])
        precondition(sourceVM.installedManagementSourceName == ProtectedAppInstallation.Source.intune.name,
                     "The highest-priority detected source must be shown")
        sourceVM.isInstalled = false
        sourceVM.externalAppURL = helper
        precondition(sourceVM.installedManagementSourceName == ProtectedAppInstallation.Source.intune.name)
        sourceVM.externalAppURL = nil
        precondition(sourceVM.installedManagementSourceName == nil)
        let sidebarItems: [SidebarItem] = [
            .home, .updates, .installed, .activeTasks, .appMigration, .brew,
            .appCategory(id: "games"), .tap(tap: TapLoadResult(id: "example/tap", casks: [vm]))
        ]
        for item in sidebarItems {
            var selection: SidebarItem? = item
            var search = ""
            var details: CaskViewModel? = vm
            SidebarNavigation.activate(item, selection: &selection, searchInput: &search, selectedAppDetails: &details)
            precondition(selection == item && details == nil && search.isEmpty,
                         "Reactivating a selected sidebar item must close details")
            selection = item == .home ? .installed : .home
            details = vm
            SidebarNavigation.activate(item, selection: &selection, searchInput: &search, selectedAppDetails: &details)
            precondition(selection == item && details == nil,
                         "Switching sidebar items must close the previous details")
            selection = nil
            search = "fixture"
            details = vm
            SidebarNavigation.activate(item, selection: &selection, searchInput: &search, selectedAppDetails: &details)
            precondition(selection == item && details == nil && search.isEmpty,
                         "Sidebar activation during search must open the selected root")
        }
        let tapRecord = CaskRecord(
            token: record.token, fullToken: "example/tap/sample", tap: "example/tap",
            name: record.name, descriptionText: "", homepageURL: nil, pkgInstaller: false,
            warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0
        )
        let tapVM = registry.viewModel(for: tapRecord)
        precondition(vm.installationState == .notInstalled)
        registry.markInstalled(tokens: [])
        registry.markExternalInstallations(appURLs: [record.fullToken: helper, tapRecord.fullToken: helper])
        precondition(vm.installationState == .externalInstalled)
        precondition(registry.externalInstalledCount == 2)
        precondition(registry.installedCount == 0)
        registry.markOutdated(tokens: [record.token])
        precondition(registry.outdatedCount == 0 && registry.hasNonActionableOutdated)

        // A successful managed refresh takes priority and only affects the exact full token.
        registry.markInstalled(tokens: [record.fullToken])
        precondition(vm.installationState == .installed)
        precondition(vm.externalAppURL == nil)
        precondition(tapVM.installationState == .externalInstalled)
        precondition(registry.externalInstalledViewModels == [tapVM])
        precondition(registry.externalInstalledCount == 1)
        precondition(registry.installedCount == 1)
        registry.markOutdated(tokens: [record.token])
        precondition(registry.outdatedViewModels == [vm] && !registry.hasNonActionableOutdated)
        registry.markOutdated(tokens: [record.token, "unrecognized"])
        precondition(registry.outdatedViewModels == [vm] && registry.hasNonActionableOutdated)
        registry.markOutdated(tokens: [])
        precondition(!registry.hasNonActionableOutdated)
        registry.markOutdated(tokens: [record.token])
        registry.markExternalInstallations(appURLs: [:])
        precondition(vm.externalAppURL == nil)
        precondition(tapVM.installationState == .notInstalled)
        precondition(registry.externalInstalledCount == 0)

        // Confirmation does not run brew. No user's preferences or app database are modified.
        defaults.removeObject(forKey: Preferences.detectExternallyInstalledApps.name)
        defaults.removeObject(forKey: Preferences.offerHomebrewManagement.name)
        defaults.setValue(true, for: Preferences.appdirOn)
        let futureApps = root.appendingPathComponent("New App Directory", isDirectory: true)
        defaults.setValue(futureApps.path, for: Preferences.appdirPath)
        let configurationBeforeCreation = BrewOperationConfiguration.current
        try fm.createDirectory(at: futureApps, withIntermediateDirectories: true)
        precondition(configurationBeforeCreation == BrewOperationConfiguration.current,
                     "Creating an unchanged custom app directory must not change the pinned configuration")
        defaults.setValue("/tmp/Apps with 'quotes'", for: Preferences.appdirPath)
        let arguments = BrewService.installArguments(fullToken: tapRecord.fullToken)
        precondition(arguments == [
            "install", "--cask", tapRecord.fullToken, "--force", "--appdir=/tmp/Apps with 'quotes'"
        ])
        registry.markExternalInstallations(appURLs: [tapRecord.fullToken: helper])
        let manager = CaskManager(registry: registry)
        manager.confirmAdoption(tapVM)
        precondition(manager.alert.current == nil, "Management must require an explicit opt-in")
        precondition(tapVM.installationState == .externalInstalled)
        precondition(registry.externalInstalledCount == 1)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        manager.confirmAdoption(tapVM)
        let confirmation = manager.alert.current!
        precondition(confirmation.title == "Manage this app with Homebrew?")
        precondition(confirmation.actions.first?.title == "Manage with Homebrew")
        precondition(confirmation.message.contains(
            "This will reinstall the app via Homebrew so future updates can be managed here."
        ))
        precondition(confirmation.message.contains(
            "brew install --cask example/tap/sample --force '--appdir=/tmp/Apps with '\\''quotes'\\'''"
        ))
        precondition(confirmation.message.contains(helper.path)
                     && confirmation.message.contains("will remain unmanaged"),
                     "Confirmation must explain when the selected copy is outside Homebrew's app directory")
        precondition(manager.activeTasks.isEmpty)
        precondition(tapVM.installationState == .externalInstalled)
        tapVM.externalAppURL = nightlyApp
        confirmation.actions.first?.handler?()
        precondition(manager.activeTasks.isEmpty, "A changed selected copy must invalidate old consent")
        tapVM.externalAppURL = helper

        // Hiding management offers must not turn off detection or let an old confirmation install.
        defaults.setValue(false, for: Preferences.offerHomebrewManagement)
        let managementDisabled = CaskManager(registry: registry)
        managementDisabled.confirmAdoption(tapVM)
        precondition(managementDisabled.alert.current == nil)
        confirmation.actions.first?.handler?()
        precondition(manager.activeTasks.isEmpty)
        precondition(tapVM.installationState == .externalInstalled)
        precondition(registry.externalInstalledCount == 1)
        precondition(vm.installationState == .installed)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        let managementEnabled = CaskManager(registry: registry)
        managementEnabled.confirmAdoption(tapVM)
        precondition(managementEnabled.alert.current?.title == "Manage this app with Homebrew?")

        // Disabling takes effect immediately, including a confirmation opened before the change.
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        manager.applyExternalAppDetectionSetting()
        precondition(tapVM.installationState == .notInstalled)
        precondition(manager.externalInstalledCount == 0)
        precondition(manager.externalInstalledViewModels.isEmpty)
        precondition(vm.installationState == .installed)
        precondition(registry.outdatedViewModels == [vm])
        confirmation.actions.first?.handler?()
        precondition(manager.activeTasks.isEmpty)

        // Even a stale external model cannot start adoption while the preference is disabled.
        registry.markExternalInstallations(appURLs: [tapRecord.fullToken: helper])
        let disabledManager = CaskManager(registry: registry)
        disabledManager.confirmAdoption(tapVM)
        precondition(disabledManager.alert.current == nil)
        precondition(disabledManager.activeTasks.isEmpty)

        let scanPool = try DatabasePool(path: root.appendingPathComponent("catalog.sqlite").path)
        try AppDatabase.migrator().migrate(scanPool)
        var scanRecord = tapRecord
        scanRecord.appBundleNames = ["External Helper.app"]
        try fm.createDirectory(at: userApps.appendingPathComponent("External Helper.app"), withIntermediateDirectories: true)
        let externalRecord = scanRecord
        try await scanPool.write { db in
            try record.insert(db)
            try externalRecord.insert(db)
            try selfRecord.insert(db)
        }
        _ = registry.viewModel(for: externalRecord)
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: scanPool), registry: registry,
            intuneInventory: { .empty }, artCraftInventory: { .empty }
        )
        let scanBrew = root.appendingPathComponent("Scan Homebrew/bin/brew")
        let scanSource = root.appendingPathComponent("Scan Homebrew/Caskroom/sample/1/Managed.app")
        let scanManagedApp = systemApps.appendingPathComponent("Managed Sample.app")
        try fm.createDirectory(at: scanBrew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nif [ \"$1\" = --caskroom ]; then printf '%s\\n' \"$(dirname \"$(dirname \"$0\")\")/Caskroom\"; else exit 2; fi\n"
            .write(to: scanBrew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scanBrew.path)
        try fm.createDirectory(at: scanSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: scanManagedApp, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: scanSource, withDestinationURL: scanManagedApp)
        try writeRecordedArtifacts(caskroom: scanSource.deletingLastPathComponent().deletingLastPathComponent(),
                                   token: "sample", version: "1", source: "Managed.app")
        defaults.setValue(BrewPaths.PathOption.custom.rawValue, for: Preferences.brewPathOption)
        defaults.setValue(scanBrew.path, for: Preferences.customUserBrewPath)
        let selfResults = try await loader.search(query: "applite")
        precondition(selfResults.isEmpty, "Applite must stay out of catalog search, not just its grid")
        defaults.setValue(userApps.path, for: Preferences.appdirPath)
        try await loader.refreshExternalInstallations()
        precondition(tapVM.installationState == .notInstalled)
        precondition(registry.externalInstalledCount == 0)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        try await loader.refreshExternalInstallations()
        precondition(tapVM.installationState == .externalInstalled)
        precondition(registry.externalInstalledCount == 1)
        precondition(vm.installationState == .installed)
        let restoredManagement = CaskManager(registry: registry)
        restoredManagement.confirmAdoption(tapVM)
        precondition(
            restoredManagement.alert.current?.title == "Manage this app with Homebrew?",
            "Re-enabling detection must respect the saved management opt-in"
        )

        defaults.setValue(false, for: Preferences.offerHomebrewManagement)
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        manager.applyExternalAppDetectionSetting()
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        try await loader.refreshExternalInstallations()
        let restoredOptOut = CaskManager(registry: registry)
        restoredOptOut.confirmAdoption(tapVM)
        precondition(
            restoredOptOut.alert.current == nil,
            "Re-enabling detection must not enable an opted-out management offer"
        )
        precondition(tapVM.installationState == .externalInstalled)
        precondition(registry.externalInstalledCount == 1)
        defaults.setValue("/tmp/Apps with 'quotes'", for: Preferences.appdirPath)

        // The real queued/streaming install path talks only to this fixture executable.
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        let brew = root.appendingPathComponent("bin/brew")
        try fm.createDirectory(at: brew.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fixture = """
        #!/bin/sh
        fixture_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
        case "$1" in
          --version) echo "Homebrew fixture" ;;
          --caskroom) echo "$fixture_dir/Caskroom" ;;
          info)
            if [ -f "$fixture_dir/info-wait" ] &&
               { [ ! -f "$fixture_dir/info-wait-token" ] || [ "$(cat "$fixture_dir/info-wait-token")" = "$4" ]; }; then
              touch "$fixture_dir/info-started"
              while [ -f "$fixture_dir/info-wait" ]; do sleep 0.01; done
            fi
            if [ -f "$fixture_dir/info-fail" ]; then
              echo "Error: metadata fixture unavailable" >&2
              exit 1
            fi
            if [ -f "$fixture_dir/info.json" ] && [ "$(cat "$fixture_dir/info-token")" = "$4" ]; then
              cat "$fixture_dir/info.json"
            else
              token="${4##*/}"
              case "$4" in
                */*) tap="${4%/*}" ;;
                *) tap="homebrew/cask" ;;
              esac
              printf '{"casks":[{"token":"%s","full_token":"%s","tap":"%s","homepage":"https://example.test/","url":"https://example.test/app.dmg","artifacts":[],"deprecated":false,"disabled":false}]}' "$token" "$4" "$tap"
            fi ;;
          list)
            {
              if [ -f "$fixture_dir/managed-tokens" ]; then
                cat "$fixture_dir/managed-tokens"
              elif [ -f "$fixture_dir/managed" ]; then
                echo "example/tap/sample"
              fi
            } | while IFS= read -r token || [ -n "$token" ]; do
              bare="${token##*/}"
              mkdir -p "$fixture_dir/Caskroom/$bare/1" "$fixture_dir/Caskroom/$bare/.metadata/1/1/Casks"
              printf '{"artifacts":[]}' > "$fixture_dir/Caskroom/$bare/.metadata/1/1/Casks/$bare.json"
              printf '%s\\n' "$token"
            done ;;
          outdated)
            if [ -f "$fixture_dir/fail-outdated" ]; then exit 1; fi
            if [ -f "$fixture_dir/pause-outdated" ]; then
              touch "$fixture_dir/outdated-started"
              while [ ! -f "$fixture_dir/resume-outdated" ]; do sleep 0.02; done
            fi ;;
          install)
            printf '%s\\n' "$@" > "$fixture_dir/arguments"
            if [ -f "$fixture_dir/fail" ]; then
              echo "Error: adoption fixture stderr" >&2
              exit 1
            fi
            touch "$fixture_dir/managed"
            echo "fixture success stderr" >&2
            echo "sample was successfully installed!" ;;
          uninstall)
            printf '%s\\n' "$@" > "$fixture_dir/arguments"
            echo "fixture uninstalled" ;;
          upgrade|reinstall)
            printf '%s\\n' "$@" > "$fixture_dir/arguments"
            if [ -f "$fixture_dir/review-bundle-plist" ]; then
              /usr/bin/plutil -replace CFBundleShortVersionString -string "$(cat "$fixture_dir/review-bundle-version")" "$(cat "$fixture_dir/review-bundle-plist")"
            fi
            echo "fixture was successfully upgraded!" ;;
          *) echo "Unexpected command" >&2; exit 2 ;;
        esac
        """
        try fixture.write(to: brew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew.path)
        defaults.setValue(BrewPaths.PathOption.custom.rawValue, for: Preferences.brewPathOption)
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        defaults.setValue(false, for: Preferences.networkProxyEnabled)
        let failMarker = root.appendingPathComponent("fail")
        try Data().write(to: failMarker)

        let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        let installedService = InstalledCaskService()
        var refreshCount = 0
        let reconcile: @MainActor () async throws -> Void = {
            refreshCount += 1
            let tokens = try await installedService.getInstalledCasks()
            registry.markInstalled(tokens: tokens)
            registry.markExternalInstallations(appURLs: [tapRecord.fullToken: helper])
        }
        await service.install(
            tapVM, arguments: arguments, confirmedConfiguration: .current, reconcile: reconcile
        ).value
        precondition(tapVM.installationState == .externalInstalled)
        precondition(refreshCount == 0)
        guard case .failed(let output) = tapVM.progressState else {
            preconditionFailure("Failed adoption must expose its output")
        }
        precondition(output.contains("Error: adoption fixture stderr"), "Unexpected adoption output: \(output)")
        let receivedArguments = try String(contentsOf: root.appendingPathComponent("arguments"), encoding: .utf8)
        precondition(receivedArguments == arguments.joined(separator: "\n") + "\n")
        precondition(registry.externalInstalledCount == 1)

        try fm.removeItem(at: failMarker)
        await service.install(
            tapVM, arguments: arguments, confirmedConfiguration: .current, reconcile: reconcile
        ).value
        precondition(refreshCount == 1)
        precondition(tapVM.installationState == .installed)
        precondition(registry.externalInstalledCount == 0)
        precondition(registry.externalInstalledViewModels.isEmpty)
        precondition(service.activeTasks.isEmpty)
        try await testAppStorePrecedence(root: root, service: service, ordinaryCask: tapVM)
        try await testIntunePrecedence(root: root, ordinaryCask: tapVM)
        try await testSetappPrecedence(root: root, ordinaryCask: tapVM)
        try await testArtCraftPrecedence(root: root, ordinaryCask: tapVM)
        try await testHomebrewCompatibility(root: root, ordinaryCask: tapVM)
        try await testManagementSourceOverrides(root: root, ordinaryCask: tapVM)
        try await testOwnershipReviewRaces(root: root)
        try await testInstalledBundleProjection(root: root)
        try await testAdoptionRaces(
            root: root, loader: loader, registry: registry, vm: tapVM,
            appURL: userApps.appendingPathComponent("External Helper.app", isDirectory: true),
            customApps: customApps, service: service
        )
        try await testOutdatedRefreshLifetime(root: root, loader: loader, registry: registry, service: service)
        try await testUpstreamConsentAndRefresh(root: root)
        try await testLiveArtifactOwnershipAndCatalogResult(root: root)
        try await testDistinctInstallationIdentities(root: root)
        try await testManagedSiblingOwnership(root: root)
        try await testManagedIdentityWithDetectionDisabled(root: root)
        if CommandLine.arguments.contains("--live-intune") {
            try checkLiveIntuneInventory()
        }
        if CommandLine.arguments.contains("--live-setapp") {
            try checkLiveSetappInstallations()
        }
        if CommandLine.arguments.contains("--live-artcraft") {
            try checkLiveArtCraftInventory()
        }
        print("PASS: default-off source overrides, enable consent, retained ownership, remaining-source guards, queued/metadata-time revocation, exact enabled Homebrew-cask eligibility, unsupported/failed verification guards, Intune/App Store/Setapp/ArtCraft precedence and queued/bulk write protection, Installed sorting/source/update/search filters, bundle/channel deduplication, managed ownership, self-exclusion, unified Installed totals, detection/settings guards, migration/FTS, and adoption success/failure")
    }

    @MainActor
    private static func testInstalledAppMetadata(root: URL) throws {
        let fm = FileManager.default
        let app = root.appendingPathComponent("Metadata Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: resources.appendingPathComponent("en.lproj"), withIntermediateDirectories: true)
        try fm.createDirectory(at: resources.appendingPathComponent("Base.lproj"), withIntermediateDirectories: true)
        let plistURL = contents.appendingPathComponent("Info.plist")
        func writePlist(_ values: [String: Any]) throws {
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: plistURL)
        }
        try writePlist([
            "CFBundleShortVersionString": "8.12.46-26.BETA",
            "CFBundleVersion": "8046",
            "CFBundleDisplayName": "Fixture Beta",
            "CFBundleIdentifier": "org.example.fixture",
            "CFBundleGetInfoString": "Fixture app information",
            "NSHumanReadableCopyright": "Fixture notice",
            "CFBundleDevelopmentRegion": "en",
            "LSMinimumSystemVersion": "12.0",
            "LSApplicationCategoryType": "public.app-category.productivity",
            "CFBundleLocalizations": ["fr", "en"]
        ])
        let metadata = try InstalledAppMetadata.read(at: app)
        precondition(metadata.appURL == app)
        precondition(metadata.version == "8.12.46-26.BETA" && metadata.build == "8046")
        precondition(metadata.bundleIdentifier == "org.example.fixture")
        precondition(metadata.displayName == "Fixture Beta" && metadata.bundleInformation == "Fixture app information")
        precondition(metadata.copyrightNotice == "Fixture notice" && metadata.developmentRegion == "en")
        precondition(metadata.minimumSystemVersion == "12.0" && metadata.category == "public.app-category.productivity")
        precondition(metadata.localizations == ["en", "fr"])

        func brew(
            installed: String?, outdated: Bool?, available: String? = "8.12.44", autoUpdates: Bool? = false
        ) throws -> CaskAdditionalInfo {
            let data = try JSONEncoder().encode(CaskAdditionalInfo.dummy)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.coderReadCorrupt)
            }
            json["installed"] = installed
            json["outdated"] = outdated
            json["version"] = available
            json["auto_updates"] = autoUpdates
            return try JSONDecoder().decode(CaskAdditionalInfo.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let current = try brew(installed: "8.12.44", outdated: false)
        let outdated = try brew(installed: "8.12.44", outdated: true)
        let missingVersion = try brew(installed: nil, outdated: false)
        let missingStatus = try brew(installed: "8.12.44", outdated: nil)
        let latestInstalled = try brew(installed: "latest", outdated: false)
        let latestAvailable = try brew(installed: "8.12.44", outdated: false, available: "latest")
        let selfUpdating = try brew(installed: "8.12.44", outdated: false, autoUpdates: true)
        let unknownAutoUpdates = try brew(installed: "8.12.44", outdated: false, autoUpdates: nil)
        let buildReceipt = try brew(installed: "8.12.44,8044", outdated: false)
        let mismatchedBuild = try brew(installed: "8.12.44,8045", outdated: false)
        try writePlist(["CFBundleShortVersionString": "8.12.44", "CFBundleVersion": "8044"])
        let matchingMetadata = try InstalledAppMetadata.read(at: app)

        precondition(InstalledAppDetails.version(
            isLocallyInstalled: true, isHomebrewManaged: false, hasOtherOwner: false, metadata: metadata, brew: current
        ) == .known("8.12.46-26.BETA"), "The installed beta version must come from its own bundle")
        precondition(InstalledAppDetails.version(
            isLocallyInstalled: true, isHomebrewManaged: false, hasOtherOwner: false, metadata: metadata, brew: nil
        ) == .known("8.12.46-26.BETA"), "A failed Homebrew lookup must not hide local information")
        precondition(InstalledAppDetails.version(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: true, metadata: metadata, brew: current
        ) == .known("8.12.46-26.BETA"))
        precondition(InstalledAppDetails.version(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: nil, brew: current
        ) == .known("8.12.44"))
        precondition(InstalledAppDetails.version(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: true, metadata: nil, brew: current
        ) == .unknown)
        precondition(InstalledAppDetails.version(
            isLocallyInstalled: false, isHomebrewManaged: false, hasOtherOwner: false, metadata: nil, brew: current
        ) == .notInstalled)
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: false, hasOtherOwner: false, metadata: metadata, brew: current
        ) == .unknown, "Homebrew cannot determine update status for an external beta")
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: true, metadata: metadata, brew: current
        ) == .unknown, "A protected distribution must not inherit another receipt's status")
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: missingVersion
        ) == .unknown, "An outdated=false response without an installed version is not evidence")
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: missingStatus
        ) == .unknown)
        for info in [latestInstalled, latestAvailable, selfUpdating] {
            precondition(InstalledAppDetails.updateStatus(
                isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: info
            ) == .unknown, "Placeholder versions or self-updating apps cannot establish update status")
        }
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: unknownAutoUpdates
        ) == .current, "An absent auto-update flag must preserve Homebrew's reported update status")
        precondition(InstalledAppDetails.version(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: nil, brew: latestInstalled
        ) == .unknown)
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: nil
        ) == .unknown)
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: current
        ) == .current)
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: outdated
        ) == .outdated)
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: false, isHomebrewManaged: false, hasOtherOwner: false, metadata: nil, brew: nil
        ) == .notApplicable)
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: metadata, brew: current
        ) == .unknown, "A different local beta must not inherit the receipt's status")
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: nil, brew: current
        ) == .unknown, "Missing local metadata cannot corroborate the receipt")
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: buildReceipt
        ) == .current, "Homebrew release/build receipts can match local release and build metadata")
        precondition(InstalledAppDetails.updateStatus(
            isLocallyInstalled: true, isHomebrewManaged: true, hasOtherOwner: false, metadata: matchingMetadata, brew: mismatchedBuild
        ) == .unknown, "A different local build must not inherit the receipt's status")

        try writePlist(["CFBundleShortVersionString": "  ", "CFBundleVersion": "2"])
        let updated = try InstalledAppMetadata.read(at: app)
        precondition(updated.version == nil && updated.build == "2", "Bundle metadata must not be cached")
        precondition(InstalledAppDetails.version(
            isLocallyInstalled: true, isHomebrewManaged: false, hasOtherOwner: false, metadata: updated, brew: current
        ) == .unknown, "A build number is not an installed release version")
        try Data("invalid plist".utf8).write(to: plistURL)
        do {
            _ = try InstalledAppMetadata.read(at: app)
            preconditionFailure("Malformed plists must report an error")
        } catch { }
        try fm.removeItem(at: plistURL)
        do {
            _ = try InstalledAppMetadata.read(at: app)
            preconditionFailure("Missing plists must report an error")
        } catch { }
    }

    @MainActor
    private static func testManagedMetadataResolution(root: URL) throws {
        let fm = FileManager.default
        let apps = root.appendingPathComponent("Metadata recovery apps")
        let token = "metadata-fixture"
        let configurationA = BrewOperationConfiguration(
            executable: root.appendingPathComponent("Metadata Homebrew A/bin/brew"),
            appdirArguments: [], applicationDirectories: [apps],
            caskroom: root.appendingPathComponent("Metadata Homebrew A/Caskroom")
        )
        let configurationB = BrewOperationConfiguration(
            executable: root.appendingPathComponent("Metadata Homebrew B/bin/brew"),
            appdirArguments: [], applicationDirectories: [apps],
            caskroom: root.appendingPathComponent("Metadata Homebrew B/Caskroom")
        )
        func writeApp(_ url: URL, version: String) throws {
            let contents = url.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "org.example.metadata", "CFBundleShortVersionString": version],
                format: .xml, options: 0
            ).write(to: contents.appendingPathComponent("Info.plist"))
        }
        func record(_ app: URL, version: String, configuration: BrewOperationConfiguration) throws -> URL {
            let directory = configuration.executable.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Caskroom/\(token)/\(version)")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeRecordedArtifacts(caskroom: directory.deletingLastPathComponent(), token: token,
                                       version: version, source: app.lastPathComponent)
            let link = directory.appendingPathComponent(app.lastPathComponent)
            try fm.createSymbolicLink(at: link, withDestinationURL: app)
            return link
        }
        func resolve(
            _ preferred: URL, configuration: BrewOperationConfiguration, managed: Bool = true
        ) throws -> URL {
            guard let url = try InstalledAppLocator.metadataAppURL(
                token: token, displayName: "Metadata Fixture", preferredURL: preferred,
                isManaged: managed, configuration: configuration
            ) else { throw CocoaError(.fileReadNoSuchFile) }
            return url
        }
        let oldApp = apps.appendingPathComponent("Old Metadata.app")
        let newApp = apps.appendingPathComponent("Renamed Metadata.app")
        try writeApp(oldApp, version: "1.0")
        let oldLink = try record(oldApp, version: "1.0", configuration: configurationA)
        let initial = try resolve(oldApp, configuration: configurationA)
        let initialMetadata = try InstalledAppMetadata.read(at: initial)
        precondition(initialMetadata.version == "1.0")
        let unrelated = apps.appendingPathComponent("Unrelated.app")
        try writeApp(unrelated, version: "9.0")
        let unrelatedLink = oldLink.deletingLastPathComponent().appendingPathComponent("Payload/Unrelated.app")
        try fm.createDirectory(at: unrelatedLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: unrelatedLink, withDestinationURL: unrelated)
        let initialTargets = try InstalledAppLocator.recordedAppURLs(token: token, caskroom: configurationA.caskroom!)
        precondition(initialTargets == [oldApp.resolvingSymlinksInPath().standardizedFileURL],
                     "Unrecorded payload apps must not be treated as managed artifacts")
        try fm.moveItem(at: oldApp, to: newApp)
        try writeApp(newApp, version: "2.0")
        try fm.removeItem(at: oldLink)
        _ = try record(newApp, version: "2.0", configuration: configurationA)
        let recoveredLaunch = try InstalledAppLocator.launchURL(
            token: token, displayName: "Metadata Fixture", preferredURL: oldApp,
            isManaged: true, configuration: configurationA
        )
        precondition(recoveredLaunch?.path == newApp.path,
                     "Opening a managed app must recover a moved bundle from the pinned Caskroom")
        for _ in 0..<2 {
            let recovered = try resolve(oldApp, configuration: configurationA)
            let metadata = try InstalledAppMetadata.read(at: recovered)
            precondition(recovered.path == newApp.path && metadata.version == "2.0",
                         "Automatic reload and retry must recover a moved managed bundle through its current Caskroom link")
        }
        try writeApp(oldApp, version: "1.0")
        let historicalLink = try record(oldApp, version: "0.1", configuration: configurationA)
        let recorded = try InstalledAppLocator.recordedAppURLs(token: token, caskroom: configurationA.caskroom!)
        precondition(recorded.count == 2, "Ownership checks must retain historical live targets")
        for _ in 0..<2 {
            let selected = try resolve(newApp, configuration: configurationA)
            let metadata = try InstalledAppMetadata.read(at: selected)
            precondition(selected.path == newApp.path && metadata.version == "2.0",
                         "Metadata reload and retry must prefer the selected recorded bundle over an alphabetical historical target")
        }
        try fm.removeItem(at: historicalLink)
        let otherApp = apps.appendingPathComponent("Other Profile.app")
        try writeApp(otherApp, version: "3.0")
        _ = try record(otherApp, version: "3.0", configuration: configurationB)
        let selectedB = try resolve(newApp, configuration: configurationB)
        let metadataB = try InstalledAppMetadata.read(at: selectedB)
        precondition(selectedB.path == otherApp.path && metadataB.version == "3.0",
                     "A different pinned Homebrew must not reuse an existing bundle from the previous profile")
        let receiptToken = "metadata-receipt"
        let receiptCaskroom = configurationA.executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Caskroom/\(receiptToken)")
        let staged = receiptCaskroom.appendingPathComponent("1.0/Payload")
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: staged.appendingPathComponent("Source.app"), withDestinationURL: otherApp)
        let receiptMetadata = receiptCaskroom.appendingPathComponent(".metadata/1.0/20260101000000/Casks")
        try fm.createDirectory(at: receiptMetadata, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["url_specs": ["only_path": "Payload"]])
            .write(to: receiptMetadata.appendingPathComponent("\(receiptToken).json"))
        try JSONSerialization.data(withJSONObject: ["uninstall_artifacts": [["app": ["Source.app"]]]])
            .write(to: receiptCaskroom.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
        let receiptTargets = try InstalledAppLocator.recordedAppURLs(token: receiptToken, caskroom: configurationA.caskroom!)
        precondition(receiptTargets == [otherApp.resolvingSymlinksInPath().standardizedFileURL],
                     "Receipt artifacts and recorded only_path must identify the staged source")
        try JSONSerialization.data(withJSONObject: ["url_specs": ["only_path": "../outside"]])
            .write(to: receiptMetadata.appendingPathComponent("\(receiptToken).json"))
        do {
            _ = try InstalledAppLocator.recordedAppURLs(token: receiptToken, caskroom: configurationA.caskroom!)
            preconditionFailure("An unsafe recorded source path must fail closed")
        } catch CaskAdoptionError.installationTargetsUnavailable { }
        let rubyRoom = receiptCaskroom.deletingLastPathComponent().appendingPathComponent("ruby-receipt")
        let rubyStage = rubyRoom.appendingPathComponent("1.0")
        let rubyCasks = rubyRoom.appendingPathComponent(".metadata/1.0/20260101000000/Casks")
        try fm.createDirectory(at: rubyStage, withIntermediateDirectories: true)
        try fm.createDirectory(at: rubyCasks, withIntermediateDirectories: true)
        try Data("cask fixture".utf8).write(to: rubyCasks.appendingPathComponent("ruby-receipt.rb"))
        try JSONSerialization.data(withJSONObject: ["uninstall_artifacts": [["app": ["Source.app"]]]])
            .write(to: rubyRoom.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
        let rubyLink = rubyStage.appendingPathComponent("Source.app")
        try fm.createSymbolicLink(at: rubyLink, withDestinationURL: otherApp)
        let rubyTargets = try InstalledAppLocator.recordedAppURLs(
            token: "ruby-receipt", caskroom: configurationA.caskroom!, requireRecordedOwnership: true
        )
        precondition(rubyTargets == [otherApp.resolvingSymlinksInPath().standardizedFileURL],
                     "Ruby-only saved casks must use recorded receipt artifacts without evaluating Ruby")
        try fm.removeItem(at: rubyRoom.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
        let legacyLaunch = try InstalledAppLocator.launchURL(
            token: "ruby-receipt", displayName: "Ruby Receipt", preferredURL: nil,
            isManaged: true, configuration: configurationA
        )
        precondition(legacyLaunch?.path == otherApp.path,
                     "Read-only lookup must locate legacy Ruby-only installations without a receipt")
        do {
            _ = try InstalledAppLocator.recordedAppURLs(
                token: "ruby-receipt", caskroom: configurationA.caskroom!, requireRecordedOwnership: true
            )
            preconditionFailure("Legacy Ruby-only installations must fail closed for mutation preflights")
        } catch CaskAdoptionError.installationTargetsUnavailable { }
        try JSONSerialization.data(withJSONObject: ["uninstall_artifacts": [["app": ["Source.app"]]]])
            .write(to: rubyRoom.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
        try fm.removeItem(at: rubyLink)
        do {
            _ = try InstalledAppLocator.recordedAppURLs(token: "ruby-receipt", caskroom: configurationA.caskroom!)
            preconditionFailure("A Ruby receipt without a verifiable staged link must fail closed")
        } catch CaskAdoptionError.installationTargetsUnavailable { }
        let launchB = try InstalledAppLocator.launchURL(
            token: token, displayName: "Metadata Fixture", preferredURL: newApp,
            isManaged: true, configuration: configurationB
        )
        precondition(launchB?.path == otherApp.path,
                     "Opening a managed app must use the selected Homebrew's recorded bundle")

        let externalApp = apps.appendingPathComponent("Protected Distribution.app")
        try writeApp(externalApp, version: "7.0")
        let external = try resolve(externalApp, configuration: configurationA, managed: false)
        let externalMetadata = try InstalledAppMetadata.read(at: external)
        precondition(external.path == externalApp.path && externalMetadata.version == "7.0",
                     "An explicit external/protected selection must not be replaced by a Homebrew distribution")
        for (app, managed) in [(newApp, true), (externalApp, false)] {
            try Data("invalid plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
            let resolved = try resolve(app, configuration: configurationA, managed: managed)
            precondition(resolved.path == app.path)
            do {
                _ = try InstalledAppMetadata.read(at: resolved)
                preconditionFailure("An unreadable selected bundle must report an error, not switch distributions")
            } catch let error as CocoaError {
                precondition(error.code == .propertyListReadCorrupt)
            }
        }
    }

    @MainActor
    private static func testAppStorePrecedence(
        root: URL, service: BrewService, ordinaryCask: CaskViewModel
    ) async throws {
        let fm = FileManager.default
        let apps = root.appendingPathComponent("Store Apps", isDirectory: true)
        let app = apps.appendingPathComponent("Store Fixture.app", isDirectory: true)
        let receiptDirectory = app.appendingPathComponent("Contents/_MASReceipt", isDirectory: true)
        let receipt = receiptDirectory.appendingPathComponent("receipt")
        try fm.createDirectory(at: receipt, withIntermediateDirectories: true)
        let directoryReceipt = try ExternalAppDetector.hasAppStoreReceipt(at: app)
        precondition(!directoryReceipt, "A receipt directory is not a receipt file")
        try fm.removeItem(at: receipt)
        try Data("sandbox fixture".utf8).write(to: receiptDirectory.appendingPathComponent("sandboxReceipt"))
        let sandboxReceipt = try ExternalAppDetector.hasAppStoreReceipt(at: app)
        precondition(!sandboxReceipt, "A sandbox receipt must not imply App Store management")
        try Data("receipt fixture".utf8).write(to: receipt)
        let storeReceipt = try ExternalAppDetector.hasAppStoreReceipt(at: app)
        precondition(storeReceipt)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: receiptDirectory.path)
        do {
            _ = try ExternalAppDetector.hasAppStoreReceipt(at: app)
            preconditionFailure("An inaccessible App Store receipt must not be treated as absent")
        } catch {
            precondition((error as NSError).code != NSFileNoSuchFileError)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: receiptDirectory.path)

        func record(_ token: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask",
                name: "Store Fixture", descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Store Fixture.app"]
            )
        }
        let stable = record("store-fixture")
        let beta = record("store-fixture@beta")
        let vendorApps = root.appendingPathComponent("Vendor Apps", isDirectory: true)
        try fm.createDirectory(at: vendorApps.appendingPathComponent("Store Fixture.app"), withIntermediateDirectories: true)
        let preferredStore = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [], directories: [vendorApps, apps]
        )
        precondition(preferredStore.externalAppURLs[stable.fullToken] == app,
                     "An App Store copy must take precedence over a direct-download copy in another standard location")
        let scan = try ExternalAppDetector.installations(
            catalog: [beta, stable], managedTokens: [stable.fullToken], directories: [apps]
        )
        precondition(scan.externalAppURLs.isEmpty)
        precondition(scan.appStoreAppURLs == [stable.fullToken: app, beta.fullToken: app],
                     "App Store protection must cover aliases and take precedence over a stale brew receipt")
        let registry = CaskViewModelRegistry()
        let vm = registry.viewModel(for: stable)
        _ = registry.viewModel(for: beta)
        registry.markInstalled(tokens: [stable.fullToken])
        registry.markExternalInstallations(appURLs: scan.externalAppURLs, appStoreAppURLs: scan.appStoreAppURLs)
        registry.markOutdated(tokens: [stable.token])
        precondition(vm.isInstalled && vm.isAppStoreManaged && registry.outdatedCount == 0
                     && registry.hasNonActionableOutdated)
        precondition(InstalledListOptions(source: .homebrew).apply(to: [vm]).isEmpty)
        precondition(InstalledListOptions(source: .other).apply(to: [vm]).isEmpty)
        precondition(InstalledListOptions(source: .appStore).apply(to: [vm]) == [vm])
        registry.clearExternalInstallations()
        precondition(vm.isAppStoreManaged, "Disabling external listings must not discard known App Store protection")

        registry.markInstalled(tokens: [])
        let externalScan = try ExternalAppDetector.installations(catalog: [beta, stable], managedTokens: [], directories: [apps])
        registry.markExternalInstallations(
            appURLs: externalScan.externalAppURLs, appStoreAppURLs: externalScan.appStoreAppURLs
        )
        precondition(registry.locallyInstalledCount == 1 && vm.isInstalledExternally)
        let defaults = UserDefaults.standard
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        let manager = CaskManager(registry: registry, brewService: service)
        manager.confirmAdoption(vm)
        precondition(manager.alert.current == nil, "An App Store app must not be offered adoption")

        // A receipt can appear after confirmation but before the queued install starts.
        try fm.removeItem(at: receipt)
        registry.markExternalInstallations(appURLs: [stable.fullToken: app])
        manager.confirmAdoption(vm)
        let pending = manager.alert.current!
        let argumentsURL = root.appendingPathComponent("arguments")
        let previousArguments = try Data(contentsOf: argumentsURL)
        try Data("receipt fixture".utf8).write(to: receipt)
        pending.actions.first?.handler?()
        _ = try await service.runSerialized { true }
        precondition(vm.isAppStoreManaged && !vm.isInstalled)
        guard case .failed(let output) = vm.progressState else {
            preconditionFailure("A stale adoption must fail explicitly without running brew")
        }
        precondition(output.contains(CaskAdoptionError.appStoreManaged.localizedDescription))
        let afterPendingAdoption = try Data(contentsOf: argumentsURL)
        precondition(afterPendingAdoption == previousArguments)

        service.dismissFailure(vm)
        registry.markExternalInstallations(appURLs: [stable.fullToken: app])
        let cachedManager = CaskManager(registry: registry, brewService: service)
        cachedManager.confirmAdoption(vm)
        let cachedPending = cachedManager.alert.current!
        registry.markExternalInstallations(appURLs: [stable.fullToken: app], appStoreAppURLs: [stable.fullToken: app])
        cachedPending.actions.first?.handler?()
        precondition(service.activeTasks.isEmpty, "A pending confirmation must respect refreshed App Store ownership")

        try fm.removeItem(at: receipt)
        registry.markExternalInstallations(appURLs: [stable.fullToken: app])
        var queueGate: CheckedContinuation<Void, Never>?
        let blocker = Task {
            try await service.runSerialized {
                await withCheckedContinuation { queueGate = $0 }
                return true
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while queueGate == nil && Date() < deadline {
            await Task.yield()
        }
        precondition(queueGate != nil, "The fixture must hold the operation queue before enqueueing")
        let queuedInstall = service.install(vm)
        do {
            try Data("receipt fixture".utf8).write(to: receipt)
        } catch {
            queueGate?.resume()
            throw error
        }
        queueGate?.resume()
        _ = try await blocker.value
        await queuedInstall.value
        precondition(vm.isAppStoreManaged && !vm.isInstalled,
                     "A receipt added while waiting must be checked when the operation actually executes")
        let afterQueuedInstall = try Data(contentsOf: argumentsURL)
        precondition(afterQueuedInstall == previousArguments)

        await service.install(vm).value
        await service.update(vm).value
        vm.isInstalled = true
        service.reinstall(vm)
        service.uninstall(vm, zap: true)
        _ = try await service.runSerialized { true }
        guard case .failed(let protectedOutput) = vm.progressState else {
            preconditionFailure("App Store mutations must remain blocked")
        }
        precondition(protectedOutput.contains(CaskAdoptionError.appStoreManaged.localizedDescription))
        precondition(vm.isInstalled, "Blocking an uninstall must not remove or rewrite Homebrew's receipt state")
        let afterSingleOperations = try Data(contentsOf: argumentsURL)
        precondition(afterSingleOperations == previousArguments)

        service.installAll([vm])
        _ = try await service.runSerialized { true }
        service.updateAll([vm])
        _ = try await service.runSerialized { true }
        let afterProtectedBatches = try Data(contentsOf: argumentsURL)
        precondition(afterProtectedBatches == previousArguments)
        precondition(service.batchProgress == nil)

        service.installAll([vm, ordinaryCask])
        _ = try await service.runSerialized { true }
        let batchArguments = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(batchArguments.contains(ordinaryCask.fullToken))
        precondition(batchArguments.contains("--appdir=\(apps.path)"))
        precondition(!batchArguments.contains(vm.fullToken), "A mixed bulk install must exclude App Store apps")
        precondition(ordinaryCask.isInstalled && !ordinaryCask.progressState.isFailed)

        // Imports/disabled detection must still check the real bundle before any write.
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        let unresolved = CaskViewModel(record: stable)
        await service.install(unresolved).value
        precondition(unresolved.isAppStoreManaged && !unresolved.isInstalled)
        let afterUnresolvedImport = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(afterUnresolvedImport == batchArguments)

        try fm.removeItem(at: receipt)
        registry.markInstalled(tokens: [])
        let refreshed = try ExternalAppDetector.installations(catalog: [stable], managedTokens: [], directories: [apps])
        registry.markExternalInstallations(appURLs: refreshed.externalAppURLs, appStoreAppURLs: refreshed.appStoreAppURLs)
        precondition(!vm.isAppStoreManaged && vm.isInstalledExternally,
                     "A later non-App-Store installation must not retain stale App Store ownership")
    }

    @MainActor
    private static func testIntunePrecedence(root: URL, ordinaryCask: CaskViewModel) async throws {
        let fm = FileManager.default
        let directory = root.appendingPathComponent("Intune Fixture", isDirectory: true)
        let agent = directory.appendingPathComponent("Agent.app", isDirectory: true)
        let app = directory.appendingPathComponent("Managed Fixture.app", isDirectory: true)
        try fm.createDirectory(at: agent, withIntermediateDirectories: true)
        try fm.createDirectory(at: app.appendingPathComponent("Contents/_MASReceipt"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "org.fixture.managed"], format: .xml, options: 0
        )
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("receipt fixture".utf8).write(to: app.appendingPathComponent("Contents/_MASReceipt/receipt"))

        let databaseURL = directory.appendingPathComponent("sidecar.sqlite")
        do {
            _ = try IntuneAppDetector.load(agentURL: agent, databaseURL: databaseURL)
            preconditionFailure("An installed agent with unavailable inventory must not be interpreted as unmanaged")
        } catch CaskAdoptionError.intuneInventoryUnavailable { }
        let database = try DatabaseQueue(path: databaseURL.path)
        try await database.write { db in
            try db.execute(sql: "CREATE TABLE ZAPPSTATECHANGEITEM (ZPOLICYRESULTJSON TEXT NOT NULL)")
        }
        let policy = """
        {"Policy":{"PrimaryApplicationBundleId":"org.fixture.primary",
        "AppInfos":[{"BundleId":"org.fixture.managed"},{"BundleId":"org.fixture.managed"}]}}
        """
        func setPolicy(_ json: String?) throws {
            try database.write { db in
                try db.execute(sql: "DELETE FROM ZAPPSTATECHANGEITEM")
                if let json {
                    try db.execute(sql: "INSERT INTO ZAPPSTATECHANGEITEM VALUES (?)", arguments: [json])
                }
            }
        }
        try setPolicy(policy)
        let missingAgent = try IntuneAppDetector.load(
            agentURL: directory.appendingPathComponent("Missing Agent.app"), databaseURL: databaseURL
        )
        precondition(missingAgent.bundleIDs.isEmpty, "A leftover policy cache without the agent must not imply management")
        let inaccessible = directory.appendingPathComponent("Inaccessible")
        try fm.createDirectory(at: inaccessible, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: inaccessible.path)
        do {
            _ = try IntuneAppDetector.load(agentURL: inaccessible.appendingPathComponent("Agent.app"), databaseURL: databaseURL)
            preconditionFailure("An inaccessible agent location must not be interpreted as absent")
        } catch CaskAdoptionError.intuneInventoryUnavailable { }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: inaccessible.path)
        let snapshot = try IntuneAppDetector.load(agentURL: agent, databaseURL: databaseURL)
        precondition(snapshot.bundleIDs == ["org.fixture.primary", "org.fixture.managed"])
        let matches = try snapshot.isManagedApp(at: app)
        precondition(matches)

        let otherApp = directory.appendingPathComponent("Other Fixture.app", isDirectory: true)
        try fm.createDirectory(at: otherApp.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let otherPlist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "ORG.fixture.managed"], format: .binary, options: 0
        )
        try otherPlist.write(to: otherApp.appendingPathComponent("Contents/Info.plist"))
        let otherMatches = try snapshot.isManagedApp(at: otherApp)
        precondition(!otherMatches, "Agent presence and similar bundle IDs must not classify unrelated apps")

        func record(_ token: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask",
                name: "Unrelated Display Name", descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Managed Fixture.app"]
            )
        }
        let stable = record("intune-fixture")
        let alias = record("intune-fixture@beta")
        let scan = try ExternalAppDetector.installations(
            catalog: [alias, stable], managedTokens: [stable.fullToken], directories: [directory], intune: snapshot
        )
        precondition(scan.intuneAppURLs == [stable.fullToken: app, alias.fullToken: app])
        precondition(scan.appStoreAppURLs == scan.intuneAppURLs && scan.externalAppURLs.isEmpty,
                     "Retain secondary App Store evidence without duplicating a managed installation")
        let recordedAlias = try ExternalAppDetector.installations(
            catalog: [alias, stable], managedTokens: [stable.fullToken], directories: [directory],
            intune: snapshot, recordedAppURLs: [stable.fullToken: [app]]
        )
        precondition(recordedAlias.intuneAppURLs[alias.fullToken] == app
                     && recordedAlias.appStoreAppURLs[alias.fullToken] == app
                     && recordedAlias.externalAppURLs[alias.fullToken] == nil,
                     "A recorded sibling bundle must still protect its alias without adding an installed copy")
        let registry = CaskViewModelRegistry()
        let vm = registry.viewModel(for: stable)
        _ = registry.viewModel(for: alias)
        registry.markInstalled(tokens: [stable.fullToken])
        registry.markExternalInstallations(
            appURLs: [:], appStoreAppURLs: scan.appStoreAppURLs, intuneAppURLs: scan.intuneAppURLs
        )
        registry.markOutdated(tokens: [stable.token])
        precondition(vm.isInstalled && vm.isIntuneManaged && !vm.isAppStoreManaged)
        precondition(registry.outdatedCount == 0 && registry.outdatedViewModels.isEmpty)
        precondition(InstalledListOptions(source: .intune).apply(to: [vm]) == [vm])
        for source in [InstalledListOptions.Source.homebrew, .appStore, .setapp, .artCraft, .other] {
            precondition(InstalledListOptions(source: source).apply(to: [vm]).isEmpty)
        }
        registry.clearExternalInstallations()
        precondition(vm.isIntuneManaged)

        let service = BrewService(notify: { _, _, _ in }, intuneInventory: {
            try IntuneAppDetector.load(agentURL: agent, databaseURL: databaseURL)
        }, artCraftInventory: { .empty })
        let defaults = UserDefaults.standard
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        defaults.setValue(directory.path, for: Preferences.appdirPath)
        let manager = CaskManager(registry: registry, brewService: service)
        manager.confirmAdoption(vm)
        precondition(manager.alert.current == nil)

        // A newly received Intune assignment must invalidate a previously offered adoption.
        registry.markInstalled(tokens: [])
        registry.markExternalInstallations(appURLs: [stable.fullToken: app])
        try setPolicy(nil)
        manager.confirmAdoption(vm)
        let pending = manager.alert.current!
        try setPolicy(policy)
        let argumentsURL = root.appendingPathComponent("arguments")
        let before = try Data(contentsOf: argumentsURL)
        pending.actions.first?.handler?()
        _ = try await service.runSerialized { true }
        precondition(vm.isIntuneManaged && !vm.isInstalled)
        guard case .failed(let reason) = vm.progressState else {
            preconditionFailure("A stale adoption must not bypass Intune ownership")
        }
        precondition(reason.contains(CaskAdoptionError.intuneManaged.localizedDescription))

        vm.isInstalled = true
        await service.update(vm).value
        service.reinstall(vm)
        service.uninstall(vm, zap: true)
        _ = try await service.runSerialized { true }
        service.installAll([vm])
        service.updateAll([vm])
        _ = try await service.runSerialized { true }
        let afterProtectedOperations = try Data(contentsOf: argumentsURL)
        precondition(before == afterProtectedOperations && vm.isInstalled)

        service.installAll([vm, ordinaryCask])
        _ = try await service.runSerialized { true }
        let mixedArguments = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(mixedArguments.contains(ordinaryCask.fullToken) && !mixedArguments.contains(vm.fullToken))
        precondition(ordinaryCask.isInstalled && !ordinaryCask.progressState.isFailed)

        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        let imported = CaskViewModel(record: stable)
        await service.install(imported).value
        precondition(imported.isIntuneManaged && !imported.isInstalled)

        try setPolicy("not valid JSON")
        await service.install(ordinaryCask).value
        guard case .failed(let failure) = ordinaryCask.progressState else {
            preconditionFailure("Unavailable Intune inventory must block writes, not assume unmanaged")
        }
        precondition(failure.contains(CaskAdoptionError.intuneInventoryUnavailable.localizedDescription))
        service.updateAll([vm, ordinaryCask])
        _ = try await service.runSerialized { true }
        let afterInventoryFailure = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(afterInventoryFailure == mixedArguments)

        try setPolicy(nil)
        let cleared = try IntuneAppDetector.load(agentURL: agent, databaseURL: databaseURL)
        let fallback = try ExternalAppDetector.protectedInstallation(
            bundleNames: stable.appBundleNames, displayName: stable.name,
            directories: [directory], intune: cleared
        )
        precondition(fallback?.source == .appStore,
                     "Removing an Intune policy must restore independent App Store protection")
        registry.markExternalInstallations(appURLs: [:], appStoreAppURLs: [stable.fullToken: app])
        precondition(vm.isAppStoreManaged && !vm.isIntuneManaged)
        try await database.write { db in try db.execute(sql: "DROP TABLE ZAPPSTATECHANGEITEM") }
        do {
            _ = try IntuneAppDetector.load(agentURL: agent, databaseURL: databaseURL)
            preconditionFailure("An unsupported inventory schema must not be interpreted as no managed apps")
        } catch CaskAdoptionError.intuneInventoryUnavailable { }
    }

    @MainActor
    private static func testSetappPrecedence(root: URL, ordinaryCask: CaskViewModel) async throws {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let apps = root.appendingPathComponent("Setapp", isDirectory: true)
        func makeApp(_ name: String, identifier: String) throws -> URL {
            let app = apps.appendingPathComponent("\(name).app", isDirectory: true)
            try fm.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
            try setIdentifier(identifier, at: app)
            return app
        }
        func setIdentifier(_ identifier: String, at app: URL) throws {
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": identifier], format: .binary, options: 0
            )
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        }
        let app = try makeApp("Subscription Fixture", identifier: "org.fixture.subscription-setapp")
        let identifiedByBundle = try ExternalAppDetector.isSetappApp(at: app)
        precondition(identifiedByBundle)
        let legacy = try makeApp("Legacy Fixture", identifier: "org.fixture.legacy")
        let key = legacy.appendingPathComponent("Contents/Resources/setappPublicKey.pem")
        try fm.createDirectory(at: key, withIntermediateDirectories: true)
        let keyDirectory = try ExternalAppDetector.isSetappApp(at: legacy)
        precondition(!keyDirectory, "A directory named like a public key is not Setapp evidence")
        try fm.removeItem(at: key)
        try Data("public-key fixture".utf8).write(to: key)
        let identifiedByResource = try ExternalAppDetector.isSetappApp(at: legacy)
        precondition(identifiedByResource, "The documented main-bundle key supports older bundle IDs")
        let resources = key.deletingLastPathComponent()
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: resources.path)
        do {
            _ = try ExternalAppDetector.isSetappApp(at: legacy)
            preconditionFailure("An inaccessible Setapp marker must not be treated as absent")
        } catch {
            precondition((error as NSError).code != NSFileNoSuchFileError)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: resources.path)
        let unrelated = try makeApp("Unrelated Fixture", identifier: "org.fixture.not-setapp.helper")
        let unrelatedMatch = try ExternalAppDetector.isSetappApp(at: unrelated)
        precondition(!unrelatedMatch, "A Setapp folder or a substring in an ID must not classify unrelated apps")

        func record(_ token: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask",
                name: "Subscription Fixture", descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Subscription Fixture.app"]
            )
        }
        let stable = record("subscription-fixture")
        let alias = record("subscription-fixture@beta")
        let direct = root.appendingPathComponent("Direct Apps", isDirectory: true)
        try fm.createDirectory(at: direct.appendingPathComponent("Subscription Fixture.app"), withIntermediateDirectories: true)
        let scan = try ExternalAppDetector.installations(
            catalog: [alias, stable], managedTokens: [], directories: [direct, apps]
        )
        precondition(scan.externalAppURLs == [
            stable.fullToken: app,
            alias.fullToken: direct.appendingPathComponent("Subscription Fixture.app", isDirectory: true)
        ], "Setapp must remain preferred while the separate direct-download copy remains detected")
        precondition(scan.setappAppURLs == [stable.fullToken: app, alias.fullToken: app])
        let intune = try ExternalAppDetector.protectedInstallation(
            bundleNames: stable.appBundleNames, displayName: stable.name, directories: [apps],
            intune: IntuneAppDetector.Snapshot(bundleIDs: ["org.fixture.subscription-setapp"])
        )
        precondition(intune?.source == .intune, "Setapp must not override organizational ownership")
        let receipt = app.appendingPathComponent("Contents/_MASReceipt/receipt")
        try fm.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("receipt fixture".utf8).write(to: receipt)
        let store = try ExternalAppDetector.protectedInstallation(
            bundleNames: stable.appBundleNames, displayName: stable.name, directories: [apps], intune: .empty
        )
        precondition(store?.source == .appStore)
        try fm.removeItem(at: receipt)

        let registry = CaskViewModelRegistry()
        let vm = registry.viewModel(for: stable)
        _ = registry.viewModel(for: alias)
        registry.markInstalled(tokens: [stable.fullToken])
        registry.markExternalInstallations(appURLs: scan.externalAppURLs, setappAppURLs: scan.setappAppURLs)
        registry.markOutdated(tokens: [stable.token])
        precondition(vm.isInstalled && vm.isSetappManaged && registry.outdatedCount == 0)
        precondition(InstalledListOptions(source: .setapp).apply(to: [vm]) == [vm])
        for source in [InstalledListOptions.Source.homebrew, .appStore, .intune, .artCraft, .other] {
            precondition(InstalledListOptions(source: source).apply(to: [vm]).isEmpty)
        }
        registry.clearExternalInstallations()
        precondition(vm.isSetappManaged)

        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        defaults.setValue("/Applications/Setapp", for: Preferences.appdirPath)
        let locations = InstalledAppLocator.applicationDirectories
        precondition(locations.filter { $0 == URL(fileURLWithPath: "/Applications/Setapp", isDirectory: true) }.count == 1)
        precondition(locations.contains(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Setapp", isDirectory: true)))
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        let pool = try DatabasePool(path: root.appendingPathComponent("setapp-catalog.sqlite").path)
        try AppDatabase.migrator().migrate(pool)
        try await pool.write { db in
            try stable.insert(db)
            try alias.insert(db)
        }
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: pool), registry: registry,
            intuneInventory: { .empty }, artCraftInventory: { .empty }
        )
        registry.markInstalled(tokens: [])
        try await loader.refreshExternalInstallations()
        precondition(vm.isSetappManaged && vm.isInstalledExternally && registry.locallyInstalledCount == 1)
        let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        let manager = CaskManager(registry: registry, brewService: service)
        manager.confirmAdoption(vm)
        precondition(manager.alert.current == nil, "Known Setapp apps must never offer adoption")

        try setIdentifier("org.fixture.subscription", at: app)
        registry.markExternalInstallations(appURLs: [stable.fullToken: app])
        manager.confirmAdoption(vm)
        let pending = manager.alert.current!
        try setIdentifier("org.fixture.subscription-setapp", at: app)
        let argumentsURL = root.appendingPathComponent("arguments")
        let before = try Data(contentsOf: argumentsURL)
        pending.actions.first?.handler?()
        _ = try await service.runSerialized { true }
        guard case .failed(let reason) = vm.progressState else {
            preconditionFailure("A stale adoption must not bypass Setapp ownership")
        }
        precondition(vm.isSetappManaged && !vm.isInstalled)
        precondition(reason.contains(CaskAdoptionError.setappManaged.localizedDescription))
        vm.isInstalled = true
        service.uninstall(vm, zap: true)
        service.updateAll([vm])
        _ = try await service.runSerialized { true }
        let afterProtectedOperations = try Data(contentsOf: argumentsURL)
        precondition(before == afterProtectedOperations && vm.isInstalled)

        service.installAll([vm, ordinaryCask])
        _ = try await service.runSerialized { true }
        let mixedArguments = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(mixedArguments.contains(ordinaryCask.fullToken) && !mixedArguments.contains(vm.fullToken))
        precondition(ordinaryCask.isInstalled && !ordinaryCask.progressState.isFailed)
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        let imported = CaskViewModel(record: stable)
        await service.install(imported).value
        precondition(imported.isSetappManaged && !imported.isInstalled)

        // The legacy resource marker must also be rechecked at execution, not just during listing.
        try setIdentifier("org.fixture.subscription", at: app)
        let appKey = app.appendingPathComponent("Contents/Resources/setappPublicKey.pem")
        try Data("public-key fixture".utf8).write(to: appKey)
        await service.install(vm).value
        precondition(vm.isSetappManaged)
        let afterResourceProtection = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(afterResourceProtection == mixedArguments)
        try fm.removeItem(at: appKey)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        registry.markInstalled(tokens: [])
        try await loader.refreshExternalInstallations()
        precondition(!vm.isManagementProtected && vm.isInstalledExternally,
                     "Replacing a Setapp build with an ordinary build must clear stale ownership")
        try Data("invalid plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        do {
            _ = try ExternalAppDetector.isSetappApp(at: app)
            preconditionFailure("Unreadable bundle metadata must report an error, not imply unmanaged")
        } catch is DecodingError { }
    }

    @MainActor
    private static func testArtCraftPrecedence(root: URL, ordinaryCask: CaskViewModel) async throws {
        let fm = FileManager.default
        let apps = root.appendingPathComponent("Launcher Owned Apps", isDirectory: true)
        let app = apps.appendingPathComponent("Launcher Fixture.app", isDirectory: true)
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "org.fixture.launcher"], format: .xml, options: 0
        )
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let manifest = root.appendingPathComponent("launcher-installed.json")
        let absent = try ArtCraftAppDetector.load(manifestURL: manifest)
        precondition(absent.appURLs.isEmpty, "A new/unused launcher has no installation records")
        do {
            _ = try ArtCraftAppDetector.load(manifestURL: apps)
            preconditionFailure("An unreadable manifest must not be interpreted as absent")
        } catch CaskAdoptionError.artCraftInventoryUnavailable { }
        func writeManifest(_ paths: [String], kind: String = "Dmg") throws {
            let entries = Dictionary(uniqueKeysWithValues: paths.enumerated().map {
                ("entry-\($0.offset)", ["kind": kind, "path": $0.element, "version": "1.0"])
            })
            try JSONEncoder().encode(["apps": entries]).write(to: manifest, options: .atomic)
        }
        try writeManifest([app.path, apps.appendingPathComponent("Gone.app").path])
        let snapshot = try ArtCraftAppDetector.load(manifestURL: manifest)
        precondition(snapshot.appURLs == [app])
        let link = root.appendingPathComponent("Launcher Alias.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: app)
        precondition(snapshot.isManagedApp(at: link), "A bundle symlink must not bypass recorded ownership")
        let direct = root.appendingPathComponent("Unrelated Apps", isDirectory: true)
        let directCopy = direct.appendingPathComponent("Launcher Fixture.app", isDirectory: true)
        try fm.createDirectory(at: directCopy, withIntermediateDirectories: true)
        precondition(!snapshot.isManagedApp(at: directCopy), "A matching name alone must not establish ownership")
        func record(_ token: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask",
                name: "Launcher Fixture", descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Launcher Fixture.app"]
            )
        }
        let stable = record("launcher-fixture")
        let alias = record("launcher-fixture@beta")
        let scan = try ExternalAppDetector.installations(
            catalog: [alias, stable], managedTokens: [], directories: [], artCraft: snapshot
        )
        precondition(scan.externalAppURLs == [stable.fullToken: app],
                     "Recorded custom installation paths must work outside standard scan roots")
        precondition(scan.artCraftAppURLs == [stable.fullToken: app, alias.fullToken: app])
        let acrossLocations = try ExternalAppDetector.protectedInstallation(
            bundleNames: stable.appBundleNames, displayName: stable.name, directories: [direct],
            intune: .empty, artCraft: snapshot
        )
        precondition(acrossLocations?.url == app && acrossLocations?.source == .artCraft)
        let intune = try ExternalAppDetector.protectedInstallation(
            bundleNames: stable.appBundleNames, displayName: stable.name, directories: [],
            intune: IntuneAppDetector.Snapshot(bundleIDs: ["org.fixture.launcher"]), artCraft: snapshot
        )
        precondition(intune?.source == .intune)
        let receipt = app.appendingPathComponent("Contents/_MASReceipt/receipt")
        try fm.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("receipt fixture".utf8).write(to: receipt)
        let store = try ExternalAppDetector.protectedInstallation(
            bundleNames: stable.appBundleNames, displayName: stable.name, directories: [],
            intune: .empty, artCraft: snapshot
        )
        precondition(store?.source == .appStore)
        try fm.removeItem(at: receipt)
        let resource = app.appendingPathComponent("Contents/Resources/setappPublicKey.pem")
        try fm.createDirectory(at: resource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("public-key fixture".utf8).write(to: resource)
        let setapp = try ExternalAppDetector.protectedInstallation(
            bundleNames: stable.appBundleNames, displayName: stable.name, directories: [],
            intune: .empty, artCraft: snapshot
        )
        precondition(setapp?.source == .setapp)
        try fm.removeItem(at: resource)

        let registry = CaskViewModelRegistry()
        let vm = registry.viewModel(for: stable)
        _ = registry.viewModel(for: alias)
        registry.markInstalled(tokens: [stable.fullToken])
        registry.markExternalInstallations(appURLs: [:], artCraftAppURLs: scan.artCraftAppURLs)
        registry.markOutdated(tokens: [stable.token])
        precondition(vm.isInstalled && vm.isArtCraftManaged && registry.outdatedCount == 0)
        precondition(InstalledListOptions(source: .artCraft).apply(to: [vm]) == [vm])
        for source in [InstalledListOptions.Source.homebrew, .appStore, .intune, .setapp, .other] {
            precondition(InstalledListOptions(source: source).apply(to: [vm]).isEmpty)
        }
        registry.clearExternalInstallations()
        precondition(vm.isArtCraftManaged)
        let defaults = UserDefaults.standard
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        defaults.setValue(direct.path, for: Preferences.appdirPath)
        let pool = try DatabasePool(path: root.appendingPathComponent("launcher-catalog.sqlite").path)
        try AppDatabase.migrator().migrate(pool)
        try await pool.write { db in
            try stable.insert(db)
            try alias.insert(db)
        }
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: pool), registry: registry,
            intuneInventory: { .empty }, artCraftInventory: { try ArtCraftAppDetector.load(manifestURL: manifest) }
        )
        registry.markInstalled(tokens: [])
        try await loader.refreshExternalInstallations()
        precondition(vm.isArtCraftManaged && vm.isInstalledExternally && registry.locallyInstalledCount == 2,
                     "A recorded launcher copy and a separate direct copy must retain distinct installation rows")
        let service = BrewService(
            notify: { _, _, _ in }, intuneInventory: { .empty },
            artCraftInventory: { try ArtCraftAppDetector.load(manifestURL: manifest) }
        )
        let manager = CaskManager(registry: registry, brewService: service)
        manager.confirmAdoption(vm)
        precondition(manager.alert.current == nil)
        try writeManifest([])
        registry.markExternalInstallations(appURLs: [stable.fullToken: app])
        manager.confirmAdoption(vm)
        let pending = manager.alert.current!
        try writeManifest([app.path])
        let argumentsURL = root.appendingPathComponent("arguments")
        let before = try Data(contentsOf: argumentsURL)
        pending.actions.first?.handler?()
        _ = try await service.runSerialized { true }
        guard case .failed(let reason) = vm.progressState else {
            preconditionFailure("A launcher assignment received after confirmation must block adoption")
        }
        precondition(vm.isArtCraftManaged && reason.contains(CaskAdoptionError.artCraftManaged.localizedDescription))
        vm.isInstalled = true
        service.uninstall(vm, zap: true)
        service.updateAll([vm])
        _ = try await service.runSerialized { true }
        let afterProtectedOperations = try Data(contentsOf: argumentsURL)
        precondition(afterProtectedOperations == before && vm.isInstalled)
        service.installAll([vm, ordinaryCask])
        _ = try await service.runSerialized { true }
        let mixedArguments = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(mixedArguments.contains(ordinaryCask.fullToken) && !mixedArguments.contains(vm.fullToken))
        precondition(ordinaryCask.isInstalled && !ordinaryCask.progressState.isFailed)
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        let imported = CaskViewModel(record: stable)
        await service.install(imported).value
        precondition(imported.protectedAppInstallation?.source == .artCraft && !imported.isInstalled,
                     "Ownership evidence from any matching copy must still block Homebrew changes")

        for invalid in ["not JSON", "{\"apps\":[]}", "{\"apps\":{\"bad\":{\"kind\":\"Dmg\",\"path\":\"relative.app\"}}}",
                        "{\"apps\":{\"bad\":{\"kind\":\"Unknown\",\"path\":\"/Applications/Future.app\"}}}"] {
            try Data(invalid.utf8).write(to: manifest, options: .atomic)
            await service.install(ordinaryCask).value
            guard case .failed(let failure) = ordinaryCask.progressState else {
                preconditionFailure("An unreadable or unsupported launcher inventory must block writes")
            }
            precondition(failure.contains(CaskAdoptionError.artCraftInventoryUnavailable.localizedDescription))
        }
        service.installAll([vm, ordinaryCask])
        _ = try await service.runSerialized { true }
        let afterInventoryFailure = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(afterInventoryFailure == mixedArguments && vm.isArtCraftManaged)
        try writeManifest([])
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        registry.markInstalled(tokens: [])
        try await loader.refreshExternalInstallations()
        precondition(vm.isInstalledExternally && !vm.isManagementProtected,
                     "Removing the launcher record must clear cached ownership on refresh")
    }

    @MainActor
    private static func testHomebrewCompatibility(root: URL, ordinaryCask: CaskViewModel) async throws {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let apps = root.appendingPathComponent("Compatibility Apps", isDirectory: true)
        let app = apps.appendingPathComponent("Compatibility Fixture.app", isDirectory: true)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        func record(_ token: String, warning: CaskRecord.WarningType? = nil) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask", name: "Compatibility Fixture",
                descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: warning, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Compatibility Fixture.app"]
            )
        }
        let registry = CaskViewModelRegistry()
        let disabled = registry.viewModel(for: record("disabled-fixture", warning: .disabled))
        let vm = registry.viewModel(for: record("compatibility-fixture"))
        let deprecated = registry.viewModel(for: record("deprecated-fixture", warning: .deprecated))
        registry.markExternalInstallations(appURLs: [disabled.fullToken: app, vm.fullToken: app])
        precondition(disabled.homebrewManagementBlockReason != nil && deprecated.homebrewManagementBlockReason == nil)
        let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        let manager = CaskManager(registry: registry, brewService: service)
        manager.confirmAdoption(disabled)
        precondition(manager.alert.current?.title == "Homebrew management unavailable")
        let argumentsURL = root.appendingPathComponent("arguments")
        let before = try Data(contentsOf: argumentsURL)
        await service.install(disabled).value
        precondition(disabled.progressState.isFailed && !disabled.isInstalled)

        let override = root.appendingPathComponent("info.json")
        let overrideToken = root.appendingPathComponent("info-token")
        try vm.fullToken.write(to: overrideToken, atomically: true, encoding: .utf8)
        func info(_ cask: CaskViewModel, disabled: Bool = false) -> [String: Any] {
            [
                "token": cask.token, "full_token": cask.fullToken, "tap": cask.tap,
                "homepage": "https://example.test/", "url": "https://example.test/app.dmg",
                "deprecated": false, "disabled": disabled, "artifacts": []
            ]
        }
        func setInfo(_ entries: [[String: Any]]) throws {
            try JSONSerialization.data(withJSONObject: ["casks": entries]).write(to: override, options: .atomic)
        }
        let freshManager = CaskManager(registry: registry, brewService: service)
        freshManager.confirmAdoption(vm)
        let pending = freshManager.alert.current!
        try setInfo([info(vm, disabled: true)])
        pending.actions.first?.handler?()
        _ = try await service.runSerialized { true }
        precondition(vm.homebrewManagementBlockReason != nil && vm.isInstalledExternally)
        let afterDisabledAdoption = try Data(contentsOf: argumentsURL)
        precondition(afterDisabledAdoption == before, "A newly disabled cask must not be adopted")
        for entries in [[], [info(ordinaryCask)]] {
            try setInfo(entries)
            await service.install(vm).value
            guard case .failed(let reason) = vm.progressState else {
                preconditionFailure("Missing/formula-only or mismatched casks must not be installed")
            }
            precondition(reason.contains(CaskAdoptionError.homebrewUnavailable.localizedDescription), "Unexpected failure: \(reason)")
        }
        var wrongTap = info(vm)
        wrongTap["full_token"] = "other/tap/\(vm.token)"
        wrongTap["tap"] = "other/tap"
        try setInfo([wrongTap])
        await service.install(vm).value
        precondition(vm.progressState.isFailed)
        try Data("invalid JSON".utf8).write(to: override)
        await service.install(vm).value
        precondition(vm.progressState.isFailed)
        let infoFailure = root.appendingPathComponent("info-fail")
        try Data().write(to: infoFailure)
        await service.install(vm).value
        guard case .failed(let lookupError) = vm.progressState else {
            preconditionFailure("A failed support check must block writes")
        }
        precondition(lookupError.contains("metadata fixture unavailable"))
        try fm.removeItem(at: infoFailure)
        let afterFailedLookups = try Data(contentsOf: argumentsURL)
        precondition(afterFailedLookups == before)

        registry.clearHomebrewManagementErrors()
        try setInfo([info(vm)])
        let queuedService = BrewService(
            notify: { _, _, _ in },
            intuneInventory: {
                // Change availability in the ownership preflight after the queued operation starts.
                try Data("{\"casks\":[]}".utf8).write(to: override, options: .atomic)
                return .empty
            },
            artCraftInventory: { .empty }
        )
        var queueGate: CheckedContinuation<Void, Never>?
        let blocker = Task {
            try await queuedService.runSerialized {
                await withCheckedContinuation { queueGate = $0 }
                return true
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while queueGate == nil && Date() < deadline {
            await Task.yield()
        }
        precondition(queueGate != nil)
        let queuedInstall = queuedService.install(vm)
        queueGate?.resume()
        _ = try await blocker.value
        await queuedInstall.value
        let afterQueuedCheck = try Data(contentsOf: argumentsURL)
        precondition(vm.progressState.isFailed && afterQueuedCheck == before
                     && vm.homebrewManagementError == CaskAdoptionError.homebrewUnavailable.localizedDescription,
                     "Availability changing after enqueueing must be rechecked at execution, before any write")

        try setInfo([info(vm, disabled: true)])
        vm.isInstalled = true
        service.reinstall(vm)
        await service.update(vm).value
        _ = try await service.runSerialized { true }
        precondition(vm.progressState.isFailed && vm.isInstalled)
        registry.markOutdated(tokens: [vm.token, disabled.token])
        precondition(registry.outdatedCount == 0)
        service.installAll([vm, ordinaryCask])
        _ = try await service.runSerialized { true }
        let mixedArguments = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(mixedArguments.contains(ordinaryCask.fullToken) && !mixedArguments.contains(vm.fullToken))
        precondition(ordinaryCask.isInstalled && !ordinaryCask.progressState.isFailed)
        service.updateAll([vm, disabled])
        _ = try await service.runSerialized { true }
        let afterUnsupportedUpdates = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(afterUnsupportedUpdates == mixedArguments)

        // Retired casks can still be removed, but only when Homebrew actually owns the installation.
        try Data().write(to: infoFailure)
        let managedTokens = root.appendingPathComponent("managed-tokens")
        try vm.fullToken.write(to: managedTokens, atomically: true, encoding: .utf8)
        service.uninstall(vm)
        _ = try await service.runSerialized { true }
        precondition(!vm.isInstalled && !vm.progressState.isFailed)
        let removal = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(removal.hasPrefix("uninstall\n--cask\n\(vm.fullToken)\n"))
        service.uninstall(vm)
        _ = try await service.runSerialized { true }
        precondition(vm.progressState.isFailed)
        let afterUnmanagedRemoval = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(afterUnmanagedRemoval == removal)
        try fm.removeItem(at: managedTokens)
        try fm.removeItem(at: infoFailure)
        registry.clearHomebrewManagementErrors()
        precondition(vm.homebrewManagementBlockReason == nil && disabled.homebrewManagementBlockReason != nil)
        var supported = info(vm)
        supported["deprecated"] = true
        try setInfo([supported])
        await service.install(vm, confirmedConfiguration: .current).value
        precondition(vm.isInstalled && !vm.progressState.isFailed && vm.homebrewManagementBlockReason == nil)
        try fm.removeItem(at: override)
        try fm.removeItem(at: overrideToken)
    }

    @MainActor
    private static func testManagementSourceOverrides(root: URL, ordinaryCask: CaskViewModel) async throws {
        let defaults = UserDefaults.standard
        let sources = ProtectedAppInstallation.Source.allCases
        precondition(sources.allSatisfy { !defaults.value(for: $0.overridePreference) })
        let previousDetection = defaults.value(for: Preferences.detectExternallyInstalledApps)
        let previousManagement = defaults.value(for: Preferences.offerHomebrewManagement)
        defer {
            for source in sources { defaults.removeObject(forKey: source.overridePreference.name) }
            defaults.setValue(previousDetection, for: Preferences.detectExternallyInstalledApps)
            defaults.setValue(previousManagement, for: Preferences.offerHomebrewManagement)
        }
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        let fm = FileManager.default
        let apps = root.appendingPathComponent("Override Apps", isDirectory: true)
        let app = apps.appendingPathComponent("Override Fixture.app", isDirectory: true)
        let receipt = app.appendingPathComponent("Contents/_MASReceipt/receipt")
        try fm.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: receipt)
        let identifier = "org.fixture.overrides-setapp"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0
        )
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        let intune = IntuneAppDetector.Snapshot(bundleIDs: [identifier])
        let artCraft = ArtCraftAppDetector.Snapshot(appURLs: [app])
        func record(warning: CaskRecord.WarningType? = nil) -> CaskRecord {
            CaskRecord(
                token: "override-fixture", fullToken: "override-fixture", tap: "homebrew/cask",
                name: "Override Fixture", descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: warning, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Override Fixture.app"]
            )
        }
        let registry = CaskViewModelRegistry()
        let vm = registry.viewModel(for: record())
        let scan = try ExternalAppDetector.installations(
            catalog: [record()], managedTokens: [], directories: [apps], intune: intune, artCraft: artCraft
        )
        registry.markExternalInstallations(
            appURLs: scan.externalAppURLs, appStoreAppURLs: scan.appStoreAppURLs,
            intuneAppURLs: scan.intuneAppURLs, setappAppURLs: scan.setappAppURLs,
            artCraftAppURLs: scan.artCraftAppURLs
        )
        precondition(vm.protectedAppInstallation?.appURLs.count == 4 && vm.isIntuneManaged)
        let service = BrewService(
            notify: { _, _, _ in }, intuneInventory: { intune }, artCraftInventory: { artCraft }
        )
        let manager = CaskManager(registry: registry, brewService: service)
        let argumentsURL = root.appendingPathComponent("arguments")
        let before = try Data(contentsOf: argumentsURL)
        func enable(_ source: ProtectedAppInstallation.Source) {
            let surface = AlertManager()
            manager.requestManagementSourceOverride(source, enabled: true, surfacingErrorsIn: surface)
            precondition(!defaults.value(for: source.overridePreference), "Opening a warning must not enable an override")
            precondition(surface.current?.actions.first?.role == .destructive)
            surface.current?.actions.first?.handler?()
            precondition(defaults.value(for: source.overridePreference))
        }

        let staleSurface = AlertManager()
        manager.requestManagementSourceOverride(.intune, enabled: true, surfacingErrorsIn: staleSurface)
        defaults.setValue(false, for: Preferences.offerHomebrewManagement)
        staleSurface.current?.actions.first?.handler?()
        precondition(!defaults.value(for: Preferences.overrideIntuneManagement))
        precondition(staleSurface.pending.contains { $0.title == "Homebrew management disabled" })
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        for (index, source) in sources.enumerated() {
            let cancelled = AlertManager()
            manager.requestManagementSourceOverride(source, enabled: true, surfacingErrorsIn: cancelled)
            cancelled.current?.actions.last?.handler?()
            precondition(!defaults.value(for: source.overridePreference))
            enable(source)
            precondition(vm.protectedAppInstallation?.appURLs.count == 4, "Overrides must not erase detected ownership")
            if index + 1 < sources.count {
                let remaining = sources[index + 1]
                precondition(vm.managementProtection?.source == remaining)
                await service.install(vm).value
                guard case .failed(let reason) = vm.progressState else {
                    preconditionFailure("An override must not bypass another detected source")
                }
                precondition(reason.contains(remaining.blockError.localizedDescription))
                let unchanged = try Data(contentsOf: argumentsURL)
                precondition(unchanged == before)
            }
        }
        precondition(!vm.isManagementProtected && vm.isInstalledExternally)
        manager.confirmAdoption(vm)
        let pendingAdoption = manager.alert.current!
        precondition(pendingAdoption.message.contains("brew install --cask \(vm.fullToken) --force"))
        precondition(sources.allSatisfy { pendingAdoption.message.contains($0.name) })
        manager.requestManagementSourceOverride(.intune, enabled: false, surfacingErrorsIn: AlertManager())
        pendingAdoption.actions.first?.handler?()
        _ = try await service.runSerialized { true }
        let afterStaleAdoption = try Data(contentsOf: argumentsURL)
        precondition(vm.isManagementProtected && afterStaleAdoption == before)
        service.installAll([vm, ordinaryCask])
        _ = try await service.runSerialized { true }
        let mixedArguments = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(mixedArguments.contains(ordinaryCask.fullToken) && !mixedArguments.contains(vm.fullToken))

        enable(.intune)
        await service.install(vm, confirmedConfiguration: .current).value
        precondition(vm.isInstalled && !vm.progressState.isFailed && !vm.isManagementProtected)
        let installedArguments = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(installedArguments.hasPrefix("install\n--cask\n\(vm.fullToken)\n"))
        let managedTokens = root.appendingPathComponent("managed-tokens")
        try vm.fullToken.write(to: managedTokens, atomically: true, encoding: .utf8)
        defer { try! fm.removeItem(at: managedTokens) }
        service.installAll([vm])
        _ = try await service.runSerialized { true }
        precondition(vm.isInstalled && !vm.progressState.isFailed)
        vm.isOutdated = true
        service.updateAll([vm])
        _ = try await service.runSerialized { true }
        precondition(!vm.isOutdated && !vm.progressState.isFailed)
        service.reinstall(vm)
        _ = try await service.runSerialized { true }
        precondition(!vm.progressState.isFailed)
        var intuneFilter = InstalledListOptions()
        intuneFilter.source = .intune
        precondition(intuneFilter.apply(to: [vm]) == [vm], "Source filters must retain detected ownership")
        intuneFilter.source = .homebrew
        precondition(intuneFilter.apply(to: [vm]) == [vm], "Overridden, tracked apps must also be available under Homebrew")
        intuneFilter.source = .other
        precondition(intuneFilter.apply(to: [vm]).isEmpty)

        let beforeRevocation = try Data(contentsOf: argumentsURL)
        var queueGate: CheckedContinuation<Void, Never>?
        let blocker = Task {
            try await service.runSerialized {
                await withCheckedContinuation { queueGate = $0 }
                return true
            }
        }
        let queueDeadline = Date().addingTimeInterval(5)
        while queueGate == nil && Date() < queueDeadline { await Task.yield() }
        precondition(queueGate != nil)
        let queuedInstall = service.install(vm)
        manager.requestManagementSourceOverride(.intune, enabled: false, surfacingErrorsIn: AlertManager())
        queueGate?.resume()
        _ = try await blocker.value
        await queuedInstall.value
        let afterRevocation = try Data(contentsOf: argumentsURL)
        precondition(vm.progressState.isFailed && afterRevocation == beforeRevocation)

        enable(.intune)
        let wait = root.appendingPathComponent("info-wait")
        let started = root.appendingPathComponent("info-started")
        for isBatch in [false, true] {
            if fm.fileExists(atPath: started.path) { try fm.removeItem(at: started) }
            try Data().write(to: wait)
            if isBatch {
                service.installAll([vm])
            } else {
                service.install(vm)
            }
            let metadataDeadline = Date().addingTimeInterval(5)
            while !fm.fileExists(atPath: started.path) && Date() < metadataDeadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let observedMetadata = fm.fileExists(atPath: started.path)
            manager.requestManagementSourceOverride(.appStore, enabled: false, surfacingErrorsIn: AlertManager())
            try fm.removeItem(at: wait)
            _ = try await service.runSerialized { true }
            precondition(observedMetadata, "The fixture must pause inside the metadata lookup")
            let afterMetadataRevocation = try Data(contentsOf: argumentsURL)
            precondition(vm.managementProtection?.source == .appStore && afterMetadataRevocation == beforeRevocation,
                         "Revocation during asynchronous metadata checks must block single and bulk writes")
            enable(.appStore)
        }
        vm.updateRecord(record(warning: .disabled))
        await service.install(vm).value
        let afterUnsupported = try Data(contentsOf: argumentsURL)
        precondition(vm.homebrewManagementBlockReason != nil && afterUnsupported == beforeRevocation,
                     "Source overrides must not bypass Homebrew eligibility")
        defaults.setValue(false, for: Preferences.offerHomebrewManagement)
        manager.applyAppManagementSettings(surfacingErrorsIn: AlertManager())
        await service.install(vm).value
        precondition(vm.managementProtection?.source == .intune && defaults.value(for: Preferences.overrideIntuneManagement))
        service.uninstall(vm)
        _ = try await service.runSerialized { true }
        precondition(vm.isInstalled && vm.progressState.isFailed)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        await service.install(vm).value
        precondition(vm.managementProtection?.source == .intune)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        vm.updateRecord(record())
        let unavailable = BrewService(
            notify: { _, _, _ in },
            intuneInventory: { throw CaskAdoptionError.intuneInventoryUnavailable },
            artCraftInventory: { artCraft }
        )
        await unavailable.install(vm).value
        guard case .failed(let reason) = vm.progressState else {
            preconditionFailure("Overrides must not bypass unavailable ownership inventories")
        }
        precondition(reason.contains(CaskAdoptionError.intuneInventoryUnavailable.localizedDescription))
        let afterBlockedOperations = try Data(contentsOf: argumentsURL)
        precondition(afterBlockedOperations == beforeRevocation)
        service.uninstall(vm)
        _ = try await service.runSerialized { true }
        precondition(!vm.isInstalled && !vm.isInstalledExternally && !vm.progressState.isFailed)
    }

    private static func checkLiveArtCraftInventory() throws {
        let snapshot = try ArtCraftAppDetector.load()
        var matches = 0
        for app in snapshot.appURLs {
            let protection = try ExternalAppDetector.protectedInstallation(
                bundleNames: [app.lastPathComponent], displayName: "", directories: [],
                knownURL: app, intune: .empty, artCraft: snapshot
            )
            if protection?.source == .artCraft { matches += 1 }
        }
        print("PASS: live ArtCraft inventory read-only: \(snapshot.appURLs.count) recorded installed bundles; \(matches) ArtCraft ownership matches (no app/account details logged)")
    }

    private static func checkLiveSetappInstallations() throws {
        let fm = FileManager.default
        let roots = [URL.applicationDirectory, fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var matches: Set<URL> = []
        for directory in roots + roots.map({ $0.appendingPathComponent("Setapp") }) {
            guard fm.fileExists(atPath: directory.path) else { continue }
            for app in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where app.pathExtension == "app" {
                if try ExternalAppDetector.isSetappApp(at: app) {
                    matches.insert(app.resolvingSymlinksInPath())
                }
            }
        }
        print("PASS: live Setapp detection read-only: \(matches.count) installed bundles with Setapp distribution markers (no app/account details logged)")
    }

    private static func checkLiveIntuneInventory() throws {
        let snapshot = try IntuneAppDetector.load()
        let fm = FileManager.default
        var matches: Set<URL> = []
        for directory in [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            guard fm.fileExists(atPath: directory.path) else { continue }
            for app in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where app.pathExtension == "app" {
                if try snapshot.isManagedApp(at: app) {
                    matches.insert(app.resolvingSymlinksInPath())
                }
            }
        }
        print("PASS: live Intune inventory read-only: \(snapshot.bundleIDs.count) policy bundle IDs; \(matches.count) installed app matches (no app/account details logged)")
    }

    @MainActor
    private static func testInstalledListOptions() {
        func app(_ token: String, name: String, downloads: Int = 0, tap: String = "homebrew/cask") -> CaskViewModel {
            CaskViewModel(record: CaskRecord(
                token: token, fullToken: tap == "homebrew/cask" ? token : "\(tap)/\(token)", tap: tap,
                name: name, descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: downloads
            ))
        }
        let alpha = app("zulu-token", name: "Alpha 2", downloads: 10)
        let alphaTen = app("alpha-ten", name: "Alpha 10")
        let beta = app("beta", name: "Beta", downloads: 100)
        let tappedBeta = app("beta", name: "Beta", downloads: 100, tap: "example/tap")
        for cask in [alpha, beta, tappedBeta] {
            cask.isInstalled = true
        }
        alphaTen.externalAppURL = URL(fileURLWithPath: "/Applications/Alpha 10.app")
        beta.isOutdated = true
        let input = [tappedBeta, beta, alphaTen, alpha]

        var options = InstalledListOptions()
        precondition(options.apply(to: input) == [alpha, alphaTen, beta, tappedBeta],
                     "Default sorting uses friendly names and natural numbers, not cask tokens")
        options.sortOrder = .zToA
        precondition(options.apply(to: input) == [beta, tappedBeta, alphaTen, alpha])
        options.sortOrder = .mostDownloaded
        precondition(options.apply(to: input) == [beta, tappedBeta, alpha, alphaTen])
        precondition(options.apply(to: input.reversed()) == options.apply(to: input),
                     "Equal names/downloads must have a stable full-token tie-break")

        options = InstalledListOptions(source: .homebrew)
        precondition(options.apply(to: input) == [alpha, beta, tappedBeta])
        options.source = .other
        precondition(options.apply(to: input) == [alphaTen])
        options.updatesOnly = true
        precondition(options.apply(to: input).isEmpty)
        options.source = .all
        precondition(options.apply(to: input) == [beta])
        options.updatesOnly = false
        precondition(options.apply(to: input, query: "ALPHA") == [alpha, alphaTen])
        precondition(options.apply(to: input, query: "zulu") == [alpha])
        precondition(options.apply(to: input, query: "missing").isEmpty)

        options.source = .other
        alphaTen.isInstalled = true
        precondition(options.apply(to: input).isEmpty,
                     "Adoption must immediately remove an app from the other-apps filter")
        options.source = .homebrew
        precondition(options.apply(to: input) == [alpha, alphaTen, beta, tappedBeta])
        options = InstalledListOptions()
        precondition(options.apply(to: input) == [alpha, alphaTen, beta, tappedBeta],
                     "Resetting options must restore the complete alphabetized list")
    }

    @MainActor
    private static func testOwnershipReviewRaces(root: URL) async throws {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let originalBrew = defaults.value(for: Preferences.customUserBrewPath)
        let originalAppdir = defaults.value(for: Preferences.appdirPath)
        defer {
            defaults.setValue(originalBrew, for: Preferences.customUserBrewPath)
            defaults.setValue(originalAppdir, for: Preferences.appdirPath)
        }
        for source in ProtectedAppInstallation.Source.allCases {
            defaults.setValue(false, for: source.overridePreference)
        }
        let apps = root.appendingPathComponent("Review Current Apps")
        let app = apps.appendingPathComponent("Review Protected.app")
        let receipt = app.appendingPathComponent("Contents/_MASReceipt/receipt")
        let key = app.appendingPathComponent("Contents/Resources/setappPublicKey.pem")
        try fm.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: key.deletingLastPathComponent(), withIntermediateDirectories: true)
        let identifier = "org.fixture.review-protected"
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0
        ).write(to: app.appendingPathComponent("Contents/Info.plist"))
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        func record(_ token: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask", name: "Review Protected",
                descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Review Protected.app"]
            )
        }
        let assigned = root.appendingPathComponent("review-intune-assignment")
        let recordedAssigned = root.appendingPathComponent("review-recorded-intune-assignment")
        let recordedIdentifier = "org.fixture.review-recorded"
        let service = BrewService(
            notify: { _, _, _ in },
            intuneInventory: {
                var ids: Set<String> = []
                if FileManager.default.fileExists(atPath: assigned.path) { ids.insert(identifier) }
                if FileManager.default.fileExists(atPath: recordedAssigned.path) { ids.insert(recordedIdentifier) }
                return IntuneAppDetector.Snapshot(bundleIDs: ids)
            },
            artCraftInventory: { .empty }
        )
        let vm = CaskViewModel(record: record("review-race"), isInstalled: true)
        let argumentsURL = root.appendingPathComponent("arguments")
        let before = try Data(contentsOf: argumentsURL)
        let wait = root.appendingPathComponent("info-wait")
        let started = root.appendingPathComponent("info-started")
        func pausedOperation(isBatch: Bool, change: @MainActor () throws -> Void) async throws {
            if fm.fileExists(atPath: started.path) { try fm.removeItem(at: started) }
            try Data().write(to: wait)
            if isBatch { service.updateAll([vm]) } else { service.update(vm) }
            let deadline = Date().addingTimeInterval(5)
            while !fm.fileExists(atPath: started.path) && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let observed = fm.fileExists(atPath: started.path)
            if observed { try change() }
            try fm.removeItem(at: wait)
            _ = try await service.runSerialized { true }
            precondition(observed, "The fixture must pause inside metadata verification")
            let after = try Data(contentsOf: argumentsURL)
            precondition(vm.progressState.isFailed && after == before,
                         "Ownership/configuration changes during metadata must prevent the modifying command")
        }
        for source in [ProtectedAppInstallation.Source.appStore, .setapp, .intune] {
            let marker = source == .appStore ? receipt : source == .setapp ? key : assigned
            for isBatch in [false, true] {
                try await pausedOperation(isBatch: isBatch) { try Data().write(to: marker) }
                precondition(vm.protectedAppInstallation?.source == source)
                try fm.removeItem(at: marker)
            }
        }
        let alternate = root.appendingPathComponent("Other Selected Brew/bin/brew")
        try fm.createDirectory(at: alternate.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: alternate, withDestinationURL: URL(fileURLWithPath: originalBrew))
        for isBatch in [false, true] {
            try await pausedOperation(isBatch: isBatch) {
                defaults.setValue(alternate.path, for: Preferences.customUserBrewPath)
            }
            precondition(!fm.fileExists(atPath: alternate.deletingLastPathComponent().appendingPathComponent("arguments").path),
                         "A newly selected Homebrew must not execute a command verified by another installation")
            defaults.setValue(originalBrew, for: Preferences.customUserBrewPath)
        }
        let last = CaskViewModel(record: record("review-race-last"), isInstalled: true)
        let waitToken = root.appendingPathComponent("info-wait-token")
        try last.fullToken.write(to: waitToken, atomically: true, encoding: .utf8)
        for changeConfiguration in [false, true] {
            if fm.fileExists(atPath: started.path) { try fm.removeItem(at: started) }
            try Data().write(to: wait)
            service.updateAll([vm, last])
            let deadline = Date().addingTimeInterval(5)
            while !fm.fileExists(atPath: started.path) && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let observed = fm.fileExists(atPath: started.path)
            if changeConfiguration {
                defaults.setValue(alternate.path, for: Preferences.customUserBrewPath)
            } else {
                try Data().write(to: receipt)
            }
            try fm.removeItem(at: wait)
            _ = try await service.runSerialized { true }
            let after = try Data(contentsOf: argumentsURL)
            precondition(observed && vm.progressState.isFailed && last.progressState.isFailed && after == before,
                         "The first batch entry must be rechecked after the last entry's metadata await")
            defaults.setValue(originalBrew, for: Preferences.customUserBrewPath)
            if fm.fileExists(atPath: receipt.path) { try fm.removeItem(at: receipt) }
        }
        try fm.removeItem(at: waitToken)

        let recordedBrew = root.appendingPathComponent("Recorded Brew/bin/brew")
        try fm.createDirectory(at: recordedBrew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: recordedBrew, withDestinationURL: URL(fileURLWithPath: originalBrew))
        let oldApp = root.appendingPathComponent("Old Applications/Review Protected.app")
        let oldReceipt = oldApp.appendingPathComponent("Contents/_MASReceipt/receipt")
        let oldKey = oldApp.appendingPathComponent("Contents/Resources/setappPublicKey.pem")
        try fm.createDirectory(at: oldReceipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: oldKey.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": recordedIdentifier], format: .xml, options: 0
        ).write(to: oldApp.appendingPathComponent("Contents/Info.plist"))
        let recordedLink = root.appendingPathComponent("Recorded Brew/Caskroom/review-recorded/1.0/Nested/Review Protected.app")
        try fm.createDirectory(at: recordedLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: recordedLink, withDestinationURL: oldApp)
        try writeRecordedArtifacts(
            caskroom: recordedLink.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
            token: "review-recorded", version: "1.0", source: "Nested/Review Protected.app"
        )
        let loop = recordedLink.deletingLastPathComponent().appendingPathComponent("Loop")
        try fm.createSymbolicLink(at: loop, withDestinationURL: recordedLink.deletingLastPathComponent())
        defaults.setValue(recordedBrew.path, for: Preferences.customUserBrewPath)
        let targets = try InstalledAppLocator.recordedAppURLs(
            token: "review-recorded", caskroom: recordedBrew.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Caskroom")
        )
        precondition(targets == [oldApp.resolvingSymlinksInPath().standardizedFileURL])
        for source in [ProtectedAppInstallation.Source.appStore, .setapp, .intune] {
            let marker = source == .appStore ? oldReceipt : source == .setapp ? oldKey : recordedAssigned
            try Data().write(to: marker)
            let recorded = CaskViewModel(record: record("review-recorded"), isInstalled: true)
            service.uninstall(recorded)
            _ = try await service.runSerialized { true }
            precondition(recorded.progressState.isFailed && recorded.protectedAppInstallation?.source == source)
            service.updateAll([recorded])
            _ = try await service.runSerialized { true }
            precondition(recorded.progressState.isFailed && recorded.protectedAppInstallation?.source == source)
            precondition(!fm.fileExists(atPath: recordedBrew.deletingLastPathComponent().appendingPathComponent("arguments").path),
                         "Recorded custom-directory targets must retain source protection for single and bulk writes")
            try fm.removeItem(at: marker)
        }
    }

    @MainActor
    private static func testInstalledBundleProjection(root: URL) async throws {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let previousAppdir = defaults.value(for: Preferences.appdirPath)
        defer { defaults.setValue(previousAppdir, for: Preferences.appdirPath) }
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        let apps = root.appendingPathComponent("Canonical Apps")
        let shared = apps.appendingPathComponent("Shared.app")
        let aliasURL = apps.appendingPathComponent("Shared Alias.app")
        let separate = apps.appendingPathComponent("Separate.app")
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)
        try fm.createDirectory(at: separate, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: aliasURL, withDestinationURL: shared)
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        func record(_ token: String, bundle: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask", name: "Shared",
                descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: [bundle]
            )
        }
        let stable = record("review-shared", bundle: "Shared.app")
        let alias = record("review-shared@beta", bundle: "Shared Alias.app")
        let other = record("review-separate", bundle: "Separate.app")
        let registry = CaskViewModelRegistry()
        _ = registry.viewModels(for: [stable, alias, other])
        let tokens: Set<CaskId> = [stable.fullToken, alias.fullToken, other.fullToken]
        registry.markInstalled(tokens: tokens)
        let scan = try ExternalAppDetector.installations(
            catalog: [stable, alias, other], managedTokens: tokens, directories: [apps]
        )
        registry.markExternalInstallations(appURLs: scan.externalAppURLs, bundleURLs: scan.bundleURLs)
        precondition(registry.installedCount == 3 && registry.installedViewModels.count == 3,
                     "Deduplication must preserve every actual Homebrew receipt flag")
        precondition(registry.locallyInstalledCount == 2 && registry.locallyInstalledViewModels.count == 2,
                     "Installed rows/counts must collapse canonical managed aliases but preserve separate bundles")

        let adoption = CaskViewModelRegistry()
        let external = adoption.viewModel(for: stable)
        let managed = adoption.viewModel(for: alias)
        adoption.markExternalInstallations(appURLs: [stable.fullToken: shared], bundleURLs: scan.bundleURLs)
        let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        let beforeInstall = managed.metadataRevision
        await service.install(managed, confirmedConfiguration: .current).value
        precondition(managed.isInstalled && !managed.progressState.isFailed && external.isInstalledExternally)
        precondition(managed.metadataRevision == beforeInstall + 1)
        precondition(adoption.locallyInstalledViewModels == [managed] && adoption.locallyInstalledCount == 1,
                     "A single alias install must immediately replace the external row in the projection")
        adoption.markInstalled(tokens: [])
        adoption.markExternalInstallations(appURLs: [stable.fullToken: shared], bundleURLs: scan.bundleURLs)
        let managedTokens = root.appendingPathComponent("managed-tokens")
        try managed.fullToken.write(to: managedTokens, atomically: true, encoding: .utf8)
        defer { try! fm.removeItem(at: managedTokens) }
        service.installAll([managed])
        _ = try await service.runSerialized { true }
        precondition(managed.isInstalled && !managed.progressState.isFailed)
        precondition(managed.metadataRevision == beforeInstall + 2)
        precondition(adoption.locallyInstalledViewModels == [managed] && adoption.locallyInstalledCount == 1,
                     "Bulk reconciliation must immediately collapse the old external alias row")
        let plist = shared.appendingPathComponent("Contents/Info.plist")
        try fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "org.fixture.metadata-refresh", "CFBundleShortVersionString": "1.0"],
            format: .xml, options: 0
        ).write(to: plist)
        let plistMarker = root.appendingPathComponent("review-bundle-plist")
        let versionMarker = root.appendingPathComponent("review-bundle-version")
        try plist.path.write(to: plistMarker, atomically: true, encoding: .utf8)
        defer {
            try! fm.removeItem(at: plistMarker)
            try! fm.removeItem(at: versionMarker)
        }
        for (index, version) in ["2.0", "3.0", "4.0"].enumerated() {
            try version.write(to: versionMarker, atomically: true, encoding: .utf8)
            let revision = managed.metadataRevision
            if index == 0 {
                managed.isOutdated = true
                await service.update(managed).value
            } else if index == 1 {
                service.reinstall(managed)
                _ = try await service.runSerialized { true }
            } else {
                service.updateAll([managed])
                _ = try await service.runSerialized { true }
            }
            let metadata = try InstalledAppMetadata.read(at: shared)
            precondition(!managed.progressState.isFailed && managed.metadataRevision == revision + 1 && metadata.version == version,
                         "Successful update/reinstall/bulk operations must invalidate details and expose fresh bundle versions")
        }
        let revision = managed.metadataRevision
        let failedMetadata = root.appendingPathComponent("info-fail")
        try Data().write(to: failedMetadata)
        await service.update(managed).value
        precondition(managed.progressState.isFailed && managed.metadataRevision == revision,
                     "A rejected operation must not masquerade as a successful metadata refresh")
        try fm.removeItem(at: failedMetadata)
        service.uninstall(managed)
        _ = try await service.runSerialized { true }
        precondition(!managed.isInstalled && managed.metadataRevision == revision + 1)
    }

    @MainActor
    private static func testAdoptionRaces(
        root: URL, loader: CaskDataLoader, registry: CaskViewModelRegistry,
        vm: CaskViewModel, appURL: URL, customApps: URL, service: BrewService
    ) async throws {
        let defaults = UserDefaults.standard
        let argumentsURL = root.appendingPathComponent("arguments")
        let before = try Data(contentsOf: argumentsURL)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        defaults.setValue(appURL.deletingLastPathComponent().path, for: Preferences.appdirPath)
        let managedMarker = root.appendingPathComponent("managed")
        if FileManager.default.fileExists(atPath: managedMarker.path) {
            try FileManager.default.removeItem(at: managedMarker)
        }
        vm.isInstalled = false
        vm.externalAppURL = nil
        await service.install(vm).value
        precondition(
            vm.externalAppURL == appURL && vm.progressState.isFailed,
            "Unconfirmed detection failed: state=\(vm.progressState), bundles=\(vm.appBundleNames), url=\(String(describing: vm.externalAppURL))"
        )
        let afterUnconfirmed = try Data(contentsOf: argumentsURL)
        precondition(afterUnconfirmed == before,
                     "Install before the first scan must not silently adopt a local app")

        let configuration = BrewOperationConfiguration.current
        let manager = CaskManager(dataLoader: loader, registry: registry, brewService: service)
        manager.confirmAdoption(vm)
        let confirmation = manager.alert.current!
        let taskIDs = service.activeTasks.map(\.id)
        defaults.setValue(customApps.path, for: Preferences.appdirPath)
        confirmation.actions.first?.handler?()
        precondition(service.activeTasks.map(\.id) == taskIDs, "A changed command preview must require confirmation again")
        defaults.setValue(appURL.deletingLastPathComponent().path, for: Preferences.appdirPath)

        var resumeQueue: CheckedContinuation<Void, Never>?
        let blocker = Task {
            try await service.runSerialized {
                await withCheckedContinuation { resumeQueue = $0 }
                return true
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while resumeQueue == nil && Date() < deadline { await Task.yield() }
        precondition(resumeQueue != nil)
        let queued = service.install(vm, confirmedConfiguration: configuration)
        defaults.setValue(customApps.path, for: Preferences.appdirPath)
        resumeQueue?.resume()
        _ = try await blocker.value
        await queued.value
        precondition(vm.progressState.isFailed)
        let afterConfigurationChange = try Data(contentsOf: argumentsURL)
        precondition(afterConfigurationChange == before,
                     "Queued adoption must reject changed application-directory settings")

        defaults.setValue(appURL.deletingLastPathComponent().path, for: Preferences.appdirPath)
        let changedBrew = root.appendingPathComponent("other-brew")
        defaults.setValue(changedBrew.path, for: Preferences.customUserBrewPath)
        do {
            try configuration.validateCurrent()
            preconditionFailure("Changing the selected Homebrew must invalidate the preview")
        } catch CaskAdoptionError.configurationChanged { }
        defaults.setValue(root.appendingPathComponent("bin/brew").path, for: Preferences.customUserBrewPath)

        vm.externalAppURL = appURL
        await service.install(vm, confirmedConfiguration: .current) {
            throw CaskAdoptionError.notManaged
        }.value
        guard case .failed(let output) = vm.progressState else {
            preconditionFailure("Reconciliation errors must remain failures")
        }
        precondition(output.contains("sample was successfully installed!")
                     && output.contains("fixture success stderr")
                     && output.contains(CaskAdoptionError.notManaged.localizedDescription),
                     "Reconciliation must preserve the successful command's output and append its error")

        let gate = ScanGate()
        let fullToken = vm.fullToken
        let oldScan = Task {
            try await loader.refreshExternalInstallations { _, _, _ in
                await gate.wait()
                return [fullToken: appURL]
            }
        }
        let scanDeadline = Date().addingTimeInterval(5)
        while !(await gate.isWaiting) && Date() < scanDeadline { await Task.yield() }
        let waiting = await gate.isWaiting
        precondition(waiting)
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        manager.applyExternalAppDetectionSetting()
        defaults.setValue(customApps.path, for: Preferences.appdirPath)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        let newerApp = customApps.appendingPathComponent(appURL.lastPathComponent)
        try FileManager.default.createDirectory(at: newerApp, withIntermediateDirectories: true)
        try await loader.refreshExternalInstallations { _, _, _ in [fullToken: newerApp] }
        defaults.setValue(appURL.deletingLastPathComponent().path, for: Preferences.appdirPath)
        await gate.release()
        do {
            try await oldScan.value
        } catch is CancellationError { }
        precondition(vm.externalAppURL == newerApp,
                     "An old scan must not win after detection was disabled and re-enabled, even with restored settings")
    }

    @MainActor
    private static func testOutdatedRefreshLifetime(
        root: URL, loader: CaskDataLoader, registry: CaskViewModelRegistry, service: BrewService
    ) async throws {
        let manager = CaskManager(dataLoader: loader, registry: registry, brewService: service)
        let fm = FileManager.default
        let failure = root.appendingPathComponent("fail-outdated")
        try Data().write(to: failure)
        do {
            try await manager.refreshOutdated()
            preconditionFailure("The fixture's failed update check must throw")
        } catch { }
        precondition(manager.outdatedRefreshFailed && !manager.isRefreshingOutdated)
        try fm.removeItem(at: failure)
        try Data().write(to: root.appendingPathComponent("pause-outdated"))
        let task = Task { try await manager.refreshOutdated() }
        let started = root.appendingPathComponent("outdated-started")
        let deadline = Date().addingTimeInterval(5)
        while !fm.fileExists(atPath: started.path) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fm.fileExists(atPath: started.path) && manager.isRefreshingOutdated)
        try Data().write(to: root.appendingPathComponent("resume-outdated"))
        try await task.value
        precondition(!manager.isRefreshingOutdated && !manager.outdatedRefreshFailed)
    }

    @MainActor
    private static func testManagedSiblingOwnership(root: URL) async throws {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let oldBrew = defaults.value(for: Preferences.customUserBrewPath)
        let oldOption = defaults.value(for: Preferences.brewPathOption)
        let oldAppdir = defaults.value(for: Preferences.appdirPath)
        let oldAppdirOn = defaults.value(for: Preferences.appdirOn)
        let oldDetection = defaults.value(for: Preferences.detectExternallyInstalledApps)
        let oldOffer = defaults.value(for: Preferences.offerHomebrewManagement)
        defer {
            defaults.setValue(oldBrew, for: Preferences.customUserBrewPath)
            defaults.setValue(oldOption, for: Preferences.brewPathOption)
            defaults.setValue(oldAppdir, for: Preferences.appdirPath)
            defaults.setValue(oldAppdirOn, for: Preferences.appdirOn)
            defaults.setValue(oldDetection, for: Preferences.detectExternallyInstalledApps)
            defaults.setValue(oldOffer, for: Preferences.offerHomebrewManagement)
        }
        let prefix = root.appendingPathComponent("Managed sibling")
        let brew = prefix.appendingPathComponent("bin/brew")
        let managedDirectory = prefix.appendingPathComponent("Managed Apps")
        let externalDirectory = prefix.appendingPathComponent("External Apps")
        let managedApp = managedDirectory.appendingPathComponent("Shared.app")
        let externalApp = externalDirectory.appendingPathComponent("Shared.app")
        let source = prefix.appendingPathComponent("Caskroom/stable/1/Payload/Source.app")
        let metadata = prefix.appendingPathComponent("Caskroom/stable/.metadata/1/1/Casks")
        for directory in [brew.deletingLastPathComponent(), managedApp, externalApp,
                          source.deletingLastPathComponent(), metadata] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try fm.createSymbolicLink(at: source, withDestinationURL: managedApp)
        let recorded = ["artifacts": [["app": ["Payload/Source.app", ["target": "Shared.app"]]]]]
        try JSONSerialization.data(withJSONObject: recorded).write(to: metadata.appendingPathComponent("stable.json"))
        let script = """
        #!/bin/sh
        dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
        case "$1" in
          --version) echo "Homebrew fixture" ;;
          --caskroom) echo "$dir/Caskroom" ;;
          list) echo stable ;;
          info) echo '{"casks":[{"token":"beta","full_token":"beta","tap":"homebrew/cask","homepage":"https://example.test/","url":"https://example.test/app.dmg","artifacts":[{"app":["Shared.app"]}],"deprecated":false,"disabled":false}]}' ;;
          install) printf '%s\\n' "$@" > "$dir/arguments" ;;
          *) exit 2 ;;
        esac
        """
        try script.write(to: brew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew.path)
        defaults.setValue(BrewPaths.PathOption.custom.rawValue, for: Preferences.brewPathOption)
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        defaults.setValue(true, for: Preferences.appdirOn)
        defaults.setValue(managedDirectory.path, for: Preferences.appdirPath)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        let nestedBrew = prefix.appendingPathComponent("Homebrew/bin/brew")
        try fm.createDirectory(at: nestedBrew.deletingLastPathComponent(), withIntermediateDirectories: true)
        let nestedScript = """
        #!/bin/sh
        prefix="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
        if [ "$1" = "--caskroom" ]; then
          if [ -f "$prefix/invalid-caskroom" ]; then echo relative; else echo "$prefix/Caskroom"; fi
        else exit 2; fi
        """
        try nestedScript.write(to: nestedBrew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: nestedBrew.path)
        defaults.setValue(nestedBrew.path, for: Preferences.customUserBrewPath)
        let pinned = try await BrewOperationConfiguration.current.resolvingCaskroom()
        precondition(pinned.caskroom == prefix.appendingPathComponent("Caskroom").standardizedFileURL)
        let pinnedTargets = try InstalledAppLocator.recordedAppURLs(
            token: "stable", caskroom: pinned.caskroom!, requireRecordedOwnership: true
        )
        precondition(pinnedTargets == [managedApp.resolvingSymlinksInPath().standardizedFileURL],
                     "A nested Homebrew executable must use its reported Caskroom")
        let metadataTarget = try InstalledAppLocator.metadataAppURL(
            token: "stable", displayName: "Shared", preferredURL: externalApp,
            isManaged: true, configuration: pinned
        )
        precondition(metadataTarget == managedApp.resolvingSymlinksInPath().standardizedFileURL,
                     "Metadata lookup must use the selected Homebrew's reported Caskroom")
        let protectedTarget = try InstalledAppLocator.metadataAppURL(
            token: "stable", displayName: "Shared", preferredURL: externalApp,
            isManaged: false, configuration: .current
        )
        precondition(protectedTarget == externalApp, "Protected copies must retain their selected URL")
        let invalidCaskroom = prefix.appendingPathComponent("invalid-caskroom")
        try Data().write(to: invalidCaskroom)
        let stillPinned = try await pinned.resolvingCaskroom()
        precondition(stillPinned.caskroom == pinned.caskroom, "An operation must retain its captured Caskroom")
        do {
            _ = try await BrewOperationConfiguration.current.resolvingCaskroom()
            preconditionFailure("An invalid reported Caskroom must fail closed")
        } catch CaskAdoptionError.installationTargetsUnavailable { }
        try fm.removeItem(at: invalidCaskroom)
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        do {
            _ = try await pinned.resolvingCaskroom()
            preconditionFailure("Pinned Caskroom configuration must expire when Homebrew changes")
        } catch CaskAdoptionError.configurationChanged { }
        func record(_ token: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask", name: "Shared",
                descriptionText: "", homepageURL: nil, pkgInstaller: false, warningType: nil,
                warningDate: nil, warningReason: nil, downloadsIn365days: 0, appBundleNames: ["Shared.app"]
            )
        }
        let stable = record("stable")
        let beta = record("beta")
        let recordedURLs = [stable.fullToken: [managedApp]]
        let sharedOnly = try ExternalAppDetector.installations(
            catalog: [stable, beta], managedTokens: [stable.fullToken], directories: [managedDirectory],
            recordedAppURLs: recordedURLs
        )
        precondition(sharedOnly.externalAppURLs.isEmpty, "A sibling must not claim a Homebrew-owned bundle")
        let alias = prefix.appendingPathComponent("Managed Alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: managedDirectory)
        let separate = try ExternalAppDetector.installations(
            catalog: [beta], managedTokens: [stable.fullToken], directories: [alias, externalDirectory],
            recordedAppURLs: recordedURLs
        )
        precondition(separate.externalAppURLs[beta.fullToken]?.standardizedFileURL == externalApp.standardizedFileURL,
                     "An uncataloged owner and alias must not hide a distinct external copy")
        let pool = try DatabasePool(path: prefix.appendingPathComponent("catalog.sqlite").path)
        try AppDatabase.migrator().migrate(pool)
        try await pool.write { db in try beta.insert(db) }
        let registry = CaskViewModelRegistry()
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: pool), registry: registry,
            intuneInventory: { .empty }, artCraftInventory: { .empty }
        )
        _ = registry.viewModel(for: beta)
        try await loader.refreshInstalled()
        precondition(registry.externalInstalledCount == 0,
                     "An uncataloged managed cask must suppress its owned bundle")
        let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        let sibling = CaskViewModel(record: beta)
        let arguments = prefix.appendingPathComponent("arguments")
        for selected in [externalApp, managedApp] {
            sibling.externalAppURL = selected
            await service.install(sibling, confirmedConfiguration: .current).value
            precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                         "A managed destination or stale selected copy must block adoption")
        }
        service.installAll([sibling])
        _ = try await service.runSerialized { true }
        precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Bulk installation must block another cask's target")
        defaults.setValue(externalDirectory.path, for: Preferences.appdirPath)
        sibling.externalAppURL = externalApp
        await service.install(sibling, confirmedConfiguration: .current).value
        precondition(fm.fileExists(atPath: arguments.path), "A distinct target remains eligible for adoption")
        try fm.removeItem(at: arguments)
        try fm.removeItem(at: metadata.appendingPathComponent("stable.json"))
        await service.install(sibling, confirmedConfiguration: .current).value
        precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Unknown managed ownership must fail closed")
        try Data("cask fixture".utf8).write(to: metadata.appendingPathComponent("stable.rb"))
        try fm.createSymbolicLink(at: prefix.appendingPathComponent("Caskroom/stable/1/Shared.app"),
                                  withDestinationURL: managedApp)
        let unrelated = CaskRecord(
            token: "unrelated", fullToken: "unrelated", tap: "homebrew/cask", name: "Unrelated",
            descriptionText: "", homepageURL: nil, pkgInstaller: false, warningType: nil,
            warningDate: nil, warningReason: nil, downloadsIn365days: 0, appBundleNames: ["Unrelated.app"]
        )
        try fm.createDirectory(at: externalDirectory.appendingPathComponent("Unrelated.app"),
                               withIntermediateDirectories: true)
        try await pool.write { db in
            try stable.insert(db)
            try unrelated.insert(db)
        }
        try await loader.refreshInstalled()
        precondition(registry.viewModel(for: unrelated).isInstalledExternally,
                     "A legacy Ruby-only receipt must not block unrelated external discovery")
        await service.install(sibling, confirmedConfiguration: .current).value
        precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "A legacy Ruby-only receipt must still block unverifiable mutation")
        try Data("invalid metadata".utf8).write(to: metadata.appendingPathComponent("stable.json"))
        try await loader.refreshInstalled()
        precondition(registry.viewModel(for: unrelated).isInstalledExternally,
                     "Malformed metadata for one managed cask must not abort unrelated discovery")
        let receiptRoom = prefix.appendingPathComponent("Caskroom/receipt-cask")
        let staged = receiptRoom.appendingPathComponent("1/Payload")
        let receiptMetadata = receiptRoom.appendingPathComponent(".metadata/1/1/Casks")
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        try fm.createDirectory(at: receiptMetadata, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: staged.appendingPathComponent("Source.app"), withDestinationURL: managedApp)
        try JSONSerialization.data(withJSONObject: ["url_specs": ["only_path": "Payload"]])
            .write(to: receiptMetadata.appendingPathComponent("receipt-cask.json"))
        try JSONSerialization.data(withJSONObject: ["uninstall_artifacts": [["app": ["Source.app"]]]])
            .write(to: receiptRoom.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))
        let receiptTargets = try InstalledAppLocator.recordedAppURLs(
            token: "receipt-cask", caskroom: prefix.appendingPathComponent("Caskroom"), requireRecordedOwnership: true
        )
        precondition(receiptTargets == [managedApp.resolvingSymlinksInPath().standardizedFileURL])
        try fm.moveItem(at: receiptMetadata.appendingPathComponent("receipt-cask.json"),
                        to: receiptMetadata.appendingPathComponent("receipt-cask.internal.json"))
        let internalTargets = try InstalledAppLocator.recordedAppURLs(
            token: "receipt-cask", caskroom: prefix.appendingPathComponent("Caskroom"), requireRecordedOwnership: true
        )
        precondition(internalTargets == receiptTargets, "Internal JSON must preserve staged-path metadata")
        try fm.removeItem(at: receiptMetadata.appendingPathComponent("receipt-cask.internal.json"))
        try JSONSerialization.data(withJSONObject: ["url_specs": ["only_path": "../outside"]])
            .write(to: receiptMetadata.appendingPathComponent("receipt-cask.json"))
        do {
            _ = try InstalledAppLocator.recordedAppURLs(token: "receipt-cask", caskroom: prefix.appendingPathComponent("Caskroom"))
            preconditionFailure("An unsafe recorded source path must fail closed")
        } catch CaskAdoptionError.installationTargetsUnavailable { }
        try fm.removeItem(at: receiptMetadata.appendingPathComponent("receipt-cask.json"))
        try Data("cask fixture".utf8).write(to: receiptMetadata.appendingPathComponent("receipt-cask.rb"))
        let directLink = receiptRoom.appendingPathComponent("1/Source.app")
        try fm.createSymbolicLink(at: directLink, withDestinationURL: managedApp)
        let rubyTargets = try InstalledAppLocator.recordedAppURLs(
            token: "receipt-cask", caskroom: prefix.appendingPathComponent("Caskroom"), requireRecordedOwnership: true
        )
        precondition(rubyTargets == [managedApp.resolvingSymlinksInPath().standardizedFileURL])
        try fm.removeItem(at: directLink)
        try fm.createSymbolicLink(at: directLink, withDestinationURL: prefix.appendingPathComponent("Missing.app"))
        let missingTargets = try InstalledAppLocator.recordedAppURLs(
            token: "receipt-cask", caskroom: prefix.appendingPathComponent("Caskroom"), requireRecordedOwnership: true
        )
        precondition(missingTargets.isEmpty, "A recorded link to a missing app must not block other casks")
        try fm.removeItem(at: directLink)
        do {
            _ = try InstalledAppLocator.recordedAppURLs(token: "receipt-cask", caskroom: prefix.appendingPathComponent("Caskroom"))
            preconditionFailure("Ruby-only metadata with an unverifiable staged link must fail closed")
        } catch CaskAdoptionError.installationTargetsUnavailable { }
    }

    @MainActor
    private static func testDistinctInstallationIdentities(root: URL) async throws {
        let fm = FileManager.default
        let system = root.appendingPathComponent("Identity System Apps")
        let user = root.appendingPathComponent("Identity User Apps")
        let systemApp = system.appendingPathComponent("Shared.app")
        let userApp = user.appendingPathComponent("Shared.app")
        try fm.createDirectory(at: systemApp, withIntermediateDirectories: true)
        try fm.createDirectory(at: userApp, withIntermediateDirectories: true)
        func record(_ token: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask", name: "Shared",
                descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Shared.app"]
            )
        }
        let stable = record("identity-shared")
        let beta = record("identity-shared@beta")
        let oldApp = system.appendingPathComponent("Old.app")
        try fm.createDirectory(at: oldApp, withIntermediateDirectories: true)
        let renamed = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [stable.fullToken], directories: [user],
            recordedAppURLs: [stable.fullToken: [oldApp]]
        )
        precondition(renamed.multipleCopyTokens.contains(stable.fullToken)
                     && renamed.bundleURLs[stable.fullToken] == oldApp.resolvingSymlinksInPath().standardizedFileURL
                     && renamed.additionalInstallations[stable.fullToken]?.map(\.url)
                        == [userApp.resolvingSymlinksInPath().standardizedFileURL],
                     "A recorded old target and a separate renamed current target are distinct copies")
        let recordedOnly = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [stable.fullToken], directories: [],
            recordedAppURLs: [stable.fullToken: [systemApp, userApp, systemApp]]
        )
        precondition(recordedOnly.multipleCopyTokens.contains(stable.fullToken)
                     && recordedOnly.bundleURLs[stable.fullToken] == systemApp.resolvingSymlinksInPath().standardizedFileURL
                     && recordedOnly.additionalInstallations[stable.fullToken]?.map(\.url)
                        == [userApp.resolvingSymlinksInPath().standardizedFileURL],
                     "Recorded bundles outside scan roots must appear once per physical copy")
        let aliasDirectory = root.appendingPathComponent("Identity Alias Apps")
        try fm.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: aliasDirectory.appendingPathComponent("Shared.app"), withDestinationURL: systemApp)
        let aliasScan = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [], directories: [system, aliasDirectory]
        )
        precondition(aliasScan.additionalInstallations.isEmpty && aliasScan.multipleCopyTokens.isEmpty,
                     "Two paths to the same canonical bundle must not produce separate copies")
        let single = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [], directories: [system, user]
        )
        let oneCaskRegistry = CaskViewModelRegistry()
        let primary = oneCaskRegistry.viewModel(for: stable)
        oneCaskRegistry.markExternalInstallations(
            appURLs: single.externalAppURLs, bundleURLs: single.bundleURLs,
            copies: single.additionalInstallations, multipleCopyTokens: single.multipleCopyTokens
        )
        let rows = oneCaskRegistry.locallyInstalledViewModels
        precondition(rows.count == 2 && oneCaskRegistry.locallyInstalledCount == 2
                     && oneCaskRegistry.externalInstalledCount == 2
                     && Set(rows.map(\.cardIdentity)).count == 2,
                     "One cask with two physical copies must produce two distinct external rows and counts")
        precondition(Set(rows.compactMap { $0.selectedInstallationURL?.path }) == [systemApp.path, userApp.path],
                     "Each copy must open and describe its own path")
        precondition(primary.hasMultipleInstalledCopies
                     && rows.allSatisfy { $0.homebrewManagementBlockReason != nil },
                     "Ambiguous copies must not offer a Homebrew operation targeting another path")
        let copy = rows.first { $0.isAdditionalInstalledCopy }!
        let blockedService = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        await blockedService.install(copy, confirmedConfiguration: .current).value
        precondition(copy.progressState.isFailed, "A per-copy Homebrew action must fail closed even when invoked directly")
        try fm.removeItem(at: userApp)
        let remaining = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [], directories: [system, user]
        )
        oneCaskRegistry.markExternalInstallations(
            appURLs: remaining.externalAppURLs, bundleURLs: remaining.bundleURLs,
            copies: remaining.additionalInstallations, multipleCopyTokens: remaining.multipleCopyTokens
        )
        precondition(oneCaskRegistry.locallyInstalledCount == 1 && !primary.hasMultipleInstalledCopies
                     && !copy.isLocallyInstalled,
                     "A removed copy must disappear and release the ambiguity block on refresh")
        try fm.createDirectory(at: userApp, withIntermediateDirectories: true)
        let userReceipt = userApp.appendingPathComponent("Contents/_MASReceipt/receipt")
        try fm.createDirectory(at: userReceipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: userReceipt)
        let mixedSources = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [], directories: [system, user]
        )
        oneCaskRegistry.markExternalInstallations(
            appURLs: mixedSources.externalAppURLs, appStoreAppURLs: mixedSources.appStoreAppURLs,
            bundleURLs: mixedSources.bundleURLs, copies: mixedSources.additionalInstallations,
            multipleCopyTokens: mixedSources.multipleCopyTokens,
            selectedCopyProtection: mixedSources.selectedCopyProtection
        )
        let sourceRows = oneCaskRegistry.locallyInstalledViewModels
        let appStoreRows = InstalledListOptions(source: .appStore).apply(to: sourceRows)
        let otherRows = InstalledListOptions(source: .other).apply(to: sourceRows)
        precondition(appStoreRows.count == 1 && appStoreRows[0].selectedInstallationURL?.path == userApp.path
                     && otherRows.count == 1 && otherRows[0].selectedInstallationURL?.path == systemApp.path,
                     "Ownership filtering must classify each physical copy, not another copy's source")
        precondition(appStoreRows[0].installedManagementSourceName == ProtectedAppInstallation.Source.appStore.name
                     && otherRows[0].installedManagementSourceName == String(localized: "Unknown"),
                     "Details must describe the selected copy's source rather than another copy's protection")
        let managedMixed = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [stable.fullToken], directories: [system, user],
            recordedAppURLs: [stable.fullToken: [systemApp]]
        )
        oneCaskRegistry.markInstalled(tokens: [stable.fullToken])
        oneCaskRegistry.markExternalInstallations(
            appURLs: managedMixed.externalAppURLs, appStoreAppURLs: managedMixed.appStoreAppURLs,
            bundleURLs: managedMixed.bundleURLs, copies: managedMixed.additionalInstallations,
            multipleCopyTokens: managedMixed.multipleCopyTokens,
            selectedCopyProtection: managedMixed.selectedCopyProtection
        )
        oneCaskRegistry.clearExternalInstallations()
        precondition(primary.installedManagementSourceName == String(localized: "Homebrew")
                     && InstalledListOptions(source: .homebrew).apply(to: [primary]) == [primary]
                     && InstalledListOptions(source: .appStore).apply(to: [primary]).isEmpty
                     && primary.protectedAppInstallation?.source == .appStore,
                     "Hiding external copies must preserve selected provenance and aggregate write protection")
        oneCaskRegistry.updateManagedBundleURLs(
            managedMixed.bundleURLs, multipleCopyTokens: managedMixed.multipleCopyTokens,
            selectedCopyProtection: managedMixed.selectedCopyProtection
        )
        precondition(primary.installedManagementSourceName == String(localized: "Homebrew")
                     && primary.protectedAppInstallation?.source == .appStore,
                     "A disabled-detection refresh must retain per-copy provenance and aggregate protection")
        try fm.removeItem(at: userReceipt)
        let oneManaged = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [stable.fullToken], directories: [system, user],
            recordedAppURLs: [stable.fullToken: [systemApp]]
        )
        oneCaskRegistry.markInstalled(tokens: [stable.fullToken])
        oneCaskRegistry.markExternalInstallations(
            appURLs: oneManaged.externalAppURLs, bundleURLs: oneManaged.bundleURLs,
            copies: oneManaged.additionalInstallations, multipleCopyTokens: oneManaged.multipleCopyTokens,
            selectedCopyProtection: oneManaged.selectedCopyProtection
        )
        let managedRows = oneCaskRegistry.locallyInstalledViewModels
        precondition(managedRows.count == 2 && managedRows.filter(\.isInstalled).count == 1
                     && managedRows.filter(\.isInstalledExternally).count == 1
                     && oneCaskRegistry.externalInstalledCount == 1,
                     "A Homebrew receipt must not make a separate unrecorded copy managed")
        let external = try ExternalAppDetector.installations(
            catalog: [stable, beta], managedTokens: [], directories: [system, user]
        )
        precondition(Set(external.externalAppURLs.values.map {
            $0.resolvingSymlinksInPath().standardizedFileURL
        }) == [systemApp.resolvingSymlinksInPath(), userApp.resolvingSymlinksInPath()],
                     "Shared artifact names must not hide a distinct installation in another app directory")
        let protected = root.appendingPathComponent("Identity Store Apps/Shared.app")
        let receipt = protected.appendingPathComponent("Contents/_MASReceipt/receipt")
        try fm.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: receipt)
        let tokens: Set<CaskId> = [stable.fullToken, beta.fullToken]
        let managed = try ExternalAppDetector.installations(
            catalog: [stable, beta], managedTokens: tokens,
            directories: [protected.deletingLastPathComponent(), system, user],
            recordedAppURLs: [stable.fullToken: [systemApp], beta.fullToken: [userApp]]
        )
        precondition(managed.appStoreAppURLs.count == 2,
                     "Conservative cross-location protection must remain attached to both matching casks")
        precondition(managed.bundleURLs[stable.fullToken] == systemApp.resolvingSymlinksInPath().standardizedFileURL
                     && managed.bundleURLs[beta.fullToken] == userApp.resolvingSymlinksInPath().standardizedFileURL,
                     "A third protected copy must not replace distinct recorded installation identities")
        let registry = CaskViewModelRegistry()
        _ = registry.viewModels(for: [stable, beta])
        registry.markInstalled(tokens: tokens)
        registry.markExternalInstallations(
            appURLs: managed.externalAppURLs, appStoreAppURLs: managed.appStoreAppURLs,
            bundleURLs: managed.bundleURLs
        )
        precondition(registry.installedCount == 2 && registry.locallyInstalledCount == 2,
                     "Distinct recorded bundles must remain separate rows and counts despite shared protection")
        for vm in registry.locallyInstalledViewModels {
            precondition(vm.selectedInstallationURL?.path == managed.bundleURLs[vm.fullToken]?.path
                         && vm.selectedInstallationURL?.path != protected.path,
                         "Launching or displaying a row must use its selected bundle, not other protection evidence")
        }
    }

    @MainActor
    private static func testManagedIdentityWithDetectionDisabled(root: URL) async throws {
        let defaults = UserDefaults.standard
        let previousBrew = defaults.value(for: Preferences.customUserBrewPath)
        let previousDetection = defaults.value(for: Preferences.detectExternallyInstalledApps)
        defer {
            defaults.setValue(previousBrew, for: Preferences.customUserBrewPath)
            defaults.setValue(previousDetection, for: Preferences.detectExternallyInstalledApps)
        }
        let fm = FileManager.default
        let prefix = root.appendingPathComponent("Disabled Detection Receipts")
        let brew = prefix.appendingPathComponent("bin/brew")
        let app = prefix.appendingPathComponent("Apps/Shared.app")
        try fm.createDirectory(at: brew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try "#!/bin/sh\nif [ \"$1\" = list ]; then printf 'stable\\nbeta\\n'; elif [ \"$1\" = --caskroom ]; then printf '%s\\n' \"$(dirname \"$(dirname \"$0\")\")/Caskroom\"; fi\n".write(
            to: brew, atomically: true, encoding: .utf8
        )
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew.path)
        for token in ["stable", "beta"] {
            let directory = prefix.appendingPathComponent("Caskroom/\(token)/1")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: directory.appendingPathComponent("Shared.app"), withDestinationURL: app)
            try writeRecordedArtifacts(caskroom: directory.deletingLastPathComponent(), token: token,
                                       version: "1", source: "Shared.app")
        }
        func record(_ token: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask", name: "Shared",
                descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: ["Shared.app"]
            )
        }
        let pool = try DatabasePool(path: prefix.appendingPathComponent("catalog.sqlite").path)
        try AppDatabase.migrator().migrate(pool)
        let stable = record("stable")
        let beta = record("beta")
        try await pool.write { db in
            try stable.insert(db)
            try beta.insert(db)
        }
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        let registry = CaskViewModelRegistry()
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: pool), registry: registry,
            intuneInventory: { throw CaskAdoptionError.intuneInventoryUnavailable },
            artCraftInventory: { .empty }
        )
        try await loader.refreshInstalled()
        precondition(registry.installedCount == 2 && registry.locallyInstalledCount == 1
                     && registry.externalInstalledCount == 0,
                     "Managed aliases must deduplicate from recorded bundle identity even when external detection is disabled")
        let storeApp = prefix.appendingPathComponent("User Apps/Shared.app")
        let storeReceipt = storeApp.appendingPathComponent("Contents/_MASReceipt/receipt")
        try fm.createDirectory(at: storeReceipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: storeReceipt)
        let provenanceRegistry = CaskViewModelRegistry()
        let selected = provenanceRegistry.viewModel(for: stable)
        provenanceRegistry.markInstalled(tokens: [stable.fullToken])
        let initialSources = try ExternalAppDetector.installations(
            catalog: [stable], managedTokens: [stable.fullToken],
            directories: [app.deletingLastPathComponent(), storeApp.deletingLastPathComponent()],
            recordedAppURLs: [stable.fullToken: [app]]
        )
        provenanceRegistry.markExternalInstallations(
            appURLs: initialSources.externalAppURLs, appStoreAppURLs: initialSources.appStoreAppURLs,
            bundleURLs: initialSources.bundleURLs, copies: initialSources.additionalInstallations,
            multipleCopyTokens: initialSources.multipleCopyTokens,
            selectedCopyProtection: initialSources.selectedCopyProtection
        )
        let provenanceLoader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: pool), registry: provenanceRegistry,
            intuneInventory: { .empty }, artCraftInventory: { .empty }
        )
        try await provenanceLoader.refreshExternalInstallations()
        precondition(selected.installedManagementSourceName == String(localized: "Homebrew")
                     && selected.protectedAppInstallation?.source == .appStore
                     && provenanceRegistry.locallyInstalledCount == 1,
                     "A disabled-detection refresh must retain provenance for the selected Homebrew copy")
        let stableLink = prefix.appendingPathComponent("Caskroom/stable/1/Shared.app")
        try fm.removeItem(at: stableLink)
        try fm.createSymbolicLink(at: stableLink, withDestinationURL: storeApp)
        try await provenanceLoader.refreshExternalInstallations()
        precondition(selected.installedManagementSourceName == ProtectedAppInstallation.Source.appStore.name
                     && provenanceRegistry.locallyInstalledCount == 1
                     && provenanceRegistry.externalInstalledCount == 0,
                     "A changed recorded copy must refresh its source without exposing external rows")
        let newSourceRegistry = CaskViewModelRegistry()
        let newlyProtected = newSourceRegistry.viewModel(for: stable)
        newSourceRegistry.markInstalled(tokens: [stable.fullToken])
        newlyProtected.installedBundleURL = app
        newlyProtected.isOutdated = true
        let newSourceLoader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: pool), registry: newSourceRegistry,
            intuneInventory: { .empty }, artCraftInventory: { .empty }
        )
        try await newSourceLoader.refreshExternalInstallations()
        precondition(newlyProtected.protectedAppInstallation?.source == .appStore
                     && newlyProtected.isManagementProtected && !newlyProtected.isOutdated,
                     "A newly detected source must immediately protect actions and clear updates")
        try fm.removeItem(at: stableLink)
        try fm.createSymbolicLink(at: stableLink, withDestinationURL: app)
        let secondPrefix = root.appendingPathComponent("Second Homebrew Receipts")
        let secondBrew = secondPrefix.appendingPathComponent("bin/brew")
        try fm.createDirectory(at: secondBrew.deletingLastPathComponent(), withIntermediateDirectories: true)
        let secondFixture = """
        #!/bin/sh
        prefix="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
        case "$1" in
          --version) echo "Homebrew fixture" ;;
          --caskroom) echo "$prefix/Caskroom" ;;
          list)
            touch "$prefix/list-started"
            while [ -f "$prefix/pause-list" ]; do sleep 0.01; done
            if [ -f "$prefix/fail-list" ]; then echo "receipt query failed" >&2; exit 1; fi ;;
          outdated) touch "$prefix/outdated-started" ;;
          uninstall) touch "$prefix/uninstall-started" ;;
        esac
        """
        try secondFixture.write(to: secondBrew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: secondBrew.path)
        let pause = secondPrefix.appendingPathComponent("pause-list")
        try Data().write(to: pause)
        let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        let manager = CaskManager(dataLoader: loader, registry: registry, brewService: service)
        let vm = registry.viewModel(for: stable)
        let settingsAlert = AlertManager()
        manager.selectedAppDetails = vm
        defaults.setValue(secondBrew.path + "-partial", for: Preferences.customUserBrewPath)
        manager.selectedHomebrewDidChange(surfacingErrorsIn: settingsAlert)
        precondition(manager.selectedAppDetails == nil, "Changing configuration must close stale details")
        let invalidDeadline = Date().addingTimeInterval(5)
        while manager.isResolvingInstalledState && Date() < invalidDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!manager.isResolvingInstalledState && settingsAlert.current == nil,
                     "An incomplete brew path must not show a modal receipt failure")
        manager.uninstall(vm)
        precondition(!fm.fileExists(atPath: secondPrefix.appendingPathComponent("uninstall-started").path),
                     "Invalid paths must keep Homebrew writes blocked")
        defaults.setValue(secondBrew.path, for: Preferences.customUserBrewPath)
        manager.selectedHomebrewDidChange(surfacingErrorsIn: manager.alert)
        precondition(!vm.isInstalled && manager.isResolvingInstalledState,
                     "Switching Homebrew must immediately invalidate stale receipt ownership")
        precondition(!manager.updateAll([vm]), "Update All must reject requests while receipts refresh")
        precondition(!manager.updateAll([]), "Update All must reject an empty batch")
        manager.uninstall(vm)
        precondition(!fm.fileExists(atPath: secondPrefix.appendingPathComponent("uninstall-started").path))
        let started = secondPrefix.appendingPathComponent("list-started")
        let deadline = Date().addingTimeInterval(5)
        while !fm.fileExists(atPath: started.path) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fm.fileExists(atPath: started.path))
        try fm.removeItem(at: pause)
        let finish = Date().addingTimeInterval(5)
        while manager.isResolvingInstalledState && Date() < finish {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!manager.isResolvingInstalledState && !vm.isInstalled)
        vm.isInstalled = true
        service.uninstall(vm)
        _ = try await service.runSerialized { true }
        precondition(vm.progressState.isFailed && !fm.fileExists(atPath: secondPrefix.appendingPathComponent("uninstall-started").path),
                     "A stale cached flag must never authorize uninstall when the selected Homebrew has no receipt")
        let fail = secondPrefix.appendingPathComponent("fail-list")
        try Data().write(to: fail)
        manager.selectedHomebrewDidChange(surfacingErrorsIn: manager.alert)
        let failureDeadline = Date().addingTimeInterval(5)
        while manager.isResolvingInstalledState && Date() < failureDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!manager.isResolvingInstalledState)
        vm.isInstalled = true
        vm.progressState = .idle
        manager.uninstall(vm)
        _ = try await service.runSerialized { true }
        precondition(!vm.progressState.isFailed && !fm.fileExists(atPath: secondPrefix.appendingPathComponent("uninstall-started").path),
                     "A failed receipt refresh must keep Homebrew actions blocked")
        try fm.removeItem(at: fail)
        manager.selectedHomebrewDidChange(surfacingErrorsIn: manager.alert)
        let retryDeadline = Date().addingTimeInterval(5)
        while manager.isResolvingInstalledState && Date() < retryDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!manager.isResolvingInstalledState && !vm.isInstalled)
        vm.isInstalled = true
        manager.uninstall(vm)
        _ = try await service.runSerialized { true }
        precondition(vm.progressState.isFailed,
                     "A successful retry must unblock actions, which still verify the selected receipt")
        try fm.removeItem(at: secondPrefix.appendingPathComponent("outdated-started"))
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        let failedInventoryService = BrewService(
            notify: { _, _, _ in },
            intuneInventory: { throw CaskAdoptionError.intuneInventoryUnavailable },
            artCraftInventory: { .empty }
        )
        let scanManager = CaskManager(dataLoader: loader, registry: registry, brewService: failedInventoryService)
        let scanAlert = AlertManager()
        scanManager.selectedHomebrewDidChange(surfacingErrorsIn: scanAlert)
        let scanDeadline = Date().addingTimeInterval(5)
        while scanManager.isResolvingInstalledState && Date() < scanDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!scanManager.isResolvingInstalledState && scanAlert.current != nil
                     && fm.fileExists(atPath: secondPrefix.appendingPathComponent("outdated-started").path)
                     && !scanManager.outdatedRefreshFailed,
                     "Ownership scan failures must be reported without suppressing valid receipt and outdated refreshes")
        vm.isInstalled = true
        vm.progressState = .idle
        scanManager.uninstall(vm)
        _ = try await failedInventoryService.runSerialized { true }
        precondition(vm.progressState.isFailed
                     && !fm.fileExists(atPath: secondPrefix.appendingPathComponent("uninstall-started").path),
                     "Writes must still fail closed when ownership inventory is unavailable")
    }

    @MainActor
    private static func testLiveArtifactOwnershipAndCatalogResult(root: URL) async throws {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let oldBrew = defaults.value(for: Preferences.customUserBrewPath)
        let oldAppdir = defaults.value(for: Preferences.appdirPath)
        defer {
            defaults.setValue(oldBrew, for: Preferences.customUserBrewPath)
            defaults.setValue(oldAppdir, for: Preferences.appdirPath)
            defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
            defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        }
        let prefix = root.appendingPathComponent("Live Artifact Review")
        let brew = prefix.appendingPathComponent("bin/brew")
        let apps = prefix.appendingPathComponent("Apps")
        let oldApp = apps.appendingPathComponent("Old.app")
        let newApp = apps.appendingPathComponent("New.app")
        let receipt = newApp.appendingPathComponent("Contents/_MASReceipt/receipt")
        try fm.createDirectory(at: brew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: oldApp, withIntermediateDirectories: true)
        try fm.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        let metadataURL = prefix.appendingPathComponent("metadata.json")
        let metadata = """
        {"casks":[{"token":"review-live","full_token":"review-live","tap":"homebrew/cask","homepage":"https://example.test/","url":"https://example.test/app.dmg","artifacts":[{"app":["Archive/Source.app",{"target":"New.app"}]}],"deprecated":false,"disabled":false}]}
        """
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
        let fixture = """
        #!/bin/sh
        fixture_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
        case "$1" in
          --version) echo "Homebrew fixture" ;;
          --caskroom) echo "$fixture_dir/Caskroom" ;;
          list) if [ -f "$fixture_dir/receipts" ]; then cat "$fixture_dir/receipts"; fi ;;
          outdated) : ;;
          info) cat "$fixture_dir/metadata.json" ;;
          install|upgrade|reinstall)
            printf '%s\\n' "$@" > "$fixture_dir/arguments"
            echo "review-live was successfully installed!" ;;
          *) exit 2 ;;
        esac
        """
        try fixture.write(to: brew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew.path)
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        for source in ProtectedAppInstallation.Source.allCases {
            defaults.setValue(false, for: source.overridePreference)
        }
        let record = CaskRecord(
            token: "review-live", fullToken: "review-live", tap: "homebrew/cask", name: "Old",
            descriptionText: "", homepageURL: nil, pkgInstaller: false,
            warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
            appBundleNames: ["Old.app"]
        )
        let arguments = prefix.appendingPathComponent("arguments")
        try Data().write(to: receipt)
        for isBatch in [false, true] {
            let vm = CaskViewModel(record: record)
            vm.externalAppURL = oldApp
            let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
            if isBatch {
                service.installAll([vm])
            } else {
                service.install(vm, confirmedConfiguration: .current)
            }
            _ = try await service.runSerialized { true }
            precondition(vm.progressState.isFailed && vm.isAppStoreManaged
                         && vm.protectedAppInstallation?.url.lastPathComponent == "New.app"
                         && !fm.fileExists(atPath: arguments.path),
                         "Final ownership must inspect live renamed targets, not only cached app artifacts")
        }
        try fm.removeItem(at: receipt)
        let recordedLink = prefix.appendingPathComponent("Caskroom/review-live/1.0/Old.app")
        try fm.createDirectory(at: recordedLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: recordedLink, withDestinationURL: oldApp)
        try writeRecordedArtifacts(caskroom: recordedLink.deletingLastPathComponent().deletingLastPathComponent(),
                                   token: "review-live", version: "1.0", source: "Old.app")
        let receiptList = prefix.appendingPathComponent("receipts")
        try record.fullToken.write(to: receiptList, atomically: true, encoding: .utf8)
        for isBatch in [false, true] {
            let vm = CaskViewModel(record: record, isInstalled: true)
            let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
            if isBatch { service.installAll([vm]) } else { service.install(vm) }
            _ = try await service.runSerialized { true }
            precondition(vm.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                         "Owning Old.app must not authorize silently replacing an external live target New.app")
        }
        let unchangedTargetMetadata = metadata.replacingOccurrences(
            of: "\"Archive/Source.app\",{\"target\":\"New.app\"}", with: "\"Old.app\""
        )
        try unchangedTargetMetadata.write(to: metadataURL, atomically: true, encoding: .utf8)
        let existingOwner = CaskViewModel(record: record, isInstalled: true)
        let ownedService = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        await ownedService.install(existingOwner).value
        precondition(!existingOwner.progressState.isFailed && existingOwner.isInstalled && fm.fileExists(atPath: arguments.path),
                     "A selected-Homebrew receipt and recorded unchanged target must retain normal managed install behavior")
        try fm.removeItem(at: arguments)
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
        try fm.removeItem(at: recordedLink)
        try fm.removeItem(at: receiptList)
        for disableDetection in [false, true] {
            let calls = OSAllocatedUnfairLock(initialState: 0)
            let service = BrewService(
                notify: { _, _, _ in },
                intuneInventory: {
                    let count = calls.withLock { value in value += 1; return value }
                    if count >= 3 {
                        if disableDetection {
                            UserDefaults.standard.setValue(false, for: Preferences.detectExternallyInstalledApps)
                        } else {
                            UserDefaults.standard.setValue(false, for: Preferences.offerHomebrewManagement)
                        }
                    }
                    return .empty
                },
                artCraftInventory: { .empty }
            )
            let vm = CaskViewModel(record: record)
            vm.externalAppURL = oldApp
            await service.install(vm, confirmedConfiguration: .current).value
            precondition(calls.withLock { $0 } >= 3 && vm.progressState.isFailed
                         && !fm.fileExists(atPath: arguments.path),
                         "Disabling management during the last ownership await must block the force install")
            defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
            defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        }
        let incomplete = """
        {"casks":[{"token":"review-live","full_token":"review-live","tap":"homebrew/cask","homepage":"https://example.test/","url":"https://example.test/app.dmg","deprecated":false,"disabled":false}]}
        """
        try incomplete.write(to: metadataURL, atomically: true, encoding: .utf8)
        let missingTargets = CaskViewModel(record: record, isInstalled: true)
        let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        await service.update(missingTargets).value
        guard case .failed(let reason) = missingTargets.progressState else {
            preconditionFailure("Incomplete live installation targets must fail closed")
        }
        precondition(reason.contains(CaskAdoptionError.installationTargetsUnavailable.localizedDescription))
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)

        let pool = try DatabasePool(path: prefix.appendingPathComponent("catalog.sqlite").path)
        try AppDatabase.migrator().migrate(pool)
        try await pool.write { db in try record.insert(db) }
        let registry = CaskViewModelRegistry()
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: pool), registry: registry,
            intuneInventory: { .empty }, artCraftInventory: { .empty }
        )
        let failedCatalog = CaskManager(
            dataLoader: loader, registry: registry, brewService: service,
            catalogLoad: { _ in throw NSError(domain: "FixtureCatalog", code: 1) }
        )
        let failedResult = await failedCatalog.loadData(forceSync: true)
        precondition(!failedResult && failedCatalog.alert.current != nil && failedCatalog.successfulCatalogRefreshRevision == 0,
                     "A valid Homebrew must not turn a failed catalog synchronization into success")
        let successfulCatalog = CaskManager(
            dataLoader: loader, registry: registry, brewService: service,
            catalogLoad: { _ in (categories: [], taps: []) }
        )
        let successfulResult = await successfulCatalog.loadData(forceSync: true)
        precondition(successfulResult && successfulCatalog.successfulCatalogRefreshRevision == 1,
                     "A successful explicit catalog sync must invalidate open details")
        _ = await successfulCatalog.loadData(forceSync: false)
        precondition(successfulCatalog.successfulCatalogRefreshRevision == 1,
                     "A non-forced load must not advance the explicit-refresh revision")
    }

    @MainActor
    private static func testUpstreamConsentAndRefresh(root: URL) async throws {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let oldBrew = defaults.value(for: Preferences.customUserBrewPath)
        let oldAppdir = defaults.value(for: Preferences.appdirPath)
        defer {
            defaults.setValue(oldBrew, for: Preferences.customUserBrewPath)
            defaults.setValue(oldAppdir, for: Preferences.appdirPath)
        }
        let prefix = root.appendingPathComponent("Upstream Consent")
        let brew = prefix.appendingPathComponent("bin/brew")
        let apps = prefix.appendingPathComponent("Apps")
        let app = apps.appendingPathComponent("External.app", isDirectory: true)
        try fm.createDirectory(at: brew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let fixture = """
        #!/bin/sh
        fixture_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
        case "$1" in
          --version) echo "Homebrew fixture" ;;
          --caskroom) echo "$fixture_dir/Caskroom" ;;
          list)
            if [ -f "$fixture_dir/fail-list" ]; then echo "fixture list failure" >&2; exit 1; fi
            if [ -f "$fixture_dir/pause-list" ]; then
              touch "$fixture_dir/list-started"
              while [ -f "$fixture_dir/pause-list" ]; do sleep 0.01; done
            fi
            if [ -f "$fixture_dir/receipts" ]; then cat "$fixture_dir/receipts"; fi ;;
          info)
            token="${4##*/}"
            bundle="External.app"
            if [ "$token" = "review-missing" ]; then bundle="Missing.app"; fi
            if [ "$token" = "legacy-safe" ]; then bundle="Safe.app"; fi
            case "$token" in mixed-*) bundle="$token.app" ;; esac
            if [ "$token" = "nested-target" ]; then bundle="Suite/Renamed.app"; fi
            if [ -f "$fixture_dir/missing-artifacts" ]; then
              printf '{"casks":[{"token":"%s","full_token":"%s","tap":"homebrew/cask","homepage":"https://example.test/","url":"https://example.test/app.dmg","deprecated":false,"disabled":false}]}' "$token" "$4"
              exit 0
            fi
            printf '{"casks":[{"token":"%s","full_token":"%s","tap":"homebrew/cask","homepage":"https://example.test/","url":"https://example.test/app.dmg","artifacts":[{"app":["%s"]}],"deprecated":false,"disabled":false}]}' "$token" "$4" "$bundle" ;;
          install)
            printf '%s\\n' "$@" > "$fixture_dir/arguments"
            if [ -f "$fixture_dir/pause-stream" ]; then
              touch "$fixture_dir/stream-started"
              while [ -f "$fixture_dir/pause-stream" ]; do sleep 0.01; done
            fi
            if [ -f "$fixture_dir/track-stream-finish" ]; then
              echo "stream continued"
              sleep 0.2
              touch "$fixture_dir/stream-finished"
            fi
            if [ -f "$fixture_dir/mixed-reconcile" ]; then echo "Starting fixture batch"; fi
            for token in "$@"; do
              case "$token" in install|--cask|--force|--appdir=*) continue ;; esac
              if [ -f "$fixture_dir/mixed-reconcile" ]; then
                case "$token" in
                  mixed-success) echo "$token was successfully installed!" ;;
                  mixed-error) echo "Error: $token: fixture individual failure" ;;
                  mixed-unresolved) echo "fixture unresolved output" ;;
                esac
                continue
              fi
              printf '%s\\n' "$token" >> "$fixture_dir/receipts"
              if [ ! -f "$fixture_dir/no-markers" ]; then echo "$token was successfully installed!"; fi
              if [ "$token" = "review-missing" ]; then mkdir -p "$fixture_dir/Apps/Missing.app"; fi
              mkdir -p "$fixture_dir/Caskroom/$token/1" "$fixture_dir/Caskroom/$token/.metadata/1/1/Casks"
              printf '{"artifacts":[]}' > "$fixture_dir/Caskroom/$token/.metadata/1/1/Casks/$token.json"
            done
            if [ -f "$fixture_dir/mixed-reconcile" ]; then touch "$fixture_dir/fail-list"; fi
            if [ -f "$fixture_dir/pause-reconciliation" ]; then touch "$fixture_dir/pause-list"; fi ;;
          *) exit 2 ;;
        esac
        """
        try fixture.write(to: brew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew.path)
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        defaults.setValue(apps.path, for: Preferences.appdirPath)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        func record(_ token: String, bundle: String) -> CaskRecord {
            CaskRecord(
                token: token, fullToken: token, tap: "homebrew/cask", name: "External Fixture",
                descriptionText: "", homepageURL: nil, pkgInstaller: false,
                warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
                appBundleNames: [bundle]
            )
        }
        let externalRecord = record("review-external", bundle: "External.app")
        let missingRecord = record("review-missing", bundle: "Missing.app")
        let unusedRecord = record("review-unused", bundle: "Unused.app")
        let pool = try DatabasePool(path: prefix.appendingPathComponent("catalog.sqlite").path)
        try AppDatabase.migrator().migrate(pool)
        try await pool.write { db in
            try externalRecord.insert(db)
            try missingRecord.insert(db)
            try unusedRecord.insert(db)
        }
        let registry = CaskViewModelRegistry()
        let vm = registry.viewModel(for: externalRecord)
        let missing = registry.viewModel(for: missingRecord)
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: pool), registry: registry,
            intuneInventory: { .empty }, artCraftInventory: { .empty }
        )
        let service = BrewService(notify: { _, _, _ in }, intuneInventory: { .empty }, artCraftInventory: { .empty })
        let manager = CaskManager(dataLoader: loader, registry: registry, brewService: service)
        let arguments = prefix.appendingPathComponent("arguments")
        let resolved = CaskViewModel(record: record("mixed-success", bundle: "Mixed-success.app"))
        let failed = CaskViewModel(record: record("mixed-error", bundle: "Mixed-error.app"))
        let unresolved = CaskViewModel(record: record("mixed-unresolved", bundle: "Mixed-unresolved.app"))
        try Data().write(to: prefix.appendingPathComponent("mixed-reconcile"))
        service.installAll([resolved, failed, unresolved])
        _ = try await service.runSerialized { true }
        precondition(resolved.isInstalled && !resolved.progressState.isFailed,
                     "A successful marker must survive a failed reconciliation query: \(resolved.progressState)")
        guard case .failed(let failedOutput) = failed.progressState,
              case .failed(let unresolvedOutput) = unresolved.progressState else {
            preconditionFailure("Failed and unresolved batch entries must retain failure output")
        }
        precondition(failedOutput.contains("fixture individual failure")
                     && unresolvedOutput.contains("fixture unresolved output")
                     && unresolvedOutput.contains("fixture list failure"),
                     "Preserve the per-cask error and append the query error to unresolved command output")
        try fm.removeItem(at: prefix.appendingPathComponent("mixed-reconcile"))
        try fm.removeItem(at: prefix.appendingPathComponent("fail-list"))
        try fm.removeItem(at: arguments)
        let nestedTarget = apps.appendingPathComponent("Suite/Renamed.app")
        try fm.createDirectory(at: nestedTarget, withIntermediateDirectories: true)
        let nestedVM = CaskViewModel(record: record("nested-target", bundle: "Suite/Renamed.app"))
        await service.install(nestedVM).value
        precondition(nestedVM.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Unconfirmed installation must not overwrite an existing nested app target")
        let staleRecord = CaskRecord(
            token: externalRecord.token, fullToken: externalRecord.fullToken, tap: externalRecord.tap,
            name: externalRecord.name, descriptionText: "", homepageURL: nil, pkgInstaller: false,
            warningType: .disabled, warningDate: "2020-01-01", warningReason: "Old",
            downloadsIn365days: 0, appBundleNames: ["External.app"]
        )
        _ = registry.viewModel(for: staleRecord)
        precondition(vm.warning?.isDisabled == true)
        try await loader.refreshExternalInstallations { _, _, _ in [:] }
        precondition(vm.warning == nil, "Fresh catalog data must update existing external cards before scanning")
        precondition(registry.count == 2, "Empty scans must not materialize the entire catalog")
        let scanGate = ScanGate()
        let scannedToken = externalRecord.fullToken
        let delayedScan = Task {
            try await loader.refreshExternalInstallations { _, _, _ in
                await scanGate.wait()
                return [scannedToken: app]
            }
        }
        let catalogScanDeadline = Date().addingTimeInterval(5)
        while !(await scanGate.isWaiting) && Date() < catalogScanDeadline { await Task.yield() }
        let scanWaiting = await scanGate.isWaiting
        precondition(scanWaiting)
        let updatedRecord = CaskRecord(
            token: externalRecord.token, fullToken: externalRecord.fullToken, tap: externalRecord.tap,
            name: "Newer Catalog Name", descriptionText: "", homepageURL: nil, pkgInstaller: false,
            warningType: nil, warningDate: nil, warningReason: nil, downloadsIn365days: 0,
            appBundleNames: ["External.app"]
        )
        _ = registry.viewModel(for: updatedRecord)
        await scanGate.release()
        try await delayedScan.value
        precondition(vm.name == "Newer Catalog Name",
                     "A slow external scan must not overwrite newer live catalog data")
        _ = registry.viewModel(for: externalRecord)
        for enabled in [false, true] {
            defaults.setValue(enabled, for: Preferences.offerHomebrewManagement)
            defaults.setValue(enabled, for: Preferences.detectExternallyInstalledApps)
            vm.isInstalled = true
            vm.isOutdated = true
            service.installAll([vm])
            _ = try await service.runSerialized { true }
            precondition(vm.progressState.isFailed && !vm.isInstalled && !vm.isOutdated
                         && !fm.fileExists(atPath: arguments.path),
                         "Bulk import must never adopt an external app without explicit consent")
        }
        service.installAll([vm, missing])
        _ = try await service.runSerialized { true }
        let mixedArguments = try String(contentsOf: arguments, encoding: .utf8)
        precondition(vm.progressState.isFailed && missing.isInstalled
                     && mixedArguments.contains(missing.fullToken) && !mixedArguments.contains(vm.fullToken))
        precondition(!mixedArguments.split(whereSeparator: \.isNewline).contains("--force"),
                     "A batch without per-app adoption consent must not force-replace an unknown artifact")

        try fm.removeItem(at: arguments)
        var legacyRecord = record("legacy-missing-artifacts", bundle: "")
        legacyRecord.appBundleNames = []
        let legacy = CaskViewModel(record: legacyRecord)
        for enabled in [false, true] {
            defaults.setValue(enabled, for: Preferences.detectExternallyInstalledApps)
            defaults.setValue(enabled, for: Preferences.offerHomebrewManagement)
            await service.install(legacy).value
            precondition(legacy.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                         "Live artifacts must block a renamed external bundle even with legacy cached metadata")
            service.installAll([legacy])
            _ = try await service.runSerialized { true }
            precondition(legacy.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                         "Bulk install must also use live artifacts for a legacy catalog")
        }
        try Data().write(to: prefix.appendingPathComponent("missing-artifacts"))
        var safeRecord = record("legacy-safe", bundle: "")
        safeRecord.appBundleNames = []
        let safe = CaskViewModel(record: safeRecord)
        await service.install(safe).value
        precondition(safe.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Missing live artifacts must fail closed")
        service.installAll([safe])
        _ = try await service.runSerialized { true }
        precondition(safe.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Missing live artifacts must fail closed for bulk installs")
        try fm.removeItem(at: prefix.appendingPathComponent("missing-artifacts"))
        await service.install(safe).value
        let normalArguments = try String(contentsOf: arguments, encoding: .utf8)
        precondition(!normalArguments.split(whereSeparator: \.isNewline).contains("--force"),
                     "A verified normal install with an incomplete legacy catalog must not use force")
        try fm.removeItem(at: arguments)
        await service.install(legacy, arguments: ["install", "--cask", legacy.fullToken, "--force"]).value
        precondition(legacy.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Explicit force arguments without adoption confirmation must be rejected")
        try mixedArguments.write(to: arguments, atomically: true, encoding: .utf8)

        registry.markExternalInstallations(appURLs: [vm.fullToken: app])
        manager.confirmAdoption(vm)
        let staleConfirmation = manager.alert.current!
        defaults.setValue(false, for: Preferences.offerHomebrewManagement)
        manager.invalidateAdoptionConsent()
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        manager.invalidateAdoptionConsent()
        let previousTasks = service.activeTasks.map(\.id)
        staleConfirmation.actions.first?.handler?()
        precondition(service.activeTasks.map(\.id) == previousTasks,
                     "Turning management off and back on must not revive an open confirmation")

        let queuedManager = CaskManager(dataLoader: loader, registry: registry, brewService: service)
        var resumeQueue: CheckedContinuation<Void, Never>?
        let blocker = Task {
            try await service.runSerialized {
                await withCheckedContinuation { resumeQueue = $0 }
                return true
            }
        }
        let queueDeadline = Date().addingTimeInterval(5)
        while resumeQueue == nil && Date() < queueDeadline { await Task.yield() }
        precondition(resumeQueue != nil)
        queuedManager.confirmAdoption(vm)
        queuedManager.alert.current!.actions.first?.handler?()
        defaults.setValue(false, for: Preferences.offerHomebrewManagement)
        queuedManager.invalidateAdoptionConsent()
        defaults.setValue(true, for: Preferences.offerHomebrewManagement)
        queuedManager.invalidateAdoptionConsent()
        resumeQueue?.resume()
        _ = try await blocker.value
        _ = try await service.runSerialized { true }
        let afterRevocation = try String(contentsOf: arguments, encoding: .utf8)
        precondition(vm.progressState.isFailed && afterRevocation == mixedArguments,
                     "Queued consent must remain revoked after management is re-enabled")

        let receipts = prefix.appendingPathComponent("receipts")
        try vm.fullToken.write(to: receipts, atomically: true, encoding: .utf8)
        let configuration = BrewOperationConfiguration.current
        let pause = prefix.appendingPathComponent("pause-list")
        let started = prefix.appendingPathComponent("list-started")
        try Data().write(to: pause)
        let refresh = Task { try await loader.refreshInstalled(configuration: configuration) }
        let listDeadline = Date().addingTimeInterval(5)
        while !fm.fileExists(atPath: started.path) && Date() < listDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fm.fileExists(atPath: started.path))
        defaults.setValue(prefix.appendingPathComponent("other-brew").path, for: Preferences.customUserBrewPath)
        try fm.removeItem(at: pause)
        do {
            try await refresh.value
            preconditionFailure("An old Homebrew receipt snapshot must be rejected")
        } catch CaskAdoptionError.configurationChanged { }
        precondition(!vm.isInstalled, "Stale receipts must not commit to the registry after Homebrew changes")
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)

        for mode in ["superseded", "parent", "configuration"] {
            let gate = ScanGate()
            let receiptRefresh = Task {
                try await loader.refreshInstalled(configuration: configuration) { _, _, _ in
                    try await gate.waitForCancellation()
                    return [:]
                }
            }
            let deadline = Date().addingTimeInterval(5)
            while !(await gate.cancellationStarted) && Date() < deadline { await Task.yield() }
            let started = await gate.cancellationStarted
            precondition(started)
            if mode == "parent" { receiptRefresh.cancel() }
            if mode == "configuration" {
                defaults.setValue(prefix.appendingPathComponent("other-brew").path, for: Preferences.customUserBrewPath)
            }
            loader.invalidateExternalInstallations()
            do {
                try await receiptRefresh.value
                precondition(mode == "superseded", "Parent cancellation and configuration changes must propagate")
            } catch is CancellationError {
                precondition(mode == "parent")
            } catch CaskAdoptionError.configurationChanged {
                precondition(mode == "configuration")
            }
            defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        }
        do {
            try await loader.refreshInstalled(configuration: configuration) { _, _, _ in
                throw CancellationError()
            }
            preconditionFailure("An unexpected scan cancellation must not be hidden")
        } catch is CancellationError { }

        for mode in ["stream", "reconciliation"] {
            let missingApp = apps.appendingPathComponent("Missing.app")
            if fm.fileExists(atPath: missingApp.path) { try fm.removeItem(at: missingApp) }
            try? fm.removeItem(at: prefix.appendingPathComponent("receipts"))
            try? fm.removeItem(at: prefix.appendingPathComponent("list-started"))
            registry.markInstalled(tokens: [])
            let flag = prefix.appendingPathComponent(mode == "stream" ? "pause-stream" : "pause-reconciliation")
            try Data().write(to: flag)
            if mode == "stream" { try Data().write(to: prefix.appendingPathComponent("track-stream-finish")) }
            if mode == "reconciliation" { try Data().write(to: prefix.appendingPathComponent("no-markers")) }
            service.installAll([missing])
            let started = prefix.appendingPathComponent(mode == "stream" ? "stream-started" : "list-started")
            let deadline = Date().addingTimeInterval(5)
            while !fm.fileExists(atPath: started.path) && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            precondition(fm.fileExists(atPath: started.path))
            defaults.setValue(prefix.appendingPathComponent("other-brew").path, for: Preferences.customUserBrewPath)
            try fm.removeItem(at: mode == "stream" ? flag : prefix.appendingPathComponent("pause-list"))
            _ = try await service.runSerialized { true }
            precondition(!missing.isInstalled && missing.progressState.isFailed,
                         "Obsolete batch \(mode) results must not update receipt state after a Homebrew switch")
            if mode == "stream", case .failed(let output) = missing.progressState {
                precondition(fm.fileExists(atPath: prefix.appendingPathComponent("stream-finished").path),
                             "Changing configuration must not terminate an in-flight Homebrew process")
                precondition(output.contains("successfully installed"),
                             "Stale streamed results must retain command output")
                try fm.removeItem(at: prefix.appendingPathComponent("track-stream-finish"))
            }
            defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
            if fm.fileExists(atPath: flag.path) { try fm.removeItem(at: flag) }
            if mode == "reconciliation" { try fm.removeItem(at: prefix.appendingPathComponent("no-markers")) }
        }

        try? fm.removeItem(at: prefix.appendingPathComponent("receipts"))
        let missingApp = apps.appendingPathComponent("Missing.app")
        if fm.fileExists(atPath: missingApp.path) { try fm.removeItem(at: missingApp) }
        registry.markInstalled(tokens: [])
        let pauseStream = prefix.appendingPathComponent("pause-stream")
        let streamStarted = prefix.appendingPathComponent("stream-started")
        if fm.fileExists(atPath: streamStarted.path) { try fm.removeItem(at: streamStarted) }
        try Data().write(to: pauseStream)
        let single = service.install(missing)
        let singleDeadline = Date().addingTimeInterval(5)
        while !fm.fileExists(atPath: streamStarted.path) && Date() < singleDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fm.fileExists(atPath: streamStarted.path))
        defaults.setValue(prefix.appendingPathComponent("other-brew").path, for: Preferences.customUserBrewPath)
        try fm.removeItem(at: pauseStream)
        await single.value
        precondition(!missing.isInstalled && missing.progressState.isFailed,
                     "A single install from the previous Homebrew must not publish receipt state")
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)

        var resumeReconciliation: CheckedContinuation<Void, Never>?
        let reconcileTask = service.install(vm, confirmedConfiguration: .current) {
            await withCheckedContinuation { resumeReconciliation = $0 }
            registry.markInstalled(tokens: [vm.fullToken])
        }
        let reconciliationDeadline = Date().addingTimeInterval(5)
        while resumeReconciliation == nil && Date() < reconciliationDeadline { await Task.yield() }
        precondition(resumeReconciliation != nil)
        guard case .busy = vm.progressState else {
            preconditionFailure("A completed command must stay busy during ownership reconciliation")
        }
        let activity = AppStatusSummary(
            isRefreshingCatalog: false, isResolvingInstalledState: false,
            outdatedRefreshFailed: false,
            operations: service.activeTasks.map { ($0.viewModel.name, $0.viewModel.progressState) }
        )
        precondition(activity.activity.isBusy && activity.activeTaskCount > 0,
                     "The footer/quit-facing operation state must remain active during reconciliation")
        resumeReconciliation?.resume()
        await reconcileTask.value

        loader.invalidateInstalledReceipts()
        registry.markInstalled(tokens: [])
        registry.markExternalInstallations(appURLs: [:])
        for _ in 0..<3 {
            manager.applyExternalAppDetectionSetting(debounce: true)
            try await Task.sleep(for: .milliseconds(80))
            precondition(vm.externalAppURL == nil, "Path edits must not immediately launch/apply a scan")
        }
        try await Task.sleep(for: .milliseconds(100))
        precondition(vm.externalAppURL == nil, "Only the last debounced path edit should schedule detection")
        let scanDeadline = Date().addingTimeInterval(5)
        while vm.externalAppURL == nil && Date() < scanDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(vm.externalAppURL == app)
        let probe = ScanGate()
        let scan = Task {
            try await loader.refreshExternalInstallations { _, _, _ in
                try await probe.waitForCancellation()
                return [:]
            }
        }
        let cancellationDeadline = Date().addingTimeInterval(5)
        while !(await probe.cancellationStarted) && Date() < cancellationDeadline { await Task.yield() }
        loader.invalidateExternalInstallations()
        do {
            try await scan.value
            preconditionFailure("Superseded scan work must be canceled, not merely ignored")
        } catch is CancellationError { }
        let canceled = await probe.cancellationObserved
        precondition(canceled)
    }

    private actor ScanGate {
        private var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }
        private(set) var cancellationStarted = false
        private(set) var cancellationObserved = false

        func waitForCancellation() async throws {
            cancellationStarted = true
            do {
                try await Task.sleep(for: .seconds(10))
            } catch is CancellationError {
                cancellationObserved = true
                throw CancellationError()
            }
        }

        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }
}
