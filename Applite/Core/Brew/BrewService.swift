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

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: BrewService.self)
    )

    // MARK: - Public Operations

    /// Installs the cask
    func install(_ vm: CaskViewModel, force: Bool = false) {
        runTask(for: vm) {
            Self.logger.info("Cask \"\(vm.token)\" installation started")

            // Appdir argument
            let appdirOn = UserDefaults.standard.value(for: Preferences.appdirOn)
            let appdirPath = UserDefaults.standard.value(for: Preferences.appdirPath)
            let appdirArgument = "--appdir=\"\(appdirPath)\""

            // Install command
            var arguments = [vm.token]
            if force { arguments.append("--force") }
            if appdirOn { arguments.append(appdirArgument) }

            let noQuarantine = UserDefaults.standard.value(for: Preferences.noQuarantine)
            if noQuarantine { arguments.append("--no-quarantine") }

            let command = "\(BrewPaths.currentBrewExecutable.quotedPath()) install --cask \(arguments.joined(separator: " "))"

            // Setup progress
            vm.progressState = .busy(withTask: "")

            // Run install command and stream output
            let result = await self.streamBrewCommand(
                command,
                vm: vm,
                busyLabel: String(localized: "Installing", comment: "Install progress text")
            )

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

    /// Updates the cask
    func update(_ vm: CaskViewModel) {
        runTask(for: vm) {
            let updateLabel = String(localized: "Updating", comment: "Update progress text")
            vm.progressState = .busy(withTask: updateLabel)

            let command = "\(BrewPaths.currentBrewExecutable.quotedPath()) upgrade --cask \(vm.fullToken)"

            if case .failure(let error) = await self.streamBrewCommand(command, vm: vm, busyLabel: updateLabel) {
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

            if case .failure(let error) = await self.streamBrewCommand(command, vm: vm, busyLabel: reinstallLabel) {
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

    /// Installs multiple casks
    func installAll(_ vms: [CaskViewModel]) {
        for vm in vms {
            self.install(vm)
        }
    }

    /// Updates multiple casks
    func updateAll(_ vms: [CaskViewModel]) {
        for vm in vms {
            self.update(vm)
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

    /// Starts a brew task and appends it to active tasks
    private func runTask(for vm: CaskViewModel, _ operation: @escaping () async -> Void) {
        let task = Task {
            defer {
                self.activeTasks.removeAll {
                    $0.viewModel == vm
                }
            }

            // Make sure brew path is valid
            guard await BrewPaths.isSelectedBrewPathValid() else {
                Self.logger.error("Couldn't start brew operation because brew path is invalid")
                alert.show(title: "Brew path is invalid", message: DependencyManager.brokenPathOrInstallMessage)
                return
            }

            await operation()
        }

        self.activeTasks.append(ActiveBrewTask(viewModel: vm, task: task))
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
        if let match = line.firstMatch(of: /([0-9.]+)\s*([KMGT]?i?B)\s*\/\s*([0-9.]+)\s*([KMGT]?i?B)/) {
            if let downloaded = Self.byteCount(match.1, match.2),
               let total = Self.byteCount(match.3, match.4),
               total > 0 {
                return .downloading(percent: min(downloaded / total, 1))
            }
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
