import Foundation

enum ExternalAppDetector {
    nonisolated static func scan(
        catalog: [CaskRecord], directories: [URL], managedTokens: Set<CaskId>,
        excluding managedPaths: Set<String> = []
    ) async throws -> [CaskId: URL] {
        let task = Task.detached {
            var found: [CaskId: URL] = [:]
            for record in catalog where !record.isApplite && !managedTokens.contains(record.fullToken) {
                try Task.checkCancellation()
                if let url = appURL(
                    bundleNames: record.appBundleNames, displayName: record.name,
                    directories: directories, excluding: managedPaths
                ) {
                    found[record.fullToken] = url
                }
            }
            try Task.checkCancellation()
            return found
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    nonisolated static func managedBundlePaths(
        tokens: Set<CaskId>, executable: URL
    ) throws -> Set<String> {
        var paths: Set<String> = []
        for token in tokens {
            try Task.checkCancellation()
            let bareToken = (token as NSString).lastPathComponent
            let urls = try InstalledAppLocator.recordedAppURLs(token: bareToken, executable: executable)
            paths.formUnion(urls.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        }
        return paths
    }

    /// Unlike launch resolution, detection never looks in the Caskroom or LaunchServices:
    /// stale receipts and registered apps on mounted disk images are not local installations.
    nonisolated static func appURL(
        bundleNames: [String],
        displayName: String,
        directories: [URL],
        excluding managedPaths: Set<String> = []
    ) -> URL? {
        let names = bundleNames.isEmpty ? ["\(displayName).app"] : bundleNames
        for directory in directories {
            for name in names {
                guard CaskArtifact.isSafeAppTargetPath(name) else { continue }
                let url = directory.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue,
                   !managedPaths.contains(url.resolvingSymlinksInPath().standardizedFileURL.path) {
                    return url
                }
            }
        }
        return nil
    }
}
