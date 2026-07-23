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
    let viewModel: CaskViewModel
    let task: Task<Void, Never>
}

/// Progress of an in-flight bulk operation (install-all / update-all).
struct BatchProgress: Equatable {
    var completed: Int
    var total: Int
    var label: String
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
    var alert = AlertManager()

    /// Progress of an in-flight bulk operation, or `nil` when none. Drives an aggregate
    /// "Installing X of N…" header (see `ActiveTasksView`).
    private(set) var batchProgress: BatchProgress?

    /// Tail of the serial operation queue. Every brew op chains after this so only ONE brew
    /// process runs at a time — Homebrew doesn't support concurrent `brew` invocations, and
    /// concurrent ones collide on its lock (silently dropping casks). A queued op shows "Waiting…".
    private var queueTail: Task<Void, Never>?

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
    func install(_ vm: CaskViewModel, force: Bool = false) -> Task<Void, Never> {
        return runTask(for: vm) {
            Self.logger.info("Cask \"\(vm.token)\" installation started")

            // Appdir argument
            let appdirOn = UserDefaults.standard.value(for: Preferences.appdirOn)
            let appdirPath = UserDefaults.standard.value(for: Preferences.appdirPath)
            let appdirArgument = "--appdir=\"\(appdirPath)\""

            // Install command
            var arguments = [vm.token]
            if force { arguments.append("--force") }
            if appdirOn { arguments.append(appdirArgument) }

            let command = "\(BrewPaths.currentBrewExecutable.quotedPath()) install --cask \(arguments.joined(separator: " "))"

            // Setup progress
            vm.progressState = .busy(withTask: "")

            // Run install command and stream output
            let result = await self.streamBrewCommand(
                command,
                vm: vm,
                busyLabel: String(localized: "Installing", comment: "Install progress text")
            )

            // Stopped by the user — no success/failure surface.
            if Task.isCancelled {
                vm.progressState = .idle
                return
            }

            if case .failure(let error) = result {
                let completeOutput = error.output
                var alertMessage = error.underlying.localizedDescription

                // Show a more helpful message in specific cases
                switch completeOutput {
                    // Already installed
                case _ where completeOutput.contains("It seems there is already an App"):
                    alertMessage = String(
                        localized: "\(vm.name) is already installed. If you want to add it to Applite click more options (chevron icon) and press Force Install.",
                        comment: "App already installed alert message (parameter: app name)"
                    )
                    // Network error
                case _ where completeOutput.contains("Could not resolve host"):
                    alertMessage = String(localized: "Couldn't download app. No internet connection, or host is unreachable.", comment: "No internet alert message")
                default:
                    // Homebrew error
                    if let result = completeOutput.firstMatch(of: /Error:(.+)/) {
                        alertMessage = String(result.1)
                    }
                }

                await self.showFailure(
                    for: vm,
                    error: error.underlying,
                    output: completeOutput,
                    alertTitle: String(localized: "Failed to install \(vm.name)", comment: "Install failure alert title"),
                    alertMessage: alertMessage
                )

                return
            }

            await self.showSuccess(
                for: vm,
                logMessage: "Successfully installed cask \(vm.token)",
                notificationTitle: String(localized: "\(vm.name) successfully installed!", comment: "Successful app install notification")
            )

            // Update state
            vm.isInstalled = true
        }
    }

    /// Uninstalls the cask
    func uninstall(_ vm: CaskViewModel, zap: Bool = false) {
        runTask(for: vm) {
            vm.progressState = .busy(withTask: String(localized: "Uninstalling", comment: "Uninstall progress text"))

            var arguments: [String] = ["uninstall", "--cask", vm.fullToken]

            // Add --zap argument
            if zap {
                arguments.append("--zap")
                arguments.append("--force")
            }

            var output: String = ""

            do {
                output = try await Shell.runBrewCommand(arguments)
            } catch {
                await self.showFailure(
                    for: vm,
                    error: error,
                    output: output,
                    alertTitle: String(localized: "Failed to uninstall \(vm.name)", comment: "Failed app install alert title"),
                    alertMessage: error.localizedDescription
                )
                return
            }

            await self.showSuccess(
                for: vm,
                logMessage: "Successfully uninstalled \(vm.fullToken)",
                notificationTitle: String(localized: "\(vm.name) successfully uninstalled", comment: "Successful app uninstall notification")
            )

            // Update state
            vm.isInstalled = false
        }
    }

