import Foundation

enum ExternalAppDetector {
    struct AdditionalInstallation: Sendable {
        let url: URL
        let protection: ProtectedAppInstallation?
    }

    struct ScanResult: Sendable {
        var externalAppURLs: [CaskId: URL] = [:]
        var appStoreAppURLs: [CaskId: URL] = [:]
        var intuneAppURLs: [CaskId: URL] = [:]
        var setappAppURLs: [CaskId: URL] = [:]
        var artCraftAppURLs: [CaskId: URL] = [:]
        var bundleURLs: [CaskId: URL] = [:]
        var selectedCopyProtection: [CaskId: ProtectedAppInstallation] = [:]
        var additionalInstallations: [CaskId: [AdditionalInstallation]] = [:]
        var multipleCopyTokens: Set<CaskId> = []
    }

    nonisolated static func installations(
        catalog: [CaskRecord],
        managedTokens: Set<CaskId>,
        directories: [URL],
        intune: IntuneAppDetector.Snapshot = .empty,
        artCraft: ArtCraftAppDetector.Snapshot = .empty,
        recordedAppURLs: [CaskId: [URL]] = [:]
    ) throws -> ScanResult {
        // A shared bundle cannot establish a release channel. Prefer its managed owner,
        // otherwise a supported official, unversioned cask, with a deterministic tie-break.
        let ordered = catalog.filter { !$0.isApplite }.sorted { lhs, rhs in
            let lhsManaged = managedTokens.contains(lhs.fullToken)
            let rhsManaged = managedTokens.contains(rhs.fullToken)
            if lhsManaged != rhsManaged { return lhsManaged }
            if lhs.isDeprecatedOrDisabled != rhs.isDeprecatedOrDisabled {
                return !lhs.isDeprecatedOrDisabled
            }
            let lhsOfficial = lhs.tap == "homebrew/cask"
            let rhsOfficial = rhs.tap == "homebrew/cask"
            if lhsOfficial != rhsOfficial { return lhsOfficial }
            let lhsVersioned = lhs.token.contains("@")
            let rhsVersioned = rhs.token.contains("@")
            if lhsVersioned != rhsVersioned { return !lhsVersioned }
            return lhs.fullToken < rhs.fullToken
        }

        let managedPaths = Set(recordedAppURLs.filter { managedTokens.contains($0.key) }
            .flatMap { $0.value.map { $0.resolvingSymlinksInPath().standardizedFileURL.path } })
        let knownManaged = Set(catalog.filter { managedTokens.contains($0.fullToken) }.map(\.fullToken))
        var claimed = Set(recordedAppURLs.filter { managedTokens.contains($0.key) && !knownManaged.contains($0.key) }
            .flatMap { $0.value.map { $0.resolvingSymlinksInPath().standardizedFileURL.path } })
        var found = ScanResult()
        var matchesByToken: [(CaskRecord, [URL])] = []
        var renamedCopyTokens: Set<CaskId> = []
        for record in ordered {
            try Task.checkCancellation()
            let recorded = recordedAppURLs[record.fullToken] ?? []
            let discovered = appURLs(
                bundleNames: record.appBundleNames,
                displayName: record.name,
                directories: directories
            ) + artCraft.matchingAppURLs(bundleNames: record.appBundleNames, displayName: record.name)
            guard !recorded.isEmpty || !discovered.isEmpty else { continue }
            let matching = managedTokens.contains(record.fullToken) ? discovered : discovered.filter {
                !managedPaths.contains($0.resolvingSymlinksInPath().standardizedFileURL.path)
            }
            matchesByToken.append((record, matching + recorded))
            if record.appBundleNames.count == 1, let old = recorded.first,
               old.lastPathComponent != (record.appBundleNames[0] as NSString).lastPathComponent,
               matching.contains(where: {
                   $0.resolvingSymlinksInPath().standardizedFileURL != old.resolvingSymlinksInPath().standardizedFileURL
               }) {
                renamedCopyTokens.insert(record.fullToken)
            }
            if renamedCopyTokens.contains(record.fullToken) || hasMultipleCopies(matching + recorded) {
                found.multipleCopyTokens.insert(record.fullToken)
            }
            var selected: URL?
            if let recorded = recorded.first {
                selected = recorded
            } else if let first = matching.first {
                let sameArtifact = matching.filter { $0.lastPathComponent == first.lastPathComponent }
                selected = sameArtifact.first {
                    !claimed.contains($0.resolvingSymlinksInPath().standardizedFileURL.path)
                } ?? first
            }
            let protection = try protectedInstallation(
                bundleNames: record.appBundleNames, displayName: record.name,
                directories: directories, knownURL: selected, intune: intune,
                artCraft: artCraft, additionalURLs: recorded + discovered
            )
            if let protection {
                for (source, url) in protection.appURLs {
                    switch source {
                    case .intune: found.intuneAppURLs[record.fullToken] = url
                    case .appStore: found.appStoreAppURLs[record.fullToken] = url
                    case .setapp: found.setappAppURLs[record.fullToken] = url
                    case .artCraft: found.artCraftAppURLs[record.fullToken] = url
                    }
                }
            }
            guard var selected else { continue }
            if recorded.isEmpty, let preferred = protection?.url,
               preferred.lastPathComponent == selected.lastPathComponent,
               matching.contains(preferred),
               !claimed.contains(preferred.resolvingSymlinksInPath().standardizedFileURL.path) {
                selected = preferred
            }
            let canonicalURL = selected.resolvingSymlinksInPath().standardizedFileURL
            found.bundleURLs[record.fullToken] = canonicalURL
            if found.multipleCopyTokens.contains(record.fullToken) {
                found.selectedCopyProtection[record.fullToken] = try Self.protection(
                    at: selected, intune: intune, artCraft: artCraft
                )
            }
            guard claimed.insert(canonicalURL.path).inserted else { continue }
            if !managedTokens.contains(record.fullToken) {
                found.externalAppURLs[record.fullToken] = selected
            }
        }
        for (record, matching) in matchesByToken {
            guard found.multipleCopyTokens.contains(record.fullToken) else { continue }
            for url in matching {
                let sameArtifact = matching.filter { $0.lastPathComponent == url.lastPathComponent }
                guard renamedCopyTokens.contains(record.fullToken) || hasMultipleCopies(sameArtifact) else {
                    continue
                }
                try Task.checkCancellation()
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                guard claimed.insert(canonical.path).inserted else { continue }
                found.additionalInstallations[record.fullToken, default: []].append(
                    AdditionalInstallation(url: canonical, protection: try protection(
                        at: url, intune: intune, artCraft: artCraft
                    ))
                )
            }
        }
        return found
    }

