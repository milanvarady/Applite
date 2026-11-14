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
                     && confirmation.message.contains("/tmp/Apps with 'quotes'")
                     && confirmation.message.contains("will remain unmanaged"),
                     "Consent must warn when the detected copy is outside the Homebrew app directory")
        precondition(manager.activeTasks.isEmpty)
        precondition(tapVM.installationState == .externalInstalled)
        defaults.setValue(userApps.path, for: Preferences.appdirPath)
        let sameDirectoryManager = CaskManager(registry: registry)
        sameDirectoryManager.confirmAdoption(tapVM)
        precondition(sameDirectoryManager.alert.current?.message.contains("will remain unmanaged") == false,
                     "A copy in the Homebrew app directory must not receive the separate-copy warning")
        let alias = root.appendingPathComponent("Apps Alias", isDirectory: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: userApps)
        defaults.setValue(alias.path, for: Preferences.appdirPath)
        let aliasedDirectoryManager = CaskManager(registry: registry)
        aliasedDirectoryManager.confirmAdoption(tapVM)
        precondition(aliasedDirectoryManager.alert.current?.message.contains("will remain unmanaged") == false,
                     "An app directory symlink must not imply a separate copy")
        defaults.setValue("/tmp/Apps with 'quotes'", for: Preferences.appdirPath)

        let changedCopyManager = CaskManager(registry: registry)
        changedCopyManager.confirmAdoption(tapVM)
        let changedCopyConfirmation = changedCopyManager.alert.current!
        tapVM.externalAppURL = displayGuess
        changedCopyConfirmation.actions.first?.handler?()
        precondition(changedCopyManager.activeTasks.isEmpty,
                     "A changed detected copy must require new consent")
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
        scanRecord.appBundleNames = ["Helper.app"]
        let externalRecord = scanRecord
        try await scanPool.write { db in
            try record.insert(db)
            try externalRecord.insert(db)
        }
        _ = registry.viewModel(for: externalRecord)
        let loader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: scanPool), registry: registry
        )
        let searchRegistry = CaskViewModelRegistry()
        let searchLoader = CaskDataLoader(
            dbService: CaskDatabaseService(databasePool: scanPool), registry: searchRegistry
        )
        let matchingTokens = try await searchLoader.searchExternalTokens(query: "sample")
        precondition(matchingTokens.contains(externalRecord.fullToken) && searchRegistry.count == 0,
                     "External search must not materialize unrelated catalog models")
        _ = searchRegistry.viewModel(for: externalRecord)
        searchRegistry.markExternalInstallations(appURLs: [externalRecord.fullToken: helper])
        precondition(searchRegistry.externalInstalledViewModels.filter { matchingTokens.contains($0.fullToken) }.count == 1,
                     "Search tokens must match models detected after the search")
        defaults.setValue(userApps.path, for: Preferences.appdirPath)
        try await loader.refreshExternalInstallations()
        precondition(tapVM.installationState == .notInstalled)
        precondition(registry.externalInstalledCount == 0)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        try await loader.refreshExternalInstallations { catalog, directories, tokens in
            try await ExternalAppDetector.scan(catalog: catalog, directories: directories, managedTokens: tokens)
        }
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
        try await loader.refreshExternalInstallations { catalog, directories, tokens in
            try await ExternalAppDetector.scan(catalog: catalog, directories: directories, managedTokens: tokens)
        }
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
        try await testAdoptionRaces(
            root: root, loader: loader, registry: registry, vm: tapVM,
            appURL: helper, customApps: customApps, service: service
        )
        try await testUpstreamConsentAndRefresh(root: root)
        try await testManagedSiblingOwnership(root: root)
        print("PASS: detection, migration/FTS, identity/totals, default-enabled setting/disable guards, and adoption success/failure")
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
          list) echo stable ;;
          outdated) echo stable ;;
          install)
            printf '%s\\n' "$@" > "$dir/arguments"
            if [ -f "$dir/pause-install" ]; then
              touch "$dir/install-started"
              while [ -f "$dir/pause-install" ]; do sleep 0.02; done
            fi ;;
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
        let stable = CaskRecord(
            token: "stable", fullToken: "stable", tap: "homebrew/cask", name: "Shared",
            descriptionText: "", homepageURL: nil, pkgInstaller: false, warningType: nil,
            warningDate: nil, warningReason: nil, downloadsIn365days: 0, appBundleNames: ["Shared.app"]
        )
        let beta = CaskRecord(
            token: "beta", fullToken: "beta", tap: "homebrew/cask", name: "Shared",
            descriptionText: "", homepageURL: nil, pkgInstaller: false, warningType: nil,
            warningDate: nil, warningReason: nil, downloadsIn365days: 0, appBundleNames: ["Shared.app"]
        )
        let owned = try ExternalAppDetector.managedBundlePaths(tokens: [stable.fullToken], executable: brew)
        let sharedOnly = try await ExternalAppDetector.scan(
            catalog: [stable, beta], directories: [managedDirectory], managedTokens: [stable.fullToken],
            excluding: owned
        )
        precondition(sharedOnly.isEmpty, "A sibling cask must not claim a Homebrew-owned bundle")
        let alias = prefix.appendingPathComponent("Managed Alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: managedDirectory)
        let separate = try await ExternalAppDetector.scan(
            catalog: [stable, beta], directories: [alias, externalDirectory],
            managedTokens: [stable.fullToken], excluding: owned
        )
        precondition(separate[beta.fullToken]?.standardizedFileURL.path == externalApp.standardizedFileURL.path,
                     "A physically separate copy must remain externally detectable")

        let pool = try DatabasePool(path: prefix.appendingPathComponent("catalog.sqlite").path)
        try AppDatabase.migrator().migrate(pool)
        try await pool.write { db in try beta.insert(db) }
        let registry = CaskViewModelRegistry()
        let loader = CaskDataLoader(dbService: CaskDatabaseService(databasePool: pool), registry: registry)
        _ = registry.viewModel(for: beta)
        try await loader.refreshInstalled()
        precondition(registry.externalInstalledCount == 0,
                     "A managed cask absent from the catalog must still suppress its owned bundle")

        let service = BrewService(notify: { _, _, _ in })
        try await pool.write { db in try stable.insert(db) }
        let managedVM = registry.viewModel(for: stable)
        registry.markInstalled(tokens: [stable.fullToken])
        registry.markOutdated(tokens: [stable.fullToken])
        let manager = CaskManager(dataLoader: loader, registry: registry, brewService: service)
        defaults.setValue(externalDirectory.path, for: Preferences.appdirPath)
        manager.applyExternalAppDetectionSetting(debounce: true)
        precondition(managedVM.isInstalled && managedVM.isOutdated
                     && loader.hasReceiptSnapshot(for: .current),
                     "An app-directory change must not invalidate receipts or updates")
        let secondBrew = prefix.appendingPathComponent("Second/bin/brew")
        try fm.createDirectory(at: secondBrew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: secondBrew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: secondBrew.path)
        let secondRoom = prefix.appendingPathComponent("Second/Caskroom/stable")
        let secondMetadata = secondRoom.appendingPathComponent(".metadata/1/1/Casks")
        try fm.createDirectory(at: secondRoom.appendingPathComponent("1"), withIntermediateDirectories: true)
        try fm.createDirectory(at: secondMetadata, withIntermediateDirectories: true)
        try Data(#"{"artifacts":[]}"#.utf8).write(to: secondMetadata.appendingPathComponent("stable.json"))
        defaults.setValue(secondBrew.path, for: Preferences.customUserBrewPath)
        manager.applyExternalAppDetectionSetting(debounce: true)
        manager.invalidateAdoptionConsent()
        let consentDeadline = Date().addingTimeInterval(5)
        while (!managedVM.isInstalled || manager.outdatedRefreshFailed) && Date() < consentDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(managedVM.isInstalled && managedVM.isOutdated && !manager.outdatedRefreshFailed,
                     "Revoking adoption consent must not abandon receipt reconciliation")
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        manager.applyExternalAppDetectionSetting(debounce: true)
        defaults.setValue(false, for: Preferences.detectExternallyInstalledApps)
        manager.applyExternalAppDetectionSetting()
        let refreshDeadline = Date().addingTimeInterval(5)
        while (!managedVM.isInstalled || manager.outdatedRefreshFailed) && Date() < refreshDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(managedVM.isInstalled && managedVM.isOutdated && !manager.outdatedRefreshFailed,
                     "Receipt reconciliation must survive consent changes and disabled detection")
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        defaults.setValue(managedDirectory.path, for: Preferences.appdirPath)
        defaults.setValue(true, for: Preferences.detectExternallyInstalledApps)
        let sibling = CaskViewModel(record: beta)
        sibling.externalAppURL = externalApp
        await service.install(sibling, confirmedConfiguration: .current).value
        let arguments = prefix.appendingPathComponent("arguments")
        precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "A separate external copy must not authorize overwriting the managed appdir target")
        sibling.externalAppURL = managedApp
        await service.install(sibling, confirmedConfiguration: .current).value
        precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "A stale confirmation for a managed sibling must fail closed")
        service.installAll([sibling])
        _ = try await service.runSerialized { true }
        precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Bulk install must also block a sibling's managed target")
        sibling.externalAppURL = nil
        let safe = CaskViewModel(record: CaskRecord(
            token: "safe", fullToken: "safe", tap: "homebrew/cask", name: "Safe",
            descriptionText: "", homepageURL: nil, pkgInstaller: false, warningType: nil,
            warningDate: nil, warningReason: nil, downloadsIn365days: 0, appBundleNames: ["Safe.app"]
        ))
        let pauseInstall = prefix.appendingPathComponent("pause-install")
        try Data().write(to: pauseInstall)
        service.installAll([sibling, safe])
        let batchDeadline = Date().addingTimeInterval(5)
        while !fm.fileExists(atPath: prefix.appendingPathComponent("install-started").path)
                && Date() < batchDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(fm.fileExists(atPath: prefix.appendingPathComponent("install-started").path)
                     && sibling.progressState.isFailed,
                     "Managed conflicts must fail before eligible batch installs finish")
        try fm.removeItem(at: pauseInstall)
        _ = try await service.runSerialized { true }
        try fm.removeItem(at: arguments)

        defaults.setValue(externalDirectory.path, for: Preferences.appdirPath)
        let selectedCopy = prefix.appendingPathComponent("Previously Selected/Shared.app")
        try fm.createDirectory(at: selectedCopy, withIntermediateDirectories: true)
        sibling.externalAppURL = selectedCopy
        await service.install(sibling, confirmedConfiguration: .current).value
        precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "A different preflight copy must require new consent")
        sibling.externalAppURL = externalApp
        await service.install(sibling, confirmedConfiguration: .current).value
        precondition(fm.fileExists(atPath: arguments.path),
                     "A separately installed target must remain eligible for confirmed adoption")
        try fm.removeItem(at: arguments)
        try fm.removeItem(at: metadata.appendingPathComponent("stable.json"))
        await service.install(sibling, confirmedConfiguration: .current).value
        precondition(sibling.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Unverifiable managed ownership must block adoption rather than imply an unmanaged target")
        let receipt = metadata.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("INSTALL_RECEIPT.json")
        try JSONSerialization.data(withJSONObject: ["uninstall_artifacts": [["app": ["Payload/Source.app"]]]])
            .write(to: receipt)
        try Data("cask fixture".utf8).write(to: metadata.appendingPathComponent("stable.rb"))
        let rubyOwned = try InstalledAppLocator.recordedAppURLs(token: "stable", executable: brew)
        precondition(rubyOwned == [managedApp.resolvingSymlinksInPath().standardizedFileURL],
                     "Ruby-only saved casks must use receipt artifacts without evaluating Ruby")
        try fm.removeItem(at: metadata.appendingPathComponent("stable.rb"))
        let receiptOwned = try InstalledAppLocator.recordedAppURLs(token: "stable", executable: brew)
        precondition(receiptOwned == rubyOwned,
                     "Receipt artifacts must work without saved cask metadata")
        try fm.removeItem(at: source)
        do {
            _ = try InstalledAppLocator.recordedAppURLs(token: "stable", executable: brew)
            preconditionFailure("Receipt-only artifacts still require verified staged links")
        } catch CaskAdoptionError.installationTargetsUnavailable { }
        manager.applyExternalAppDetectionSetting()
        let failedScanDeadline = Date().addingTimeInterval(5)
        while (manager.alert.current == nil || manager.outdatedRefreshFailed) && Date() < failedScanDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(managedVM.isInstalled && managedVM.isOutdated && !manager.outdatedRefreshFailed
                     && manager.alert.current?.title == "Couldn't detect externally installed apps",
                     "A disk-scan failure must be surfaced without skipping the outdated refresh")
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
            if [ -f "$fixture_dir/fail-list" ]; then exit 1; fi
            if [ -f "$fixture_dir/pause-list" ]; then
              touch "$fixture_dir/list-started"
              while [ -f "$fixture_dir/pause-list" ]; do sleep 0.01; done
            fi
            if [ -f "$fixture_dir/receipts" ]; then cat "$fixture_dir/receipts"; fi ;;
          outdated) exit 0 ;;
          info)
            echo info >> "$fixture_dir/info-calls"
            shift 3
            printf '{"casks":['
            separator=""
            for full_token in "$@"; do
              token="${full_token##*/}"
              if [ -f "$fixture_dir/wrong-info-identity" ] && [ "$token" = "legacy-safe-two" ]; then token="wrong"; fi
              bundle="External.app"
              if [ "$token" = "review-missing" ]; then bundle="Missing.app"; fi
              case "$token" in legacy-safe*) bundle="Safe.app" ;; esac
              printf '%s' "$separator"
              if [ -f "$fixture_dir/missing-artifacts" ]; then
                printf '{"token":"%s","full_token":"%s","tap":"homebrew/cask"}' "$token" "$full_token"
              else
                printf '{"token":"%s","full_token":"%s","tap":"homebrew/cask","homepage":"https://example.test/","url":"https://example.test/app.dmg","artifacts":[{"app":["%s"]}],"deprecated":false,"disabled":false}' "$token" "$full_token" "$bundle"
              fi
              separator=","
            done
            printf ']}' ;;
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
            if [ -f "$fixture_dir/fail-list-after-install" ]; then echo "Installing batch"; fi
            for token in "$@"; do
              case "$token" in install|--cask|--force|--appdir=*) continue ;; esac
              mkdir -p "$fixture_dir/Caskroom/$token/1" "$fixture_dir/Caskroom/$token/.metadata/1/1/Casks"
              printf '{"artifacts":[]}' > "$fixture_dir/Caskroom/$token/.metadata/1/1/Casks/$token.json"
              printf '%s\\n' "$token" >> "$fixture_dir/receipts"
              if [ ! -f "$fixture_dir/no-markers" ] && [ "$token" != "partial-unresolved" ]; then echo "$token was successfully installed!"; fi
              if [ "$token" = "review-missing" ]; then mkdir -p "$fixture_dir/Apps/Missing.app"; fi
            done
            if [ -f "$fixture_dir/pause-reconciliation" ]; then touch "$fixture_dir/pause-list"; fi
            if [ -f "$fixture_dir/fail-list-after-install" ]; then touch "$fixture_dir/fail-list"; fi ;;
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
        let loader = CaskDataLoader(dbService: CaskDatabaseService(databasePool: pool), registry: registry)
        let service = BrewService(notify: { _, _, _ in })
        let manager = CaskManager(dataLoader: loader, registry: registry, brewService: service)
        let arguments = prefix.appendingPathComponent("arguments")
        service.recoverBrew = {
            defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
            return true
        }
        let invalidBrew = prefix.appendingPathComponent("missing-brew")
        for batch in [false, true] {
            defaults.setValue(invalidBrew.path, for: Preferences.customUserBrewPath)
            let recovered = CaskViewModel(record: record("recovery-\(batch)", bundle: "Recovery-\(batch).app"))
            if batch {
                service.installAll([recovered])
                _ = try await service.runSerialized { true }
            } else {
                await service.install(recovered).value
            }
            precondition(recovered.isInstalled && !recovered.progressState.isFailed,
                         "An unconfirmed operation must use the recovered Homebrew configuration")
            try fm.removeItem(at: arguments)
        }
        defaults.setValue(invalidBrew.path, for: Preferences.customUserBrewPath)
        let pinned = BrewOperationConfiguration.current
        let confirmed = CaskViewModel(record: externalRecord)
        await service.install(confirmed, confirmedConfiguration: pinned).value
        precondition(confirmed.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Recovery must not change a confirmed adoption's previewed configuration")
        service.recoverBrew = nil
        try fm.removeItem(at: prefix.appendingPathComponent("receipts"))
        let nestedTarget = apps.appendingPathComponent("Suite/Renamed.app")
        try fm.createDirectory(at: nestedTarget, withIntermediateDirectories: true)
        let nestedVM = CaskViewModel(record: record("nested-target", bundle: "Suite/Renamed.app"))
        await service.install(nestedVM).value
        precondition(nestedVM.progressState.isFailed && !fm.fileExists(atPath: arguments.path),
                     "Unconfirmed installation must not overwrite an existing nested app target")
        var notices: [String] = []
        let notificationService = BrewService(notify: { title, _, _ in notices.append(title) })
        let blockedA = CaskViewModel(record: record("blocked-a", bundle: "External.app"))
        let blockedB = CaskViewModel(record: record("blocked-b", bundle: "External.app"))
        notificationService.installAll([blockedA, blockedB])
        _ = try await notificationService.runSerialized { true }
        precondition(notices.count == 1 && blockedA.progressState.isFailed && blockedB.progressState.isFailed,
                     "Blocked external installs must retain per-card errors but produce one notification")
        notices.removeAll()
        var unknownARecord = record("unknown-a", bundle: "")
        unknownARecord.appBundleNames = []
        var unknownBRecord = record("unknown-b", bundle: "")
        unknownBRecord.appBundleNames = []
        let unknownA = CaskViewModel(record: unknownARecord)
        let unknownB = CaskViewModel(record: unknownBRecord)
        try Data().write(to: prefix.appendingPathComponent("missing-artifacts"))
        notificationService.installAll([unknownA, unknownB])
        _ = try await notificationService.runSerialized { true }
        precondition(notices.count == 1 && unknownA.progressState.isFailed && unknownB.progressState.isFailed,
                     "A batch preflight failure must produce one notification and retain each error")
        try fm.removeItem(at: prefix.appendingPathComponent("missing-artifacts"))
        notices.removeAll()
        let changingA = CaskViewModel(record: record("changing-a", bundle: "Changing-a.app"))
        let changingB = CaskViewModel(record: record("changing-b", bundle: "Changing-b.app"))
        let notificationPause = prefix.appendingPathComponent("pause-stream")
        let notificationStarted = prefix.appendingPathComponent("stream-started")
        try Data().write(to: notificationPause)
        notificationService.installAll([changingA, changingB])
        let deadline = Date().addingTimeInterval(5)
        while !fm.fileExists(atPath: notificationStarted.path) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fm.fileExists(atPath: notificationStarted.path))
        defaults.setValue(invalidBrew.path, for: Preferences.customUserBrewPath)
        try fm.removeItem(at: notificationPause)
        _ = try await notificationService.runSerialized { true }
        precondition(notices.count == 1 && changingA.progressState.isFailed && changingB.progressState.isFailed,
                     "A batch configuration change must produce one notification and retain each error")
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        try fm.removeItem(at: notificationStarted)
        try fm.removeItem(at: arguments)
        try fm.removeItem(at: prefix.appendingPathComponent("receipts"))
        let profileReceipts = prefix.appendingPathComponent("receipts")
        let fixtureMetadata = prefix.appendingPathComponent("Caskroom/\(externalRecord.token)/.metadata/1/1/Casks")
        try fm.createDirectory(at: fixtureMetadata, withIntermediateDirectories: true)
        try fm.createDirectory(at: prefix.appendingPathComponent("Caskroom/\(externalRecord.token)/1"),
                               withIntermediateDirectories: true)
        try Data(#"{"artifacts":[]}"#.utf8)
            .write(to: fixtureMetadata.appendingPathComponent("\(externalRecord.token).json"))
        try externalRecord.fullToken.write(to: profileReceipts, atomically: true, encoding: .utf8)
        try await loader.refreshInstalled()
        precondition(vm.isInstalled)
        let alternateBrew = root.appendingPathComponent("Alternate Homebrew/bin/brew")
        try fm.createDirectory(at: alternateBrew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.write(to: alternateBrew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: alternateBrew.path)
        defaults.setValue(alternateBrew.path, for: Preferences.customUserBrewPath)
        manager.applyExternalAppDetectionSetting(debounce: true)
        precondition(!vm.isInstalled, "Changing Homebrew must immediately invalidate old receipt flags")
        let receiptDeadline = Date().addingTimeInterval(5)
        while vm.externalAppURL != app && Date() < receiptDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await service.runSerialized { true }
        precondition(!vm.isInstalled && vm.externalAppURL == app && !manager.outdatedRefreshFailed,
                     "External scans and update state must use receipts from the selected Homebrew")
        defaults.setValue(brew.path, for: Preferences.customUserBrewPath)
        try fm.removeItem(at: profileReceipts)
        try await loader.refreshInstalled()
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
        let oldSnapshots = registry.recordSnapshots()
        _ = registry.viewModel(for: staleRecord)
        registry.updateExistingViewModels(for: [externalRecord], unchangedSince: oldSnapshots)
        precondition(vm.warning?.isDisabled == true,
                     "A record updated during catalog fetch must not be overwritten by its old snapshot")
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
        var secondSafeRecord = record("legacy-safe-two", bundle: "")
        secondSafeRecord.appBundleNames = []
        let secondSafe = CaskViewModel(record: secondSafeRecord)
        let infoCalls = prefix.appendingPathComponent("info-calls")
        let wrongIdentity = prefix.appendingPathComponent("wrong-info-identity")
        try Data().write(to: wrongIdentity)
        service.installAll([safe, secondSafe])
        _ = try await service.runSerialized { true }
        precondition(safe.progressState.isFailed && secondSafe.progressState.isFailed
                     && !fm.fileExists(atPath: arguments.path),
                     "A response with a mismatched cask identity must fail closed")
        try fm.removeItem(at: wrongIdentity)
        try fm.removeItem(at: infoCalls)
        service.installAll([safe, secondSafe])
        _ = try await service.runSerialized { true }
        let calls = try String(contentsOf: infoCalls, encoding: .utf8).split(whereSeparator: \.isNewline)
        precondition(calls.count == 1, "A bulk preflight must use one pinned metadata lookup")
        let bulkArguments = try String(contentsOf: arguments, encoding: .utf8)
        precondition(bulkArguments.contains(safe.fullToken) && bulkArguments.contains(secondSafe.fullToken))
        try fm.removeItem(at: arguments)
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
                try await loader.refreshInstalled(configuration: configuration, scan: { _, _, _ in
                    try await gate.waitForCancellation()
                    return [:]
                })
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
            try await loader.refreshInstalled(configuration: configuration, scan: { _, _, _ in
                throw CancellationError()
            })
            preconditionFailure("An unexpected scan cancellation must not be hidden")
        } catch is CancellationError { }

        try? fm.removeItem(at: prefix.appendingPathComponent("receipts"))
        var fallbackNotices = 0
        let batchService = BrewService(notify: { _, _, _ in fallbackNotices += 1 })
        let batchSuccess = CaskViewModel(record: record("partial-success", bundle: "PartialSuccess.app"))
        let batchUnknown = CaskViewModel(record: record("partial-unresolved", bundle: "PartialUnknown.app"))
        try Data().write(to: prefix.appendingPathComponent("fail-list-after-install"))
        batchService.installAll([batchSuccess, batchUnknown])
        _ = try await batchService.runSerialized { true }
        precondition(batchSuccess.isInstalled && !batchSuccess.progressState.isFailed
                     && batchUnknown.progressState.isFailed && fallbackNotices == 1,
                     "Fallback query: installed=\(batchSuccess.isInstalled), success=\(batchSuccess.progressState), unknown=\(batchUnknown.progressState), notices=\(fallbackNotices)")
        try fm.removeItem(at: prefix.appendingPathComponent("fail-list-after-install"))
        try fm.removeItem(at: prefix.appendingPathComponent("fail-list"))

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

        vm.isInstalled = false
        vm.externalAppURL = app
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
        precondition(service.activeTasks.contains { $0.viewModel === vm },
                     "The operation must remain active during reconciliation")
        resumeReconciliation?.resume()
        await reconcileTask.value

        if fm.fileExists(atPath: profileReceipts.path) { try fm.removeItem(at: profileReceipts) }
        try "review-unused\n".write(to: profileReceipts, atomically: true, encoding: .utf8)
        try await loader.refreshInstalled(scan: { _, _, _ in [:] })
        try fm.removeItem(at: profileReceipts)
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