    /// Updates the cask. Returns the tracking task so `updateAll` can serialize.
    @discardableResult
    func update(_ vm: CaskViewModel) -> Task<Void, Never> {
        return runTask(for: vm) {
            let updateLabel = String(localized: "Updating", comment: "Update progress text")
            vm.progressState = .busy(withTask: updateLabel)

            let command = "\(BrewPaths.currentBrewExecutable.quotedPath()) upgrade --cask \(vm.fullToken)"

            let result = await self.streamBrewCommand(command, vm: vm, busyLabel: updateLabel)

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
                    alertTitle: String(localized: "Failed to update \(vm.name)", comment: "Failed app update alert title"),
                    alertMessage: error.underlying.localizedDescription
                )
                return
            }

            await self.showSuccess(
                for: vm,
                logMessage: "Successfully updated \(vm.token)",
                notificationTitle: String(localized: "\(vm.name) successfully updated", comment: "Successful app update notification")
            )

            // Update state
            vm.isOutdated = false
        }
    }

    /// Reinstalls the cask
    func reinstall(_ vm: CaskViewModel) {
        runTask(for: vm) {
            let reinstallLabel = String(localized: "Reinstalling", comment: "Reinstall progress text")
            vm.progressState = .busy(withTask: reinstallLabel)

            let command = "\(BrewPaths.currentBrewExecutable.quotedPath()) reinstall --cask \(vm.fullToken)"

            let result = await self.streamBrewCommand(command, vm: vm, busyLabel: reinstallLabel)

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
                    alertTitle: String(localized: "Failed to reinstall \(vm.name)", comment: "Failed reinstall alert title"),
                    alertMessage: error.underlying.localizedDescription
                )
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

    /// Cancels every active task and waits for them to unwind (terminating their
    /// brew processes via `Shell.stream`'s onTermination), bounded by a timeout so
    /// quitting can never block indefinitely. Used by the quit-confirmation flow.
    func cancelAllAndWait() async {
        let tasks = activeTasks.map(\.task)
        for task in tasks { task.cancel() }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for task in tasks { await task.value }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
            }
            // Return as soon as either all tasks finished unwinding or the timeout fired.
            await group.next()
            group.cancelAll()
        }
    }

    /// Gets additional info for a cask from brew CLI
    func getAdditionalInfoForCask(_ vm: CaskViewModel) async throws -> CaskAdditionalInfo {
        let json = try await Shell.runBrewCommand(["info", "--json=v2", "--cask", vm.fullToken])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let responseObject = try decoder.decode(CaskAdditionalInfoResponse.self, from: json.data(using: .utf8)!)

        guard let additionalInfo = responseObject.casks.first else {
            Self.logger.error("Couldn't find cask \(vm.fullToken)")
            throw CaskLoadError.failedToLoadAdditionalInfo
        }

        return additionalInfo
    }

    // MARK: - Helper Functions

    /// Enqueues a single-cask brew operation on the serial queue and tracks it. Returns the
    /// task. The op waits for any earlier queued op to finish (only one brew process at a time);
    /// until then the card shows "Waiting…".
    @discardableResult
    private func runTask(for vm: CaskViewModel, _ operation: @escaping () async -> Void) -> Task<Void, Never> {
        vm.progressState = .busy(withTask: waitingLabel)

        let previous = queueTail
        let task = Task {
            await previous?.value

            defer {
                self.activeTasks.removeAll {
                    $0.viewModel == vm
                }
            }

            // Cancelled while still queued — reset and skip cleanly.
            if Task.isCancelled {
                vm.progressState = .idle
                return
            }

            // Make sure brew path is valid
            guard await BrewPaths.isSelectedBrewPathValid() else {
                Self.logger.error("Couldn't start brew operation because brew path is invalid")
                alert.show(title: "Brew path is invalid", message: AnnexBrewManager.brokenPathOrInstallMessage)
                vm.progressState = .idle
                return
            }

            await operation()
        }

        queueTail = task
        self.activeTasks.append(ActiveBrewTask(viewModel: vm, task: task))
        return task
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

        for vm in vms { vm.progressState = .busy(withTask: waitingLabel) }

        let previous = queueTail
        let batchTokens = Set(vms.map(\.fullToken))
        let task = Task {
            await previous?.value

            defer { self.activeTasks.removeAll { batchTokens.contains($0.viewModel.fullToken) } }

            if Task.isCancelled {
                for vm in vms { vm.progressState = .idle }
                return
            }
            guard await BrewPaths.isSelectedBrewPathValid() else {
                Self.logger.error("Couldn't start bulk operation because brew path is invalid")
                alert.show(title: "Brew path is invalid", message: AnnexBrewManager.brokenPathOrInstallMessage)
                for vm in vms { vm.progressState = .idle }
                return
            }
            await self.runBatchOperation(vms, kind: kind)
        }

        queueTail = task
        for vm in vms { activeTasks.append(ActiveBrewTask(viewModel: vm, task: task)) }
    }

    /// Runs the batch brew process and routes its streamed per-cask output to each card.
    private func runBatchOperation(_ vms: [CaskViewModel], kind: BatchKind) async {
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

        var arguments = vms.map(\.fullToken)
        if kind == .install {
            let appdirOn = UserDefaults.standard.value(for: Preferences.appdirOn)
            let appdirPath = UserDefaults.standard.value(for: Preferences.appdirPath)
            if appdirOn { arguments.append("--appdir=\"\(appdirPath)\"") }
        }
        let command = "\(BrewPaths.currentBrewExecutable.quotedPath()) \(kind.subcommand) --cask \(arguments.joined(separator: " "))"

        batchProgress = BatchProgress(completed: 0, total: vms.count, label: kind.busyLabel)
        defer { batchProgress = nil }

        var perCaskError: [String: String] = [:]
        var completeOutput = ""

        do {
            for try await line in Shell.stream(command, pty: true) {
                if Task.isCancelled { break }
                completeOutput += line + "\n"
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

        await reconcileBatch(vms, kind: kind, perCaskError: perCaskError, output: completeOutput)
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
        if let match = line.firstMatch(of: /Cask (\S+) \(/),
           let vm = lookup[String(match.1)],
           let percent = Self.downloadPercent(from: line) {
            vm.progressState = .downloading(percent: percent)
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
        output: String
    ) async {
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
            let out = (try? await Shell.runBrewCommand(args)) ?? ""
            brewTokens = Set(out.split(whereSeparator: \.isNewline).map(String.init))
        }

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
                // No marker seen — decide from the single brew query.
                let listed = brewTokens.contains(vm.fullToken) || brewTokens.contains(vm.token)
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

        let verb = kind == .install
            ? String(localized: "installed", comment: "Bulk op past-tense verb")
            : String(localized: "updated", comment: "Bulk op past-tense verb")

        if failedNames.isEmpty {
            Self.logger.info("Batch \(kind.subcommand): \(succeeded) succeeded")
            await sendNotification(
                title: String(localized: "\(succeeded) apps \(verb)", comment: "Bulk op success notification"),
                body: "",
                reason: .success
            )
        } else {
            let title = String(localized: "\(succeeded) apps \(verb), \(failedNames.count) failed",
                               comment: "Bulk op partial-failure notification")
            let names = failedNames.joined(separator: ", ")
            Self.logger.error("Batch \(kind.subcommand): \(succeeded) ok, failed: \(names)")
            alert.show(title: LocalizedStringKey(title), message: names)
            await sendNotification(title: title, body: names, reason: .failure)
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
        // Download phase — live-updating line, e.g.
        //   "✔︎ Cask antinote (1.1.7)   Downloading   3.1MB/  6.7MB"
        // The status text cycles Downloading → Downloaded → Verified while the
        // "<downloaded>/<total>" byte counters update in place.
        if let percent = Self.downloadPercent(from: line) {
            return .downloading(percent: percent)
        }

        // Post-download phase (install / upgrade)
        if line.contains("Installing") || line.contains("Upgrading")
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
    private func streamBrewCommand(_ command: String, vm: CaskViewModel, busyLabel: String) async -> Result<String, BrewStreamError> {
        var completeOutput = ""

        do {
            for try await line in Shell.stream(command, pty: true) {
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

        // Show success for 2 seconds
        vm.progressState = .success
        try? await Task.sleep(for: .seconds(2))
        vm.progressState = .idle

        await sendNotification(title: notificationTitle, body: notificationMessage, reason: .success)
    }

    /// Register failed task
    private func showFailure(
        for vm: CaskViewModel,
        error: Error,
        output: String,
        alertTitle: String,
        alertMessage: String,
        notificationTitle: String? = nil,
        notificationMessage: String = ""
    ) async {
        // Log error
        Self.logger.error("\(alertTitle)\nError: \(error.localizedDescription)\nOutput: \(output)")

        // Alert
        alert.show(title: LocalizedStringKey(alertTitle), message: alertMessage)

        // Send notification
        let notificationTitle = notificationTitle ?? alertTitle

        // Set progress state to failed
        vm.progressState = .failed(output: output)

        await sendNotification(title: notificationTitle, body: notificationMessage, reason: .failure)
    }
}
