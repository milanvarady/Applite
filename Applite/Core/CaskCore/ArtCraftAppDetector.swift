import Foundation
import OSLog

enum ArtCraftAppDetector {
    typealias Loader = @Sendable () throws -> Snapshot

    struct Snapshot: Sendable {
        let appURLs: Set<URL>
        private let canonicalAppURLs: Set<URL>

        static let empty = Snapshot(appURLs: [])

        init(appURLs: Set<URL>) {
            self.appURLs = appURLs
            self.canonicalAppURLs = Set(appURLs.map { $0.resolvingSymlinksInPath().standardizedFileURL })
        }

        nonisolated func isManagedApp(at appURL: URL) -> Bool {
            canonicalAppURLs.contains(appURL.resolvingSymlinksInPath().standardizedFileURL)
        }

        nonisolated func matchingAppURLs(bundleNames: [String], displayName: String) -> [URL] {
            let names = bundleNames.isEmpty ? ["\(displayName).app"] : bundleNames
            return appURLs.filter { names.contains($0.lastPathComponent) }.sorted { $0.path < $1.path }
        }
    }

    private struct Manifest: Decodable {
        let apps: [String: Installation]
    }

    private struct Installation: Decodable {
        let kind: String
        let path: String
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Applite",
        category: "ArtCraftAppDetector"
    )

    nonisolated static func load(
        manifestURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ArtCraft Launcher/installed.json")
    ) throws -> Snapshot {
        do {
            let data: Data
            do {
                data = try Data(contentsOf: manifestURL)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                return .empty
            }
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            var urls: Set<URL> = []
            for record in manifest.apps.values {
                guard record.kind == "Dmg" else {
                    if (record.path as NSString).pathExtension == "app" {
                        throw CaskAdoptionError.artCraftInventoryUnavailable
                    }
                    continue
                }
                guard (record.path as NSString).isAbsolutePath else {
                    throw CaskAdoptionError.artCraftInventoryUnavailable
                }
                let url = URL(fileURLWithPath: record.path, isDirectory: true)
                guard url.pathExtension == "app" else {
                    throw CaskAdoptionError.artCraftInventoryUnavailable
                }
                do {
                    let metadata = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
                    if metadata.isDirectory == true {
                        urls.insert(url.standardizedFileURL)
                    }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    continue
                }
            }
            return Snapshot(appURLs: urls)
        } catch {
            logger.error("Couldn't read ArtCraft Launcher app ownership: \(error.localizedDescription)")
            throw CaskAdoptionError.artCraftInventoryUnavailable
        }
    }
}