    nonisolated static func hasMultipleCopies(_ urls: [URL]) -> Bool {
        let groups = Dictionary(grouping: urls, by: \.lastPathComponent)
        return groups.values.contains {
            Set($0.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }).count > 1
        }
    }

    nonisolated static func protection(
        at url: URL, intune: IntuneAppDetector.Snapshot, artCraft: ArtCraftAppDetector.Snapshot
    ) throws -> ProtectedAppInstallation? {
        var sources: [ProtectedAppInstallation.Source: URL] = [:]
        if try intune.isManagedApp(at: url) { sources[.intune] = url }
        if try hasAppStoreReceipt(at: url) { sources[.appStore] = url }
        if try isSetappApp(at: url) { sources[.setapp] = url }
        if artCraft.isManagedApp(at: url) { sources[.artCraft] = url }
        return ProtectedAppInstallation(appURLs: sources)
    }

    nonisolated static func hasAppStoreReceipt(at appURL: URL) throws -> Bool {
        let receipt = appURL.appendingPathComponent("Contents/_MASReceipt/receipt")
        return try isMarkerFile(at: receipt)
    }

    nonisolated static func isSetappApp(at appURL: URL) throws -> Bool {
        if try InstalledAppLocator.bundleIdentifier(at: appURL)?.hasSuffix("-setapp") == true {
            return true
        }
        let key = appURL.appendingPathComponent("Contents/Resources/setappPublicKey.pem")
        return try isMarkerFile(at: key)
    }

    private nonisolated static func isMarkerFile(at url: URL) throws -> Bool {
        do {
            guard let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                throw CocoaError(.fileReadUnknown)
            }
            return !isDirectory
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        }
    }

    nonisolated static func protectedInstallation(
        bundleNames: [String], displayName: String, directories: [URL],
        knownURL: URL? = nil, intune: IntuneAppDetector.Snapshot,
        artCraft: ArtCraftAppDetector.Snapshot = .empty,
        additionalURLs: [URL] = []
    ) throws -> ProtectedAppInstallation? {
        var candidates = knownURL.map { [$0] } ?? []
        candidates.append(contentsOf: additionalURLs.filter { !candidates.contains($0) })
        let names = bundleNames.isEmpty ? ["\(displayName).app"] : bundleNames
        for directory in directories {
            for name in names {
                if let url = appURL(bundleNames: [name], displayName: displayName, directories: [directory]),
                   !candidates.contains(url) {
                    candidates.append(url)
                }
            }
        }
        for url in artCraft.matchingAppURLs(bundleNames: bundleNames, displayName: displayName)
            where !candidates.contains(url) {
            candidates.append(url)
        }
        var appURLs: [ProtectedAppInstallation.Source: URL] = [:]
        for url in candidates {
            try Task.checkCancellation()
            if appURLs[.intune] == nil, try intune.isManagedApp(at: url) { appURLs[.intune] = url }
            if appURLs[.appStore] == nil, try hasAppStoreReceipt(at: url) { appURLs[.appStore] = url }
            if appURLs[.setapp] == nil, try isSetappApp(at: url) { appURLs[.setapp] = url }
            if appURLs[.artCraft] == nil, artCraft.isManagedApp(at: url) { appURLs[.artCraft] = url }
        }
        return ProtectedAppInstallation(appURLs: appURLs)
    }

    nonisolated static func scan(
        catalog: [CaskRecord], directories: [URL], managedTokens: Set<CaskId>
    ) async throws -> [CaskId: URL] {
        let task = Task.detached {
            try installations(catalog: catalog, managedTokens: managedTokens, directories: directories).externalAppURLs
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Unlike launch resolution, detection never looks in the Caskroom or LaunchServices:
    /// stale receipts and registered apps on mounted disk images are not local installations.
    nonisolated static func appURL(
        bundleNames: [String],
        displayName: String,
        directories: [URL]
    ) -> URL? {
        appURLs(bundleNames: bundleNames, displayName: displayName, directories: directories).first
    }

    nonisolated static func appURLs(
        bundleNames: [String], displayName: String, directories: [URL]
    ) -> [URL] {
        let names = bundleNames.isEmpty ? ["\(displayName).app"] : bundleNames
        var matches: [URL] = []
        for directory in directories {
            for name in names {
                guard CaskArtifact.isSafeAppTargetPath(name) else { continue }
                let url = directory.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    if !matches.contains(url) { matches.append(url) }
                }
            }
        }
        return matches
    }
}
