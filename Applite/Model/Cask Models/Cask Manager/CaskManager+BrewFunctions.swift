//
//  Cask+BrewFunctions.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.27.
//

import Foundation

extension CaskManager {
    /// Installs the cask
    ///
    /// - Parameters:
    ///   - caskManager: ``CaskData`` object passed in by the view
    ///   - force: If `true` install will be run with the `--force` flag
    func install(_ cask: Cask, force: Bool = false) {
        runTask(for: cask) {
            Self.logger.info("Cask \"\(cask.id)\" installation started")

            // Appdir argument
            let appdirOn = UserDefaults.standard.bool(forKey: Preferences.appdirOn.rawValue)
            let appdirPath = UserDefaults.standard.string(forKey: Preferences.appdirPath.rawValue)
            let appdirArgument = "--appdir=\"\(appdirPath ?? "/Applications")\""

            // Install command
            var arguments = [cask.id]
            if force { arguments.append("--force") }
            if appdirOn { arguments.append(appdirArgument) }

            let noQuarantine = UserDefaults.standard.bool(forKey: Preferences.noQuarantine.rawValue)
            if noQuarantine { arguments.append("--no-quarantine") }

            let command = "\(BrewPaths.currentBrewExecutable) install --cask \(arguments.joined(separator: " "))"

            // Setup progress
            cask.progressState = .busy(withTask: "")

            /// Holds the complete output of the install process
            var completeOutput = ""

            // Run install command and stream output
            do {
                for try await line in Shell.stream(command, pty: true) {
                    completeOutput += line

                    let newProgress = self.parseBrewInstall(output: line)
                    cask.progressState = newProgress
                }
            } catch {
                let alertMessage = switch completeOutput {
                    // Already installed
                case _ where completeOutput.contains("It seems there is already an App"):
                    String(localized: "\(cask.info.name) is already installed. If you want to add it to Applite click more options (chevron icon) and press Force Install.")
                    // Network error
                case _ where completeOutput.contains("Could not resolve host"):
                    String(localized: "Couldn't download app. No internet connection, or host is unreachable.")
                default:
                    error.localizedDescription
                }

                await self.showFailure(
                    for: cask,
                    error: error,
                    output: completeOutput,
                    alertTitle: "Failed to install \(cask.info.name)",
                    alertMessage: alertMessage
                )
                return
            }

            await self.showSuccess(
                for: cask,
                logMessage: "Successfully installed cask \(cask.id)",
                alertTitle: "\(cask.info.name) successfully installed!"
            )

            // Update state
            cask.isInstalled = true
            self.installedCasks.addCask(cask)
        }
    }

    /// Uninstalls the cask
    /// - Parameters:
    ///     - caskManager: ``CaskData`` object
    ///     - zap: If true the app will be uninstalled completely using the brew --zap flag
    func uninstall(_ cask: Cask, zap: Bool = false) {
        runTask(for: cask) {
            cask.progressState = .busy(withTask: "Uninstalling")

            var arguments: [String] = ["uninstall", "--cask", cask.info.id]

            // Add -- zap argument
            if zap {
                arguments.append("--zap")
            }

            var output: String = ""

            do {
                output = try await Shell.runBrewCommand(arguments)
            } catch {
                await self.showFailure(
                    for: cask,
                    error: error,
                    output: output,
                    alertTitle: "Failed to uninstall \(cask.info.name)",
                    alertMessage: error.localizedDescription
                )
                return
            }

            await self.showSuccess(
                for: cask,
                logMessage: "Successfully uninstalled \(cask.info.id)",
                alertTitle: "\(cask.info.name) successfully uninstalled"
            )

            // Update state
            cask.isInstalled = false
            self.installedCasks.remove(cask)
        }
    }

