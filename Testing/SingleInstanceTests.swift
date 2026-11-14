import Foundation
import Darwin

@main
enum SingleInstanceTests {
    @MainActor
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            let lock = try SingleInstanceLock(at: URL(fileURLWithPath: CommandLine.arguments[2]))
            if CommandLine.arguments[1] == "--exit-with-lock" {
                precondition(lock.isPrimary)
                _exit(0)
            }
            FileHandle.standardOutput.write(Data((lock.isPrimary ? "primary\n" : "secondary\n").utf8))
            if lock.isPrimary {
                withExtendedLifetime(lock) {
                    _ = FileHandle.standardInput.readDataToEndOfFile()
                }
            }
            return
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("instance.lock")

        var owner: SingleInstanceLock? = try SingleInstanceLock(at: url)
        precondition(owner!.isPrimary)
        let contender = try SingleInstanceLock(at: url)
        precondition(!contender.isPrimary)
        owner = nil
        let successor = try SingleInstanceLock(at: url)
        precondition(successor.isPrimary, "Closing the owner must release the lock without deleting its file")
        withExtendedLifetime((contender, successor)) {}

        let raceURL = root.appendingPathComponent("race.lock")
        let first = try startChild(mode: "--hold", url: raceURL)
        let second = try startChild(mode: "--hold", url: raceURL)
        let outcomes = [first, second].map {
            String(decoding: $0.output.fileHandleForReading.availableData, as: UTF8.self)
        }
        precondition(outcomes.filter { $0 == "primary\n" }.count == 1)
        precondition(outcomes.filter { $0 == "secondary\n" }.count == 1)
        for child in [first, second] {
            try child.input.fileHandleForWriting.close()
            child.process.waitUntilExit()
            precondition(child.process.terminationStatus == 0)
        }
        let afterRace = try SingleInstanceLock(at: raceURL)
        precondition(afterRace.isPrimary)

        let exitURL = root.appendingPathComponent("exit.lock")
        let exiting = try startChild(mode: "--exit-with-lock", url: exitURL)
        exiting.process.waitUntilExit()
        precondition(exiting.process.terminationStatus == 0)
        let afterExit = try SingleInstanceLock(at: exitURL)
        precondition(afterExit.isPrimary, "The OS must release the lock even without running deinit")

        let staleURL = root.appendingPathComponent("stale.lock")
        try Data("stale process data".utf8).write(to: staleURL)
        let stale = try SingleInstanceLock(at: staleURL)
        precondition(stale.isPrimary, "A leftover file must not block launch")

        do {
            _ = try SingleInstanceLock(at: root.appendingPathComponent("missing/instance.lock"))
            preconditionFailure("An inaccessible lock path must fail closed")
        } catch let error as NSError {
            precondition(error.domain == NSPOSIXErrorDomain)
        }

        let settings = SettingsNavigation()
        settings.selection = .brew
        var focusRequests = 0
        let focusSettings = {
            precondition(settings.selection == .uninstall, "Select Uninstall before opening or focusing Settings")
            focusRequests += 1
        }
        settings.showUninstall(openSettings: focusSettings)
        settings.showUninstall(openSettings: focusSettings)
        precondition(focusRequests == 2, "Repeated Uninstall requests must still focus the existing Settings window")
        settings.selection = .general
        settings.showUninstall(openSettings: focusSettings)
        precondition(focusRequests == 3)

        settings.selection = .general
        var updateEvents: [String] = []
        let showUpdateSettings = {
            precondition(settings.selection == .updates, "Select Updates before opening or focusing Settings")
            updateEvents.append("settings")
        }
        let checkForUpdates = {
            precondition(updateEvents.last == "settings", "Focus Settings before starting the update check")
            updateEvents.append("check")
        }
        settings.showUpdates(openSettings: showUpdateSettings, checkForUpdates: checkForUpdates)
        settings.showUpdates(openSettings: showUpdateSettings, checkForUpdates: checkForUpdates)
        precondition(updateEvents == ["settings", "check", "settings", "check"])

