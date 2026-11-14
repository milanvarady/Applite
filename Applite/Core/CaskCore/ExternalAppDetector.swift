import Foundation

enum ExternalAppDetector {
    nonisolated static func scan(
        catalog: [CaskRecord], directories: [URL], managedTokens: Set<CaskId>
    ) async throws -> [CaskId: URL] {
        let task = Task.detached {
            var found: [CaskId: URL] = [:]
            for record in catalog where !record.isApplite && !managedTokens.contains(record.fullToken) {
                try Task.checkCancellation()
                if let url = appURL(bundleNames: record.appBundleNames, displayName: record.name, directories: directories) {
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

    /// Unlike launch resolution, detection never looks in the Caskroom or LaunchServices:
    /// stale receipts and registered apps on mounted disk images are not local installations.
    nonisolated static func appURL(
        bundleNames: [String],
        displayName: String,
        directories: [URL]
    ) -> URL? {
        let names = bundleNames.isEmpty ? ["\(displayName).app"] : bundleNames
        for directory in directories {
            for name in names {
                guard CaskArtifact.isSafeAppTargetPath(name) else { continue }
                let url = directory.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return url
                }
            }
        }
        return nil
    }
}