    /// Updates the cask
    func update(_ cask: Cask) {
        runTask(for: cask) {
            cask.progressState = .busy(withTask: "Updating")

            var output: String = ""

            do {
                output = try await Shell.runBrewCommand(["upgrade", "--cask", cask.info.id])
            } catch {
                await self.showFailure(
                    for: cask,
                    error: error,
                    output: output,
                    alertTitle: "Failed to update \(cask.info.name)",
                    alertMessage: error.localizedDescription
                )
                return
            }

            await self.showSuccess(
                for: cask,
                logMessage: "Successfully updated \(cask.id)",
                alertTitle: "\(cask.info.name) successfully updated"
            )

            // Update state
            self.outdatedCasks.remove(cask)
        }
    }

    /// Reinstalls the cask
    func reinstall(_ cask: Cask) {
        runTask(for: cask) {
            cask.progressState = .busy(withTask: "Reinstalling")

            var output: String = ""

            do {
                output = try await Shell.runBrewCommand(["reinstall", "--cask", cask.info.id])
            } catch {
                await self.showFailure(
                    for: cask,
                    error: error,
                    output: output,
                    alertTitle: "Failed to reinstall \(cask.info.name)",
                    alertMessage: error.localizedDescription
                )
                return
            }

            await self.showSuccess(
                for: cask,
                logMessage: "Successfully reinstalled \(cask.info.id)",
                alertTitle: "\(cask.info.name) successfully reinstalled"
            )
        }
    }

    /// Installs multiple
    func installAll(_ casks: [Cask]) {
        for cask in casks {
            self.install(cask)
        }
    }

    /// Updates multiple casks
    func updateAll(_ casks: [Cask]) {
        for cask in casks {
            self.update(cask)
        }
    }

    func getAdditionalInfoForCask(_ cask: Cask) async throws -> CaskAdditionalInfo {
        let json = try await Shell.runBrewCommand(["info", "--json=v2", "--cask", cask.info.id])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let responseObject = try decoder.decode(CaskAdditionalInfoResponse.self, from: json.data(using: .utf8)!)

        guard let additionalInfo = responseObject.casks.first else {
            Self.logger.error("Couldn't find cask \(cask.info.id)")
            throw CaskLoadError.failedToLoadAdditionalInfo
        }

        return additionalInfo
    }

    // MARK: - Helper functions

    /// Starts a brew task and appends it to active tasks
    private func runTask(for cask: Cask, _ operation: @escaping () async -> Void) {
        let task = Task {
            defer {
                self.activeTasks.removeAll {
                    $0.cask == cask
                }
            }

            // Make sure if brew path is valid
            guard await BrewPaths.isSelectedBrewPathValid() else {
                Self.logger.error("Couln't start brew operation because brew path is invalid")
                alert.show(title: "Brew path is invalid", message: DependencyManager.brokenPathOrIstallMessage)
                return
            }

            await operation()
        }

        self.activeTasks.append((cask: cask, task: task))
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
            return .busy(withTask: String(localized: "Installing"))
        }
        else if output.contains("successfully installed") {
            return .success
        }

        return .busy(withTask: "")
    }

    /// Register successful task
    ///
    /// - Logs success
    /// - Sends notification
    /// - Sets progress state to success for 2 seconds
    private func showSuccess(
        for cask: Cask,
        logMessage: String,
        alertTitle: String,
        alertMessage: String = ""
    ) async {
        Self.logger.info("\(logMessage)")

        // Show success for 2 seconds
        cask.progressState = .success
        try? await Task.sleep(for: .seconds(2))
        cask.progressState = .idle

        await sendNotification(title: alertTitle, body: alertMessage, reason: .success)
    }

    /// Register failed task
    ///
    /// - Logs error
    /// - Shows alert and notification
    /// - Sets progress state to failed
    private func showFailure(
        for cask: Cask,
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
        alert.show(title: alertTitle, message: alertMessage)

        // Send notification
        let notificationTitle = notificationTitle ?? alertTitle

        // Set progress state to failed
        cask.progressState = .failed(output: output)

        await sendNotification(title: notificationTitle, body: notificationMessage, reason: .failure)
    }
}
