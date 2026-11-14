//
//  BrewService.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 11..
//

import Foundation
import SwiftUI
import OSLog

struct ActiveBrewTask: Identifiable {
    let id = UUID()
    /// Groups the rows belonging to the same brew operation (a batch shares one across its casks).
    /// Eviction is scoped to this, so a finishing op only removes its *own* rows — never a
    /// different, still-queued op's row for the same cask (which would make that card vanish and
    /// its cancel silently no-op while brew still ran).
    let operationID: UUID
    let viewModel: CaskViewModel
    let task: Task<Void, Never>
}

/// Progress of an in-flight bulk operation (install-all / update-all).
struct BatchProgress: Equatable {
    var completed: Int
    var total: Int
    /// True for update-all, false for install-all — drives the header wording and lets the
    /// Update-All button ignore a *different* (install-all) batch ending.
    var isUpdate: Bool
}

/// Wraps a streaming brew failure together with the output captured so far,
/// so callers can build tailored error messages from the partial output.
struct BrewStreamError: Error {
    let underlying: Error
    let output: String
}

/// Handles all brew CLI operations (install, uninstall, update, reinstall) on CaskViewModels.
@Observable
@MainActor
final class BrewService {
    private(set) var activeTasks: [ActiveBrewTask] = []

    private let notify: @MainActor (String, String, NotificationReason) async -> Void
    private let loadIntuneInventory: IntuneAppDetector.Loader
    private let loadArtCraftInventory: ArtCraftAppDetector.Loader

    init(
        notify: @escaping @MainActor (String, String, NotificationReason) async -> Void = { title, body, reason in
            await sendNotification(title: title, body: body, reason: reason)
        },
        intuneInventory: @escaping IntuneAppDetector.Loader = { try IntuneAppDetector.load() },
        artCraftInventory: @escaping ArtCraftAppDetector.Loader = { try ArtCraftAppDetector.load() }
    ) {
        self.notify = notify
        self.loadIntuneInventory = intuneInventory
        self.loadArtCraftInventory = artCraftInventory
    }

    /// Asks the owner (`CaskManager`) to re-resolve brew when an operation finds the selected path
    /// invalid, returning whether brew ended up usable. Wired to `HomebrewBootstrap.run()` so this
    /// service reports the fault into the one owned brew state instead of deciding on its own how a
    /// broken brew should look (E1/F1). `run()` is single-flight, so a queue of ops collapses into
    /// a single recovery pass.
    var recoverBrew: (@MainActor () async -> Bool)?

    /// Progress of an in-flight bulk operation, or `nil` when none. Drives an aggregate
    /// "Installing X of N…" header (see `ActiveTasksView`).
    private(set) var batchProgress: BatchProgress?

    /// Tail of the serial operation queue. Every brew op chains after this so only ONE brew
    /// process runs at a time — Homebrew doesn't support concurrent `brew` invocations, and
    /// concurrent ones collide on its lock (silently dropping casks). A queued op shows "Waiting…".
    private var queueTail: Task<Void, Never>?

    /// Reference holder so a batch's `Task` can be published (after it's created) for cancellation.
    private final class BatchHandle { var task: Task<Void, Never>? }
    /// The currently-executing bulk op, or nil. Set when a batch actually starts running (not while
    /// queued) so `cancelBatch()` cancels only the running batch, never queued single ops.
    private var runningBatch: BatchHandle?

