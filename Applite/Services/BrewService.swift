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
            let appdirOn = UserDefaults.standard.bool(forKey: Preferences.appdirOn.rawValue)
            let appdirPath = UserDefaults.standard.string(forKey: Preferences.appdirPath.rawValue)
            let appdirArgument = "--appdir=\"\(appdirPath ?? "/Applications")\""

            // Install command
            var arguments = [vm.token]
            if force { arguments.append("--force") }
            if appdirOn { arguments.append(appdirArgument) }

            let noQuarantine = UserDefaults.standard.bool(forKey: Preferences.noQuarantine.rawValue)
            if noQuarantine { arguments.append("--no-quarantine") }

            let command = "\(BrewPaths.currentBrewExecutable.quotedPath()) install --cask \(arguments.joined(separator: " "))"

            // Setup progress
            vm.progressState = .busy(withTask: "")

            /// Holds the complete output of the install process
            var completeOutput = ""

            // Run install command and stream output
            do {
                for try await line in Shell.stream(command, pty: true) {
                    completeOutput += line + "\n"

                    let newProgress = self.parseBrewInstall(output: line)
                    vm.progressState = newProgress
                }
            } catch {
                var alertMessage = error.localizedDescription

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
                    error: error,
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
            vm.progressState = .busy(withTask: String(localized: "Updating", comment: "Update progress text"))

            var output: String = ""

            do {
                output = try await Shell.runBrewCommand(["upgrade", "--cask", vm.fullToken])
            } catch {
                await self.showFailure(
                    for: vm,
                    error: error,
                    output: output,
                    alertTitle: String(localized: "Failed to update \(vm.name)", comment: "Failed app update alert title"),
                    alertMessage: error.localizedDescription
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
            vm.progressState = .busy(withTask: String(localized: "Reinstalling", comment: "Reinstall progress text"))

            var output: String = ""

            do {
                output = try await Shell.runBrewCommand(["reinstall", "--cask", vm.fullToken])
            } catch {
                await self.showFailure(
                    for: vm,
                    error: error,
                    output: output,
                    alertTitle: String(localized: "Failed to reinstall \(vm.name)", comment: "Failed reinstall alert title"),
                    alertMessage: error.localizedDescription
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

    /// Parses the shell output when installing a cask
    private func parseBrewInstall(output: String) -> CaskProgressState {
        if output.contains("Downloading") {
            return .busy(withTask: "")
        } else if output.contains("#") {
            let regex = /#+\s+(\d+\.\d+)%/

            if let result = output.firstMatch(of: regex) {
                return .downloading(percent: (Double(result.1) ?? 0) / 100)
            }
        }
        else if output.contains("Installing") || output.contains("Moving") || output.contains("Linking") {
            return .busy(withTask: String(localized: "Installing", comment: "Install progress text"))
        }
        else if output.contains("successfully installed") {
            return .success
        }

        return .busy(withTask: "")
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