        let operations: [(name: String, progress: CaskProgressState)] = [
            ("Failed app", .failed(output: "fixture error")),
            ("Installing app", .busy(withTask: "Installing")),
            ("Downloading app", .downloading(percent: 0.42)),
            ("Completed app", .success)
        ]
        let running = AppStatusSummary(
            isRefreshingCatalog: false, isResolvingInstalledState: true,
            outdatedRefreshFailed: false, operations: operations
        )
        precondition(running.activity == .working(name: "Installing app", detail: "Installing"))
        precondition(running.activeTaskCount == 2 && running.failedTaskCount == 1 && running.taskCount == 4)
        let refreshing = AppStatusSummary(
            isRefreshingCatalog: true, isResolvingInstalledState: true,
            outdatedRefreshFailed: false, operations: operations
        )
        precondition(refreshing.activity == .refreshingCatalog && refreshing.activeTaskCount == 2)
        let failed = AppStatusSummary(
            isRefreshingCatalog: false, isResolvingInstalledState: false,
            outdatedRefreshFailed: false, operations: [operations[0]]
        )
        precondition(failed.activity == .failedTasks(1) && !failed.activity.isBusy)
        precondition(failed.activeTaskCount == 0)
        let downloading = AppStatusSummary(
            isRefreshingCatalog: false, isResolvingInstalledState: false,
            outdatedRefreshFailed: false, operations: [operations[2]]
        )
        precondition(downloading.activity == .downloading(name: "Downloading app", fraction: 0.42))
        let loading = AppStatusSummary(
            isRefreshingCatalog: false, isResolvingInstalledState: true,
            outdatedRefreshFailed: false, operations: []
        )
        precondition(loading.activity == .checkingApps && loading.activity.isBusy)
        let unavailable = AppStatusSummary(
            isRefreshingCatalog: false, isResolvingInstalledState: false,
            outdatedRefreshFailed: true, operations: []
        )
        precondition(unavailable.activity == .updateCheckFailed && !unavailable.activity.isBusy)
        let retrying = AppStatusSummary(
            isRefreshingCatalog: false, isResolvingInstalledState: false,
            isRefreshingOutdated: true, outdatedRefreshFailed: true, operations: []
        )
        precondition(retrying.activity == .checkingUpdates && retrying.activity.isBusy && retrying.blocksCatalogRefresh,
                     "A standalone retry must replace stale failure/Ready status and block catalog refresh")
        let ready = AppStatusSummary(
            isRefreshingCatalog: false, isResolvingInstalledState: false,
            outdatedRefreshFailed: false, operations: [operations[3]]
        )
        precondition(ready.activity == .ready && ready.activeTaskCount == 0)
        precondition(!ready.blocksCatalogRefresh)

        let infoJSON = Data(#"{"token":"fixture","full_token":"example/tap/fixture","name":["Fixture App"],"desc":"Fixture description","version":"2.0","tap":"example/tap","homepage":"https://example.invalid","url":"https://example.invalid/app.zip","deprecated":false,"disabled":false}"#.utf8)
        let info = try JSONDecoder().decode(CaskAdditionalInfo.self, from: infoJSON)
        precondition(info.displayName == "Fixture App" && info.desc == "Fixture description" && info.version == "2.0")
        guard var legacyJSON = try JSONSerialization.jsonObject(with: infoJSON) as? [String: Any] else {
            preconditionFailure("Expected an app-info JSON object")
        }
        for key in ["name", "desc", "version"] {
            legacyJSON.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(
            CaskAdditionalInfo.self, from: JSONSerialization.data(withJSONObject: legacyJSON)
        )
        precondition(legacy.displayName == "example/tap/fixture" && legacy.desc == nil && legacy.version == nil)
        let appValues: [Any] = ["Nested/Source.app", ["target": "Renamed.app"]]
        legacyJSON["artifacts"] = [["app": appValues]]
        let withArtifacts = try JSONDecoder().decode(
            CaskAdditionalInfo.self, from: JSONSerialization.data(withJSONObject: legacyJSON)
        )
        let roundTrip = try JSONDecoder().decode(CaskAdditionalInfo.self, from: JSONEncoder().encode(withArtifacts))
        precondition(withArtifacts.artifacts?.compactMap(\.bundleName) == ["Renamed.app"]
                     && roundTrip.artifacts == withArtifacts.artifacts,
                     "Live artifact target renames must survive metadata serialization")

        print("PASS: single-instance locking, Settings routing, activity summaries, and app-info metadata compatibility")
    }

    private static func startChild(mode: String, url: URL) throws -> (process: Process, input: Pipe, output: Pipe) {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [mode, url.path]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        return (process, input, output)
    }
}