    /// Label shown on a cask's card while its operation is queued behind a running one.
    private var waitingLabel: String {
        String(localized: "Waiting…", comment: "Queued brew operation label")
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: BrewService.self)
    )

    // MARK: - Public Operations

    /// Installs the cask. Returns the tracking task so callers (e.g. `installAll`) can
    /// await completion and serialize; discardable for the common fire-and-forget case.
    @discardableResult
    func install(
        _ vm: CaskViewModel,
        arguments: [String]? = nil,
        confirmedConfiguration: BrewOperationConfiguration? = nil,
        adoptionConsent: BrewAdoptionConsent? = nil,
        reconcile: (@MainActor () async throws -> Void)? = nil
    ) -> Task<Void, Never> {
        let configuration = confirmedConfiguration ?? .current
        return runTask(for: vm, configuration: configuration) { configuration, appBundleNames in
            Self.logger.info("Cask \"\(vm.token)\" installation started")

            do {
                try self.validateAdoption(
                    configuration: configuration, confirmedConfiguration: confirmedConfiguration,
                    consent: adoptionConsent
                )
                let external = try await self.externalInstallations(
                    in: [vm], configuration: configuration, bundleNames: [vm.fullToken: appBundleNames]
                )
                try Task.checkCancellation()
                if let appURL = external[vm.fullToken] {
                    guard confirmedConfiguration != nil else {
                        vm.isInstalled = false
                        if UserDefaults.standard.value(for: Preferences.detectExternallyInstalledApps) {
                            vm.externalAppURL = appURL
                        }
                        throw CaskAdoptionError.confirmationRequired
                    }
                }
            } catch is CancellationError {
                vm.progressState = .idle
                return
            } catch {
                await self.showFailure(
                    for: vm, error: error, output: error.localizedDescription,
                    failureTitle: String(localized: "Couldn't start app installation"),
                    failureMessage: error.localizedDescription
                )
                return
            }
            guard !(await self.blockProtectedManagement(
                of: vm, configuration: configuration, appBundleNames: appBundleNames
            )) else { return }
            let arguments = arguments ?? Self.installArguments(
                fullToken: vm.fullToken, configuration: configuration
            ).filter { confirmedConfiguration != nil || $0 != "--force" }
            if arguments.contains("--force") && confirmedConfiguration == nil {
                let error = CaskAdoptionError.confirmationRequired
                await self.showFailure(
                    for: vm, error: error, output: error.localizedDescription,
                    failureTitle: String(localized: "Couldn't start app installation"),
                    failureMessage: error.localizedDescription
                )
                return
            }

            // Setup progress
            vm.progressState = .busy(withTask: "")

            do {
                try self.validateAdoption(
                    configuration: configuration, confirmedConfiguration: confirmedConfiguration,
                    consent: adoptionConsent
                )
            } catch {
                await self.showFailure(
                    for: vm, error: error, output: error.localizedDescription,
                    failureTitle: String(localized: "Couldn't start app installation"),
                    failureMessage: error.localizedDescription
                )
                return
            }

            // Run install command and stream output
            let result = await self.streamBrewCommand(
                arguments,
                vm: vm,
                busyLabel: String(localized: "Installing", comment: "Install progress text"),
                executable: configuration.executable
            )

            // Stopped by the user — no success/failure surface.
            if Task.isCancelled {
                vm.progressState = .idle
                return
            }

            let commandOutput: String
            switch result {
            case .success(let output):
                commandOutput = output
            case .failure(let error):
                let completeOutput = error.output
                var failureMessage = error.underlying.localizedDescription

                // Show a more helpful message in specific cases
                switch completeOutput {
                    // Network error
                case _ where completeOutput.contains("Could not resolve host"):
                    failureMessage = String(localized: "Couldn't download app. No internet connection, or host is unreachable.", comment: "No internet failure message")
                default:
                    // Homebrew error
                    if let result = completeOutput.firstMatch(of: /Error:(.+)/) {
                        failureMessage = String(result.1)
                    }
                }

                await self.showFailure(
                    for: vm,
                    error: error.underlying,
                    output: completeOutput,
                    failureTitle: String(localized: "Failed to install \(vm.name)", comment: "Install failure notification title"),
                    failureMessage: failureMessage
                )

                return
            }

            vm.progressState = .busy(withTask: String(localized: "Refreshing installed apps..."))
            do {
                try configuration.validateCurrent()
                if let reconcile {
                    try await reconcile()
                    try configuration.validateCurrent()
                } else {
                    vm.isInstalled = true
                }
                try await self.refreshOwnership(
                    for: [vm], configuration: configuration, bundleNames: [vm.fullToken: appBundleNames]
                )
            } catch {
                await self.showFailure(
                    for: vm,
                    error: error,
                    output: commandOutput + "\n" + error.localizedDescription,
                    failureTitle: String(localized: "Couldn't refresh installed apps"),
                    failureMessage: error.localizedDescription
                )
                return
            }

            await self.showSuccess(
                for: vm,
                logMessage: "Successfully installed cask \(vm.token)",
                notificationTitle: String(localized: "\(vm.name) successfully installed!", comment: "Successful app install notification")
            )

        }
    }

    static func installArguments(
        fullToken: String, configuration: BrewOperationConfiguration = .current
    ) -> [String] {
        ["install", "--cask", fullToken, "--force"] + configuration.appdirArguments
    }

    /// Uninstalls the cask
    func uninstall(_ vm: CaskViewModel, zap: Bool = false) {
        runTask(for: vm, requiresSupportedCask: false) { configuration, _ in
            vm.progressState = .busy(withTask: String(localized: "Uninstalling", comment: "Uninstall progress text"))
            do {
                let receipts = try await InstalledCaskService().getInstalledCasks(configuration: configuration)
                try Task.checkCancellation()
                try configuration.validateCurrent()
                guard vm.matchesFullName(in: receipts) else { throw CaskAdoptionError.notHomebrewManaged }
            } catch {
                if Task.isCancelled {
                    vm.progressState = .idle
                } else {
                    await self.reportManagementBlock(for: vm, error: error)
                }
                return
            }

            // Always --force: a cask whose files are partly
            // gone — app manually trashed, an orphaned font, a half-finished install — otherwise
            // fails a plain uninstall and strands the entry. Force makes uninstall resilient.
            var arguments: [String] = ["uninstall", "--cask", vm.fullToken, "--force"]

            // --zap additionally removes the cask's app data (prefs/caches/launch agents).
            if zap {
                arguments.append("--zap")
            }

            var output: String = ""

            do {
                output = try await Shell.run(configuration.executable, arguments)
                try configuration.validateCurrent()
            } catch {
                await self.showFailure(
                    for: vm,
                    error: error,
                    output: output,
                    failureTitle: String(localized: "Failed to uninstall \(vm.name)", comment: "Failed app install notification title"),
                    failureMessage: error.localizedDescription
                )
                return
            }

            vm.isInstalled = false
            vm.installedBundleURL = nil
            await self.showSuccess(
                for: vm,
                logMessage: "Successfully uninstalled \(vm.fullToken)",
                notificationTitle: String(localized: "\(vm.name) successfully uninstalled", comment: "Successful app uninstall notification")
            )

        }
    }

    /// Updates the cask. Returns the tracking task so `updateAll` can serialize.
    @discardableResult
    func update(_ vm: CaskViewModel) -> Task<Void, Never> {
        return runTask(for: vm) { configuration, _ in
            let updateLabel = String(localized: "Updating", comment: "Update progress text")
            vm.progressState = .busy(withTask: updateLabel)

            let result = await self.streamBrewCommand(
                ["upgrade", "--cask", vm.fullToken], vm: vm, busyLabel: updateLabel, executable: configuration.executable
            )

            // Stopped by the user — no success/failure surface.
            if Task.isCancelled {
                vm.progressState = .idle
                return
            }

            if case .failure(let error) = result {
                await self.showFailure(
                    for: vm,
                    error: error.underlying,
                    output: error.output,
                    failureTitle: String(localized: "Failed to update \(vm.name)", comment: "Failed app update notification title"),
                    failureMessage: error.underlying.localizedDescription
                )
                return
            }

            guard configuration == .current else {
                await self.reportManagementBlock(for: vm, error: CaskAdoptionError.configurationChanged)
                return
            }
            vm.isOutdated = false
            await self.showSuccess(
                for: vm,
                logMessage: "Successfully updated \(vm.token)",
                notificationTitle: String(localized: "\(vm.name) successfully updated", comment: "Successful app update notification")
            )

        }
    }

    /// Reinstalls the cask
    func reinstall(_ vm: CaskViewModel) {
        runTask(for: vm) { configuration, _ in
            let reinstallLabel = String(localized: "Reinstalling", comment: "Reinstall progress text")
            vm.progressState = .busy(withTask: reinstallLabel)

            let result = await self.streamBrewCommand(
                ["reinstall", "--cask", vm.fullToken], vm: vm, busyLabel: reinstallLabel, executable: configuration.executable
            )

            // Stopped by the user — no success/failure surface.
            if Task.isCancelled {
                vm.progressState = .idle
                return
            }

            if case .failure(let error) = result {
                await self.showFailure(
                    for: vm,
                    error: error.underlying,
                    output: error.output,
                    failureTitle: String(localized: "Failed to reinstall \(vm.name)", comment: "Failed reinstall notification title"),
                    failureMessage: error.underlying.localizedDescription
                )
                return
            }

            guard configuration == .current else {
                await self.reportManagementBlock(for: vm, error: CaskAdoptionError.configurationChanged)
                return
            }
            await self.showSuccess(
                for: vm,
                logMessage: "Successfully reinstalled \(vm.fullToken)",
                notificationTitle: String(localized: "\(vm.name) successfully reinstalled", comment: "Successful reinstall notification")
            )
        }
    }

    /// Installs many casks as ONE `brew install --cask <all>` process (queued behind any
    /// running op). One process avoids the lock collisions that dropped casks with the old
    /// per-cask concurrent approach; brew downloads them concurrently, so it stays fast, and
    /// its per-cask output drives each card's progress (see `runBatchOperation`).
    func installAll(_ vms: [CaskViewModel]) {
        runBatch(vms, kind: .install)
    }

    /// Updates many casks as ONE `brew upgrade --cask <all>` process (see `installAll`).
    func updateAll(_ vms: [CaskViewModel]) {
        runBatch(vms, kind: .update)
    }

    /// Stops the cask's in-progress streaming operation (install, update, reinstall).
    ///
    /// Cancelling the task finishes the output stream, which terminates the
    /// underlying brew process (see `Shell.stream`). The operation then sees
    /// `Task.isCancelled` and resets the cask back to idle.
    func cancel(_ vm: CaskViewModel) {
        activeTasks.first { $0.viewModel == vm }?.task.cancel()
    }

    /// Dismisses a failed cask: clears its error state and drops it from the task list. (Failed
    /// casks are kept in `activeTasks` after an op ends so the error stays reachable in
    /// `ActiveTasksView` until the user clears it.)
    func dismissFailure(_ vm: CaskViewModel) {
        vm.progressState = .idle
        activeTasks.removeAll { $0.viewModel == vm }
    }

    /// Cancels every active task and waits for them to unwind (terminating their brew processes via
    /// `Shell.stream`'s onTermination), bounded by a timeout so quitting can never block
    /// indefinitely. Used by the quit path.
    ///
    /// The timeout is derived from `Shell.terminationGrace` rather than being its own magic number,
    /// and must stay **longer** than it: SIGTERM goes out immediately but the SIGKILL that catches a
    /// process ignoring it only lands one grace period later. A wait shorter than the grace would
    /// return first, the app would exit, and the very process we escalated for would be reparented
    /// to launchd still running — the P3-10 leak, just with extra steps.
    func cancelAllAndWait() async {
        let tasks = activeTasks.map(\.task)
        for task in tasks { task.cancel() }

        let deadline = Shell.terminationGrace + .seconds(1)
        let unwoundCleanly = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for task in tasks { await task.value }
                return true
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return false
            }
            // Return as soon as either all tasks finished unwinding or the timeout fired.
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if !unwoundCleanly {
            Self.logger.error("Quit: \(tasks.count) brew task(s) did not unwind within \(deadline); processes were SIGKILLed")
        }
    }

    /// Gets additional info for a cask from brew CLI
    func getAdditionalInfoForCask(
        _ vm: CaskViewModel, configuration: BrewOperationConfiguration = .current
    ) async throws -> CaskAdditionalInfo {
        let json = try await Shell.run(
            configuration.executable, ["info", "--json=v2", "--cask", vm.fullToken], timeout: .seconds(30)
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try configuration.validateCurrent()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let responseObject = try decoder.decode(CaskAdditionalInfoResponse.self, from: json.data(using: .utf8)!)

        guard responseObject.casks.count == 1, let additionalInfo = responseObject.casks.first,
              additionalInfo.token == vm.token, additionalInfo.full_token == vm.fullToken,
              additionalInfo.tap == vm.tap else {
            Self.logger.error("Couldn't find cask \(vm.fullToken)")
            throw CaskAdoptionError.homebrewUnavailable
        }

        return additionalInfo
    }

    // MARK: - Helper Functions

    private func validateAdoption(
        configuration: BrewOperationConfiguration, confirmedConfiguration: BrewOperationConfiguration?,
        consent: BrewAdoptionConsent?
    ) throws {
        try configuration.validateCurrent()
        if confirmedConfiguration != nil {
            guard UserDefaults.standard.value(for: Preferences.detectExternallyInstalledApps),
                  UserDefaults.standard.value(for: Preferences.offerHomebrewManagement) else {
                throw CaskAdoptionError.confirmationExpired
            }
            try consent?.validate()
        }
    }

    private func externalInstallations(
        in vms: [CaskViewModel], configuration: BrewOperationConfiguration,
        bundleNames: [CaskId: [String]] = [:]
    ) async throws -> [CaskId: URL] {
        let managed = try await InstalledCaskService().getInstalledCasks(configuration: configuration)
        let candidates = vms.map {
            (token: $0.fullToken, bareToken: $0.token, name: $0.name, bundles: bundleNames[$0.fullToken] ?? $0.appBundleNames,
             knownURL: $0.externalAppURL ?? $0.installedBundleURL)
        }
        let task = Task.detached {
            var found: [CaskId: URL] = [:]
            for candidate in candidates {
                try Task.checkCancellation()
                if managed.contains(candidate.token) {
                    let recorded = try InstalledAppLocator.recordedAppURLs(
                        token: candidate.bareToken, executable: configuration.executable
                    )
                    guard !recorded.isEmpty else { continue }
                    let owned = Set(recorded.map(\.path))
                    let targets = ExternalAppDetector.appURLs(
                        bundleNames: candidate.bundles, displayName: candidate.name,
                        directories: Array(configuration.applicationDirectories.prefix(1))
                    )
                    if let external = targets.first(where: {
                        !owned.contains($0.resolvingSymlinksInPath().standardizedFileURL.path)
                    }) {
                        found[candidate.token] = external
                    }
                    continue
                }
                let detected = ExternalAppDetector.appURL(
                    bundleNames: candidate.bundles, displayName: candidate.name,
                    directories: configuration.applicationDirectories
                )
                if let detected {
                    found[candidate.token] = detected
                } else if let known = candidate.knownURL {
                    do {
                        if try known.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                            found[candidate.token] = known
                        }
                    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                        continue
                    }
                }
            }
            return found
        }
        let found = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        try configuration.validateCurrent()
        return found
    }

    /// Enqueues a single-cask brew operation on the serial queue and tracks it. Returns the
    /// task. The op waits for any earlier queued op to finish (only one brew process at a time);
    /// until then the card shows "Waiting…".
    @discardableResult
    private func runTask(
        for vm: CaskViewModel, configuration: BrewOperationConfiguration = .current,
        requiresSupportedCask: Bool = true,
        _ operation: @escaping @MainActor (BrewOperationConfiguration, [String]) async -> Void
    ) -> Task<Void, Never> {
        // Drop any lingering (dismissed-or-not) entry for this cask before re-queuing it, so a
        // retry of a failed op doesn't leave two cards for the same cask.
        activeTasks.removeAll { $0.viewModel == vm }
        vm.progressState = .busy(withTask: waitingLabel)

        let previous = queueTail
        let operationID = UUID()
        let task = Task {
            await previous?.value

            defer {
                // Keep a failed cask in the task list (so its error stays reachable) until the user
                // dismisses it; remove it once it succeeds or is otherwise done. Scope to THIS
                // operation's row so a separate queued op for the same cask isn't evicted (P2-10).
                self.activeTasks.removeAll {
                    $0.operationID == operationID && !$0.viewModel.progressState.isFailed
                }
            }

            // Cancelled while still queued — reset and skip cleanly.
            if Task.isCancelled {
                vm.progressState = .idle
                return
            }

            guard !(await self.blockProtectedManagement(of: vm, configuration: configuration)) else { return }

            // Make sure brew path is valid
            guard await self.brewPathIsValid(configuration: configuration) else {
                vm.progressState = .idle
                return
            }

            var appBundleNames = vm.appBundleNames
            if requiresSupportedCask {
                guard let verified = await self.verifiedInstallationTargets(of: vm, configuration: configuration) else { return }
                appBundleNames = verified
            } else if !vm.isInstalled {
                await self.reportManagementBlock(for: vm, error: CaskAdoptionError.notHomebrewManaged)
                return
            }
            guard !(await self.blockProtectedManagement(
                of: vm, configuration: configuration, appBundleNames: appBundleNames
            )) else { return }
            await operation(configuration, appBundleNames)
        }

        queueTail = task
        self.activeTasks.append(ActiveBrewTask(operationID: operationID, viewModel: vm, task: task))
        return task
    }

    private func refreshOwnership(
        for vms: [CaskViewModel], configuration: BrewOperationConfiguration,
        intuneInventory: IntuneAppDetector.Snapshot? = nil,
        artCraftInventory: ArtCraftAppDetector.Snapshot? = nil,
        bundleNames: [CaskId: [String]] = [:]
    ) async throws {
        let candidates = vms.map {
            (token: $0.token, name: $0.name, bundles: bundleNames[$0.fullToken] ?? $0.appBundleNames,
             knownURL: $0.installedBundleURL ?? $0.externalAppURL ?? $0.protectedAppInstallation?.url)
        }
        let loadIntuneInventory = self.loadIntuneInventory
        let loadArtCraftInventory = self.loadArtCraftInventory
        let evidence = try await Task.detached {
            let inventory = try intuneInventory ?? loadIntuneInventory()
            let artCraft = try artCraftInventory ?? loadArtCraftInventory()
            return try candidates.map { candidate in
                let recorded = try InstalledAppLocator.recordedAppURLs(
                    token: candidate.token, executable: configuration.executable
                )
                let protection = try ExternalAppDetector.protectedInstallation(
                    bundleNames: candidate.bundles, displayName: candidate.name,
                    directories: configuration.applicationDirectories, knownURL: candidate.knownURL,
                    intune: inventory, artCraft: artCraft, additionalURLs: recorded
                )
                var existingKnown: URL?
                if let known = candidate.knownURL {
                    do {
                        if try known.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { existingKnown = known }
                    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { }
                }
                let matching = ExternalAppDetector.appURLs(
                    bundleNames: candidate.bundles, displayName: candidate.name,
                    directories: configuration.applicationDirectories
                ) + artCraft.matchingAppURLs(bundleNames: candidate.bundles, displayName: candidate.name) + recorded
                let multipleCopies = ExternalAppDetector.hasMultipleCopies(matching)
                let url = (multipleCopies ? existingKnown : nil) ?? recorded.first ?? existingKnown ?? matching.first
                let selectedProtection: ProtectedAppInstallation? = if multipleCopies, let url {
                    try ExternalAppDetector.protection(at: url, intune: inventory, artCraft: artCraft)
                } else {
                    nil
                }
                return (protection, url?.resolvingSymlinksInPath().standardizedFileURL,
                        multipleCopies, selectedProtection)
            }
        }.value
        try Task.checkCancellation()
        try configuration.validateCurrent()
        for (vm, (protection, url, multipleCopies, selectedProtection)) in zip(vms, evidence) {
            vm.protectedAppInstallation = protection
            vm.installedBundleURL = url
            vm.hasMultipleInstalledCopies = multipleCopies
            vm.hasSelectedCopyProvenance = multipleCopies
            vm.selectedCopyProtection = selectedProtection
        }
    }

    private func blockProtectedManagement(
        of vm: CaskViewModel, configuration: BrewOperationConfiguration,
        intuneInventory: IntuneAppDetector.Snapshot? = nil,
        artCraftInventory: ArtCraftAppDetector.Snapshot? = nil,
        appBundleNames: [String]? = nil
    ) async -> Bool {
        if vm.isAdditionalInstalledCopy {
            await reportManagementBlock(for: vm, error: CaskAdoptionError.multipleInstallations)
            return true
        }
        do {
            try await refreshOwnership(
                for: [vm], configuration: configuration,
                intuneInventory: intuneInventory, artCraftInventory: artCraftInventory,
                bundleNames: appBundleNames.map { [vm.fullToken: $0] } ?? [:]
            )
            return await blockKnownProtectedManagement(of: vm)
        } catch {
            if Task.isCancelled {
                vm.progressState = .idle
                return true
            }
            await reportManagementBlock(for: vm, error: error)
        }
        return true
    }

    private func blockKnownProtectedManagement(of vm: CaskViewModel) async -> Bool {
        vm.managementSourceOverrides = ProtectedAppInstallation.Source.enabledOverrides()
        if let protection = vm.managementProtection {
            vm.isOutdated = false
            await reportManagementBlock(for: vm, error: protection.source.blockError)
            return true
        }
        if vm.hasMultipleInstalledCopies || vm.isAdditionalInstalledCopy {
            vm.isOutdated = false
            await reportManagementBlock(for: vm, error: CaskAdoptionError.multipleInstallations)
            return true
        }
        return false
    }

    private func reportManagementBlock(for vm: CaskViewModel, error: Error) async {
        await showFailure(
            for: vm, error: error, output: error.localizedDescription,
            failureTitle: String(localized: "Homebrew action blocked"),
            failureMessage: error.localizedDescription
        )
    }

    private func verifiedInstallationTargets(
        of vm: CaskViewModel, configuration: BrewOperationConfiguration
    ) async -> [String]? {
        do {
            if vm.warning?.isDisabled == true { throw CaskAdoptionError.homebrewDisabled }
            let info = try await getAdditionalInfoForCask(vm, configuration: configuration)
            if info.disabled { throw CaskAdoptionError.homebrewDisabled }
            guard let artifacts = info.artifacts,
                  artifacts.allSatisfy({ $0.app == nil || $0.bundleName != nil }) else {
                throw CaskAdoptionError.installationTargetsUnavailable
            }
            if Task.isCancelled {
                vm.progressState = .idle
                return nil
            }
            vm.homebrewManagementError = nil
            return Array(Set(vm.appBundleNames + artifacts.compactMap(\.bundleName))).sorted()
        } catch {
            if Task.isCancelled {
                vm.progressState = .idle
                return nil
            }
            vm.homebrewManagementError = error.localizedDescription
            vm.isOutdated = false
            await reportManagementBlock(for: vm, error: error)
            return nil
        }
    }

    /// Validates the selected brew path before an operation runs. On failure it hands the fault to
    /// `recoverBrew` rather than reacting locally: a transient probe failure re-resolves silently
    /// and the operation proceeds, while a real one turns `bootstrap.phase` broken, which raises the
    /// setup overlay — the single surface for an unusable brew. The caller resets its own casks'
    /// progress state on `false`.
    private func brewPathIsValid(configuration: BrewOperationConfiguration) async -> Bool {
        guard await BrewPaths.isBrewPathValid(at: configuration.executable) else {
            Self.logger.error("Couldn't start brew operation because brew path is invalid")

            // Unwired (no owner, i.e. not the running app) — nothing can recover it here.
            guard let recoverBrew else { return false }

            guard await recoverBrew() else { return false }

            Self.logger.info("Brew re-resolved successfully — continuing the operation")
            return true
        }
        return true
    }

    /// Runs `operation` on the serial brew queue (after any in-flight/queued op) and returns its
    /// result. Used to sequence the read-side installed/outdated refresh with install/uninstall/
    /// update *writes*: without this, a stage-2 `brew list`/`outdated` snapshot taken before an
    /// install finishes can land afterwards and reconcile the just-installed cask back to "not
    /// installed" (the F2 / P2-3 dual-writer stomp). On the queue, the refresh's snapshot is always
    /// taken after every completed op, so it can never revert one.
    func runSerialized<T: Sendable>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = queueTail
        let opTask = Task { @MainActor () async throws -> T in
            await previous?.value
            return try await operation()
        }
        // Chain the queue tail so later ops wait for this one; the op's own error is the caller's.
        queueTail = Task { _ = try? await opTask.value }
        return try await opTask.value
    }

    // MARK: - Bulk (batch) operations

    private enum BatchKind {
        case install, update

        var subcommand: String { self == .install ? "install" : "upgrade" }
        var busyLabel: String {
            self == .install
                ? String(localized: "Installing", comment: "Install progress text")
                : String(localized: "Updating", comment: "Update progress text")
        }
        /// `==> Installing Cask <token>` (install) / `==> Upgrading <token>` (update).
        var startMarker: String { self == .install ? "Installing Cask " : "Upgrading " }
        /// The tail of `🍺 <token> was successfully installed!/upgraded!`.
        var successNeedle: String { self == .install ? "successfully installed" : "successfully upgraded" }
    }

    /// Enqueues a bulk op as ONE brew process on the serial queue, tracking every cask as its
    /// own `ActiveBrewTask` (all sharing this batch task) so each card shows in `ActiveTasksView`.
    private func runBatch(_ vms: [CaskViewModel], kind: BatchKind) {
        guard !vms.isEmpty else { return }
        let configuration = BrewOperationConfiguration.current

        let batchTokens = Set(vms.map(\.fullToken))
        // Drop any lingering entries for these casks (e.g. a dismissed-or-not failure) before re-queuing.
        activeTasks.removeAll { batchTokens.contains($0.viewModel.fullToken) }
        for vm in vms { vm.progressState = .busy(withTask: waitingLabel) }

        let previous = queueTail
        let handle = BatchHandle()
        let operationID = UUID()
        let task = Task {
            await previous?.value

            // Now running — publish this batch so the Active Tasks "Stop" can cancel just it.
            self.runningBatch = handle
            defer {
                // Keep failed casks in the task list until dismissed; remove the rest. Scope to this
                // batch's rows so it can't evict a separate op's row for a shared cask (P2-10).
                self.activeTasks.removeAll {
                    $0.operationID == operationID && !$0.viewModel.progressState.isFailed
                }
                if self.runningBatch === handle { self.runningBatch = nil }
            }

            if Task.isCancelled {
                for vm in vms { vm.progressState = .idle }
                return
            }
            let intuneInventory: IntuneAppDetector.Snapshot
            let artCraftInventory: ArtCraftAppDetector.Snapshot
            do {
                let load = self.loadIntuneInventory
                let loadArtCraft = self.loadArtCraftInventory
                (intuneInventory, artCraftInventory) = try await Task.detached {
                    (try load(), try loadArtCraft())
                }.value
            } catch {
                for vm in vms {
                    if Task.isCancelled {
                        vm.progressState = .idle
                    } else {
                        await self.reportManagementBlock(for: vm, error: error)
                    }
                }
                return
            }
            var eligible: [CaskViewModel] = []
            for vm in vms {
                if !(await self.blockProtectedManagement(
                    of: vm, configuration: configuration,
                    intuneInventory: intuneInventory, artCraftInventory: artCraftInventory
                )) {
                    eligible.append(vm)
                }
            }
            if Task.isCancelled {
                for vm in eligible { vm.progressState = .idle }
                return
            }
            guard !eligible.isEmpty else { return }
            guard await self.brewPathIsValid(configuration: configuration) else {
                for vm in eligible { vm.progressState = .idle }
                return
            }
            var supported: [CaskViewModel] = []
            var verifiedBundles: [CaskId: [String]] = [:]
            for vm in eligible {
                if let bundles = await self.verifiedInstallationTargets(of: vm, configuration: configuration) {
                    verifiedBundles[vm.fullToken] = bundles
                    supported.append(vm)
                }
            }
            if Task.isCancelled {
                for vm in supported { vm.progressState = .idle }
                return
            }
            guard !supported.isEmpty else { return }
            var unconfirmed: [CaskId: URL] = [:]
            do {
                if kind == .install {
                    unconfirmed = try await self.externalInstallations(
                        in: supported, configuration: configuration, bundleNames: verifiedBundles
                    )
                }
                try await self.refreshOwnership(
                    for: supported, configuration: configuration, bundleNames: verifiedBundles
                )
            } catch {
                for vm in supported {
                    if Task.isCancelled {
                        vm.progressState = .idle
                    } else {
                        await self.reportManagementBlock(for: vm, error: error)
                    }
                }
                return
            }
            // Do not yield between final permission decisions: notifying about one blocked
            // entry could otherwise let Settings revoke permission for an earlier entry.
            let overrides = ProtectedAppInstallation.Source.enabledOverrides()
            var allowed: [CaskViewModel] = []
            var blocked: [(CaskViewModel, CaskAdoptionError)] = []
            for vm in supported {
                vm.managementSourceOverrides = overrides
                if let protection = vm.managementProtection {
                    let error = protection.source.blockError
                    vm.isOutdated = false
                    vm.progressState = .failed(output: error.localizedDescription)
                    blocked.append((vm, error))
                } else if vm.hasMultipleInstalledCopies || vm.isAdditionalInstalledCopy {
                    let error = CaskAdoptionError.multipleInstallations
                    vm.isOutdated = false
                    vm.progressState = .failed(output: error.localizedDescription)
                    blocked.append((vm, error))
                } else if let url = unconfirmed[vm.fullToken] {
                    vm.isInstalled = false
                    if UserDefaults.standard.value(for: Preferences.detectExternallyInstalledApps) {
                        vm.externalAppURL = url
                    }
                    let error = CaskAdoptionError.confirmationRequired
                    vm.progressState = .failed(output: error.localizedDescription)
                    blocked.append((vm, error))
                } else {
                    allowed.append(vm)
                }
            }
            if !allowed.isEmpty {
                await self.runBatchOperation(allowed, kind: kind, configuration: configuration)
            }
            for (vm, error) in blocked {
                await self.reportManagementBlock(for: vm, error: error)
            }
        }

        handle.task = task
        queueTail = task
        for vm in vms { activeTasks.append(ActiveBrewTask(operationID: operationID, viewModel: vm, task: task)) }
    }

    /// Cancels the currently-running bulk operation (the whole `brew install/upgrade --cask <all>`
    /// process, since it's one invocation). Queued single ops are unaffected. No-op if none running.
    func cancelBatch() {
        runningBatch?.task?.cancel()
    }

    /// Runs the batch brew process and routes its streamed per-cask output to each card.
    private func runBatchOperation(
        _ vms: [CaskViewModel], kind: BatchKind, configuration: BrewOperationConfiguration
    ) async {
        do {
            try Task.checkCancellation()
            try configuration.validateCurrent()
        } catch {
            for vm in vms {
                if Task.isCancelled {
                    vm.progressState = .idle
                } else {
                    await self.showFailure(
                        for: vm, error: error, output: error.localizedDescription,
                        failureTitle: String(localized: "Couldn't start app installation"),
                        failureMessage: error.localizedDescription
                    )
                }
            }
            return
        }
        // token AND fullToken → vm, so brew's per-cask output lines (which name either) can be
        // routed to a card. If two casks in the batch share a key (e.g. a core cask and a tap cask
        // with the same bare token), drop that key so it can't mis-route — those fall to reconcile.
        var lookup: [String: CaskViewModel] = [:]
        var ambiguousKeys: Set<String> = []
        for vm in vms {
            for key in [vm.token, vm.fullToken] {
                if let existing = lookup[key], existing !== vm {
                    ambiguousKeys.insert(key)
                } else {
                    lookup[key] = vm
                }
            }
        }
        for key in ambiguousKeys { lookup[key] = nil }

        var arguments = [kind.subcommand, "--cask"] + vms.map(\.fullToken)
        if kind == .install {
            // A batch cannot provide per-app consent to replace an existing installation.
            arguments.append(contentsOf: configuration.appdirArguments)
        }

        batchProgress = BatchProgress(completed: 0, total: vms.count, isUpdate: kind == .update)
        defer { batchProgress = nil }

        var perCaskError: [String: String] = [:]
        var completeOutput = ""
        var configurationChanged = false

        do {
            for try await line in Shell.stream(configuration.executable, arguments, pty: true) {
                if Task.isCancelled { break }
                completeOutput += line + "\n"
                if configuration != .current { configurationChanged = true }
                guard !configurationChanged else { continue }
                applyBatchLine(line, kind: kind, lookup: lookup, perCaskError: &perCaskError)
            }
        } catch {
            // A non-zero exit is expected when any cask fails (reconcile decides per-cask outcome).
            // A user cancel also throws here — don't log that as an error.
            if !Task.isCancelled {
                Self.logger.error("Batch \(kind.subcommand) stream ended: \(error.localizedDescription)")
            }
        }

        if Task.isCancelled {
            for vm in vms { vm.progressState = .idle }
            return
        }
        if configurationChanged || configuration != .current {
            await failBatchForConfigurationChange(vms, output: completeOutput)
            return
        }

        do {
            try await reconcileBatch(
                vms, kind: kind, perCaskError: perCaskError, output: completeOutput, configuration: configuration
            )
        } catch is CancellationError {
            for vm in vms { vm.progressState = .idle }
        } catch {
            guard configuration == .current else {
                await failBatchForConfigurationChange(vms, output: completeOutput)
                return
            }
            for vm in vms {
                switch vm.progressState {
                case .success:
                    vm.progressState = .idle
                case .failed:
                    break
                default:
                    await showFailure(
                        for: vm, error: error, output: completeOutput + "\n" + error.localizedDescription,
                        failureTitle: String(localized: "Couldn't refresh installed apps"),
                        failureMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    private func failBatchForConfigurationChange(_ vms: [CaskViewModel], output: String) async {
        let error = CaskAdoptionError.configurationChanged
        for vm in vms {
            await showFailure(
                for: vm, error: error, output: output + "\n" + error.localizedDescription,
                failureTitle: String(localized: "Couldn't refresh installed apps"),
                failureMessage: error.localizedDescription
            )
        }
    }

    /// Routes one streamed batch-output line to the matching cask's `progressState`.
    private func applyBatchLine(
        _ line: String,
        kind: BatchKind,
        lookup: [String: CaskViewModel],
        perCaskError: inout [String: String]
    ) {
        // 1. Per-cask download line: "⠙ Cask <token> (<ver>) … Downloading <dl>/<total>".
        //    Brew redraws these in place; `Shell.stream` yields each as its own frame.
        if let match = line.firstMatch(of: /Cask (\S+) \(/), let vm = lookup[String(match.1)] {
            if line.contains("Downloading"), let percent = Self.downloadPercent(from: line) {
                vm.progressState = .downloading(percent: percent)
                return
            }
            // Fetch finished (Downloaded / Verifying / Verified) — but a batch installs each cask
            // sequentially *after* all downloads, so show "Waiting…" rather than a stuck 100% ring
            // until this cask's "Installing Cask …" marker arrives.
            if line.contains("Downloaded") || line.contains("Verif") {
                vm.progressState = .busy(withTask: waitingLabel)
                return
            }
            // Any other Cask-mentioning line (e.g. the "Fetching downloads for:" heading) — ignore.
            return
        }

        // 2. Install/upgrade start marker.
        if let range = line.range(of: kind.startMarker) {
            let token = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if let vm = lookup[token] {
                vm.progressState = .busy(withTask: kind.busyLabel)
                return
            }
        }

        // 3. Per-cask success: "🍺  <token> was successfully installed!/upgraded!".
        if line.contains(kind.successNeedle),
           let match = line.firstMatch(of: /(\S+) was successfully/),
           let vm = lookup[String(match.1)] {
            vm.progressState = .success
            if kind == .install { vm.isInstalled = true } else { vm.isOutdated = false }
            if var progress = batchProgress {
                progress.completed += 1
                batchProgress = progress
            }
            return
        }

        // 4. Per-cask error: "Error: <token>: <reason>" (batch continues past a failure).
        if line.hasPrefix("Error: "),
           let match = line.firstMatch(of: /Error: (\S+?):/),
           let vm = lookup[String(match.1)] {
            perCaskError[vm.fullToken] = line
            vm.progressState = .failed(output: line)
            if var progress = batchProgress {   // a failure still counts as "done"
                progress.completed += 1
                batchProgress = progress
            }
        }
    }

    /// Extracts a `<downloaded>/<total>` → ratio from a brew download line, or `nil`.
    private static func downloadPercent(from line: String) -> Double? {
        guard let match = line.firstMatch(of: /([0-9.]+)\s*([KMGT]?i?B)\s*\/\s*([0-9.]+)\s*([KMGT]?i?B)/),
              let downloaded = byteCount(match.1, match.2),
              let total = byteCount(match.3, match.4),
              total > 0 else {
            return nil
        }
        return min(downloaded / total, 1)
    }

    /// After the batch process ends, reconcile every cask's real end state with one brew query
    /// (covers "already installed" warnings and unmatched markers), reset cards, and send a
    /// single summary notification instead of one per cask.
    private func reconcileBatch(
        _ vms: [CaskViewModel],
        kind: BatchKind,
        perCaskError: [String: String],
        output: String,
        configuration: BrewOperationConfiguration
    ) async throws {
        // Casks that already got a success/error marker while streaming are authoritative — do
        // NOT re-derive them from a list query (its `--full-name` format may not match a token,
        // which would flip a genuinely-installed cask to a false failure). Only query brew for
        // casks with no marker ("already installed" warnings, unmatched output).
        func isResolved(_ vm: CaskViewModel) -> Bool {
            switch vm.progressState {
            case .success, .failed: return true
            default: return false
            }
        }
        var brewTokens: Set<String> = []
        if vms.contains(where: { !isResolved($0) }) {
            let args = kind == .install ? ["list", "--cask", "--full-name"] : ["outdated", "--cask", "-q"]
            let out = try await Shell.run(configuration.executable, args)
            try Task.checkCancellation()
            try configuration.validateCurrent()
            brewTokens = Set(out.split(whereSeparator: \.isNewline).map(String.init))
        }

        try Task.checkCancellation()
        try configuration.validateCurrent()
        var succeeded = 0
        var failedNames: [String] = []

        for vm in vms {
            let ok: Bool
            switch vm.progressState {
            case .success:
                ok = true   // isInstalled / isOutdated already set from the success marker
            case .failed:
                ok = false
            default:
                // No marker seen — decide from the single brew query. `list --full-name` is an
                // exact identity match; `outdated -q` prints bare tokens, so it stays loose but can
                // only mean *this* cask when it's the installed one.
                let listed = kind == .install
                    ? vm.matchesFullName(in: brewTokens)
                    : (vm.isInstalled && vm.matchesBareToken(in: brewTokens))
                switch kind {
                case .install:
                    ok = listed
                    vm.isInstalled = listed
                case .update:
                    ok = !listed           // absent from `outdated` == up to date
                    vm.isOutdated = listed
                }
            }

            if ok {
                vm.progressState = .idle
                succeeded += 1
            } else {
                if case .failed = vm.progressState {
                    // keep the per-cask error already parsed onto the card
                } else {
                    vm.progressState = .failed(output: perCaskError[vm.fullToken] ?? output)
                }
                failedNames.append(vm.name)
            }
        }

        if kind == .install {
            let installed = vms.filter { !$0.progressState.isFailed && $0.isInstalled }
            do {
                try await refreshOwnership(for: installed, configuration: configuration)
            } catch {
                for vm in installed {
                    vm.progressState = .failed(output: output + "\n" + error.localizedDescription)
                    failedNames.append(vm.name)
                    succeeded -= 1
                }
            }
        }

        for vm in vms where !vm.progressState.isFailed {
            vm.recordSuccessfulOperation()
        }

        // Distinct static keys per operation (don't splice a localized verb into another
        // localized string — that yields a dynamic key that can't be translated).
        let successTitle = kind == .install
            ? String(localized: "\(succeeded) apps installed", comment: "Bulk install success notification")
            : String(localized: "\(succeeded) apps updated", comment: "Bulk update success notification")

        if failedNames.isEmpty {
            Self.logger.info("Batch \(kind.subcommand): \(succeeded) succeeded")
            await notify(successTitle, "", .success)
        } else {
            let title = kind == .install
                ? String(localized: "\(succeeded) apps installed, \(failedNames.count) failed", comment: "Bulk install partial-failure notification")
                : String(localized: "\(succeeded) apps updated, \(failedNames.count) failed", comment: "Bulk update partial-failure notification")
            let names = failedNames.joined(separator: ", ")
            Self.logger.error("Batch \(kind.subcommand): \(succeeded) ok, failed: \(names)")
            // No alert: each failed cask keeps its own error row, and those rows stay in Active
            // Tasks (badged) after the batch ends — a persistent, actionable list beats a modal
            // summary the user dismisses once and can't get back.
            await notify(title, names, .failure)
        }
    }

    /// Parses a single line of streamed `brew install/upgrade --cask` output.
    /// Returns the new progress state, or `nil` if the line carries no progress
    /// signal (so the previous state is preserved instead of resetting to a spinner).
    ///
    /// NOTE: Homebrew's progress output is unstable across releases. If progress
    /// ever stops updating, this is the place to re-check against current `brew`
    /// output. Worst case is a spinner instead of a percentage — success/failure
    /// is still detected via the "successfully …" strings and the process exit code.
    private func parseBrewProgress(line: String, busyLabel: String) -> CaskProgressState? {
        // Active download → ring with %. Gate on "Downloading" specifically: the byte counter
        // also appears on the "Downloaded"/"Verified" lines (at 100%), and treating those as
        // downloading would freeze the ring at 100% through the verify/install gap.
        if line.contains("Downloading"), let percent = Self.downloadPercent(from: line) {
            return .downloading(percent: percent)
        }

        // Fetch finished (Downloaded / Verifying / Verified / Extracting) or install underway →
        // spinner with the operation label, so the ring doesn't linger at 100%.
        if line.contains("Downloaded") || line.contains("Verif") || line.contains("Extract")
            || line.contains("Preparing")
            || line.contains("Installing") || line.contains("Upgrading")
            || line.contains("Moving") || line.contains("Linking")
            || line.contains("Backing") || line.contains("Purging") {
            return .busy(withTask: busyLabel)
        }

        if line.contains("successfully installed") || line.contains("successfully upgraded") {
            return .success
        }

        return nil
    }

    /// Converts a brew size token (value + unit) to bytes. Base-1000 vs 1024 is
    /// irrelevant here — the value only feeds a ratio for the progress bar.
    private static func byteCount(_ value: Substring, _ unit: Substring) -> Double? {
        guard let number = Double(value) else { return nil }
        let multiplier: Double = switch unit.first {
            case "K": 1_000
            case "M": 1_000_000
            case "G": 1_000_000_000
            case "T": 1_000_000_000_000
            default:  1   // plain "B"
        }
        return number * multiplier
    }

    /// Streams a brew command, updating `vm.progressState` from each parsed line.
    /// Returns the complete output on success, or a ``BrewStreamError`` carrying
    /// the partial output on failure.
    private func streamBrewCommand(
        _ arguments: [String], vm: CaskViewModel, busyLabel: String, executable: URL? = nil
    ) async -> Result<String, BrewStreamError> {
        var completeOutput = ""

        do {
            for try await line in Shell.stream(executable ?? BrewPaths.currentBrewExecutable, arguments, pty: true) {
                completeOutput += line + "\n"

                if let newProgress = self.parseBrewProgress(line: line, busyLabel: busyLabel) {
                    vm.progressState = newProgress
                }
            }
        } catch {
            return .failure(BrewStreamError(underlying: error, output: completeOutput))
        }

        return .success(completeOutput)
    }

    /// Register successful task
    private func showSuccess(
        for vm: CaskViewModel,
        logMessage: String,
        notificationTitle: String,
        notificationMessage: String = ""
    ) async {
        Self.logger.info("\(logMessage)")

        vm.recordSuccessfulOperation()
        // Show success for 2 seconds
        vm.progressState = .success
        try? await Task.sleep(for: .seconds(2))
        vm.progressState = .idle

        await notify(notificationTitle, notificationMessage, .success)
    }

    /// Registers a failed task on the cask itself, and notifies.
    ///
    /// Deliberately raises no alert: the card's `.failed` row already reports this where the user is
    /// looking, persistently, with the terminal output a modal can't show and a Dismiss button — and
    /// the row survives in Active Tasks (badged in the sidebar) until dismissed. A modal on top of
    /// that is a fourth surface for one event, carrying the least information of the four.
    private func showFailure(
        for vm: CaskViewModel,
        error: Error,
        output: String,
        failureTitle: String,
        failureMessage: String
    ) async {
        Self.logger.error("\(failureTitle)\nError: \(error.localizedDescription)\nOutput: \(output)")

        vm.progressState = .failed(output: output)

        await notify(failureTitle, failureMessage, .failure)
    }
}
