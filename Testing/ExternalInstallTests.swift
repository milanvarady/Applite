import Foundation
import GRDB
@testable import Applite

@main
enum ExternalInstallTests {
    @MainActor
    static func main() async throws {
        precondition(Bundle.main.bundleIdentifier == "dev.applite.ExternalInstallTests")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try! fm.removeItem(at: root) }

        let systemApps = root.appendingPathComponent("Applications", isDirectory: true)
        let userApps = root.appendingPathComponent("User Applications", isDirectory: true)
        let customApps = root.appendingPathComponent("Custom Applications", isDirectory: true)
        let directories = [systemApps, userApps, customApps]
        for directory in directories {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

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
        precondition(registry.outdatedCount == 0)

        // A successful managed refresh takes priority and only affects the exact full token.
        registry.markInstalled(tokens: [record.fullToken])
        precondition(vm.installationState == .installed)
        precondition(vm.externalAppURL == nil)
        precondition(tapVM.installationState == .externalInstalled)
        precondition(registry.externalInstalledViewModels == [tapVM])
        precondition(registry.externalInstalledCount == 1)
        precondition(registry.installedCount == 1)
        registry.markOutdated(tokens: [record.token])
        precondition(registry.outdatedViewModels == [vm])
        registry.markExternalInstallations(appURLs: [:])
        precondition(vm.externalAppURL == nil)
        precondition(tapVM.installationState == .notInstalled)
        precondition(registry.externalInstalledCount == 0)

        // Confirmation does not run brew. No user's preferences or app database are modified.
        let defaults = UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: "dev.applite.ExternalInstallTests") }
        defaults.removeObject(forKey: Preferences.detectExternallyInstalledApps.name)
        defaults.removeObject(forKey: Preferences.offerHomebrewManagement.name)
        defaults.setValue(true, for: Preferences.appdirOn)
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
        precondition(manager.activeTasks.isEmpty)
        precondition(tapVM.installationState == .externalInstalled)

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
        scanRecord.appBundleNames = ["Helper.app"]
        let externalRecord = scanRecord
        try await scanPool.write { db in
            try record.insert(db)
            try externalRecord.insert(db)
        }
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: scanPool), registry: registry
        )
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
        let brew = root.appendingPathComponent("brew")
        let fixture = """
        #!/bin/sh
        fixture_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        case "$1" in
          --version) echo "Homebrew fixture" ;;
          list)
            if [ -f "$fixture_dir/managed" ]; then echo "example/tap/sample"; fi ;;
          install)
            printf '%s\\n' "$@" > "$fixture_dir/arguments"
            if [ -f "$fixture_dir/fail" ]; then
              echo "Error: adoption fixture stderr" >&2
              exit 1
            fi
            touch "$fixture_dir/managed"
            echo "fixture success stderr" >&2
            echo "sample was successfully installed!" ;;
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

        let service = BrewService(notify: { _, _, _ in })
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
        precondition(output.contains("Error: adoption fixture stderr"))
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
        try await testAdoptionRaces(
            root: root, loader: loader, registry: registry, vm: tapVM,
            appURL: helper, customApps: customApps, service: service
        )
        try await testUpstreamConsentAndRefresh(root: root)
        print("PASS: detection, migration/FTS, identity/totals, default-enabled setting/disable guards, and adoption success/failure")
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
        precondition(vm.externalAppURL == appURL && vm.progressState.isFailed)
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
        defaults.setValue(root.appendingPathComponent("brew").path, for: Preferences.customUserBrewPath)

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
        let newerApp = customApps.appendingPathComponent("Helper.app")
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
          list)
            if [ -f "$fixture_dir/pause-list" ]; then
              touch "$fixture_dir/list-started"
              while [ -f "$fixture_dir/pause-list" ]; do sleep 0.01; done
            fi
            if [ -f "$fixture_dir/receipts" ]; then cat "$fixture_dir/receipts"; fi ;;
          info)
            token="${4##*/}"
            bundle="External.app"
            if [ "$token" = "review-missing" ]; then bundle="Missing.app"; fi
            printf '{"casks":[{"token":"%s","full_token":"%s","tap":"homebrew/cask","homepage":"https://example.test/","url":"https://example.test/app.dmg","artifacts":[{"app":["%s"]}],"deprecated":false,"disabled":false}]}' "$token" "$4" "$bundle" ;;
          install)
            printf '%s\\n' "$@" > "$fixture_dir/arguments"
            for token in "$@"; do
              case "$token" in install|--cask|--force|--appdir=*) continue ;; esac
              printf '%s\\n' "$token" >> "$fixture_dir/receipts"
              echo "$token was successfully installed!"
              if [ "$token" = "review-missing" ]; then mkdir -p "$fixture_dir/Apps/Missing.app"; fi
            done ;;
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
        let pool = try DatabasePool(path: prefix.appendingPathComponent("catalog.sqlite").path)
        try AppDatabase.migrator().migrate(pool)
        try await pool.write { db in
            try externalRecord.insert(db)
            try missingRecord.insert(db)
        }
        let registry = CaskViewModelRegistry()
        let vm = registry.viewModel(for: externalRecord)
        let missing = registry.viewModel(for: missingRecord)
        let loader = CaskDataLoader(dbService: CaskDatabaseService(databasePool: pool), registry: registry)
        let service = BrewService(notify: { _, _, _ in })
        let manager = CaskManager(dataLoader: loader, registry: registry, brewService: service)
        let arguments = prefix.appendingPathComponent("arguments")
        for enabled in [false, true] {
            defaults.setValue(enabled, for: Preferences.offerHomebrewManagement)
            service.installAll([vm])
            _ = try await service.runSerialized { true }
            precondition(vm.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                         "Bulk import must never adopt an external app without explicit consent")
        }
        service.installAll([vm, missing])
        _ = try await service.runSerialized { true }
        let mixedArguments = try String(contentsOf: arguments, encoding: .utf8)
        precondition(vm.progressState.isFailed && missing.isInstalled
                     && mixedArguments.contains(missing.fullToken) && !mixedArguments.contains(vm.fullToken))

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
        resumeReconciliation?.resume()
        await reconcileTask.value

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
