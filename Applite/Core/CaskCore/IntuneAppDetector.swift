import Foundation
import GRDB
import OSLog

enum IntuneAppDetector {
    typealias Loader = @Sendable () throws -> Snapshot

    struct Snapshot: Sendable {
        let bundleIDs: Set<String>

        static let empty = Snapshot(bundleIDs: [])

        nonisolated func isManagedApp(at appURL: URL) throws -> Bool {
            guard !bundleIDs.isEmpty else { return false }
            guard let identifier = try InstalledAppLocator.bundleIdentifier(at: appURL) else { return false }
            return bundleIDs.contains(identifier)
        }
    }

    private struct AppInfo: Decodable {
        let BundleId: String
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Applite",
        category: "IntuneAppDetector"
    )

    nonisolated static func load(
        agentURL: URL = URL(fileURLWithPath: "/Library/Intune/Microsoft Intune Agent.app"),
        databaseURL: URL = URL(fileURLWithPath: "/Library/Application Support/Microsoft/Intune/SideCar/sidecar.sqlite")
    ) throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: agentURL.path) else { return .empty }
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CaskAdoptionError.intuneInventoryUnavailable
        }
        do {
            return try readInventory(databaseURL: databaseURL)
        } catch {
            logger.error("Couldn't read Intune app ownership: \(error.localizedDescription)")
            throw CaskAdoptionError.intuneInventoryUnavailable
        }
    }

    nonisolated private static func readInventory(databaseURL: URL) throws -> Snapshot {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(1)
        let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        return try queue.read { db in
            // Select only bundle identifiers; policy rows can also contain organization scripts.
            let rows = try Row.fetchAll(db, sql: """
                SELECT json_type(ZPOLICYRESULTJSON, '$.Policy.PrimaryApplicationBundleId') AS primaryType,
                       json_extract(ZPOLICYRESULTJSON, '$.Policy.PrimaryApplicationBundleId') AS primaryID,
                       json_type(ZPOLICYRESULTJSON, '$.Policy.AppInfos') AS infosType,
                       json_extract(ZPOLICYRESULTJSON, '$.Policy.AppInfos') AS infos
                FROM ZAPPSTATECHANGEITEM
                """)
            var identifiers: Set<String> = []
            for row in rows {
                let primaryType: String? = row["primaryType"]
                let infosType: String? = row["infosType"]
                guard (primaryType == nil || primaryType == "null" || primaryType == "text"),
                      infosType == "array" else {
                    throw CaskAdoptionError.intuneInventoryUnavailable
                }
                if let primary: String = row["primaryID"], !primary.isEmpty {
                    identifiers.insert(primary)
                }
                let infos: String = row["infos"]
                let apps = try JSONDecoder().decode([AppInfo].self, from: Data(infos.utf8))
                for app in apps where !app.BundleId.isEmpty {
                    identifiers.insert(app.BundleId)
                }
            }
            return Snapshot(bundleIDs: identifiers)
        }
    }
}
