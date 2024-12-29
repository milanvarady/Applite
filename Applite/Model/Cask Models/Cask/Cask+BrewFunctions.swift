//
//  Cask+BrewFunctions.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.27.
//

import Foundation

extension Cask {
    /// Installs the cask
    ///
    /// - Parameters:
    ///   - caskData: ``CaskData`` object passed in by the view
    ///   - force: If `true` install will be run with the `--force` flag
    func install(caskData: CaskData, force: Bool = false) async {
        defer {
            resetProgressState(caskData: caskData)
        }

        Self.logger.info("Cask \"\(self.info.id)\" installation started")

        // Appdir argument
        let appdirOn = UserDefaults.standard.bool(forKey: Preferences.appdirOn.rawValue)
        let appdirPath = UserDefaults.standard.string(forKey: Preferences.appdirPath.rawValue)
        let appdirArgument = "--appdir=\"\(appdirPath ?? "/Applications")\""

        // Install command
        let command = "\(BrewPaths.currentBrewExecutable) install --cask \(force ? "--force" : "") \(self.id) \(appdirOn ? appdirArgument : "")"

        // Setup progress
        self.progressState = .busy(withTask: "")
        caskData.busyCasks.insert(self)

        /// Holds the complete output of the install process
        var completeOutput = ""

        // Run install command and stream output
        do {
            for try await line in Shell.stream(command, pty: true) {
                completeOutput += line
                self.progressState = self.parseBrewInstall(output: line)
            }
        } catch {
            let alertMessage = switch completeOutput {
            // Already installed
            case _ where completeOutput.contains("It seems there is already an App"):
                String(localized: "\(self.info.name) is already installed. If you want to add it to \(Bundle.main.appName) click more options (chevron icon) and press Force Install.")
            // Network error
            case _ where completeOutput.contains("Could not resolve host"):
                String(localized: "Couldn't download app. No internet connection, or host is unreachable.")
            default:
                error.localizedDescription
            }

            showFailure(
                error: error,
                output: completeOutput,
                alertTitle: "Failed to install \(self.info.name)",
                alertMessage: alertMessage
            )
            return
        }

        showSuccess(
            logMessage: "Successfully installed cask \(self.id)",
            alertTitle: "\(self.info.name) successfully installed!"
        )

        // Update state
        self.isInstalled = true
    }

    /// Uninstalls the cask
    /// - Parameters:
    ///     - caskData: ``CaskData`` object
    ///     - zap: If true the app will be uninstalled completely using the brew --zap flag
    func uninstall(caskData: CaskData, zap: Bool = false) async {
        defer {
            resetProgressState(caskData: caskData)
        }

        progressState = .busy(withTask: "Uninstalling")
        caskData.busyCasks.insert(self)

        var arguments: [String] = [self.info.id]

        // Add -- zap argument
        if zap {
            arguments.append("--zap")
        }

        var output: String = ""

        do {
            output = try await Shell.runBrewCommand("uninstall", arguments: arguments)
        } catch {
            showFailure(
                error: error,
                output: output,
                alertTitle: "Failed to uninstall \(self.info.name)",
                alertMessage: error.localizedDescription
            )
            return
        }

        showSuccess(
            logMessage: "Successfully uninstalled \(self.info.id)",
            alertTitle: "\(self.info.name) successfully uninstalled"
        )

        // Update state
        self.isInstalled = false
    }

    /// Updates the cask
    func update(caskData: CaskData) async {
        defer {
            resetProgressState(caskData: caskData)
        }

        progressState = .busy(withTask: "Updating")
        caskData.busyCasks.insert(self)

        var output: String = ""

        do {
            output = try await Shell.runBrewCommand("uninstall", arguments: [self.info.id])
        } catch {
            showFailure(
                error: error,
                output: output,
                alertTitle: "Failed to update \(self.info.name)",
                alertMessage: error.localizedDescription
            )
            return
        }

        showSuccess(
            logMessage: "Successfully updated \(self.id)",
            alertTitle: "\(self.info.name) successfully updated"
        )

        // Update state
        caskData.outdatedCasks.remove(self)
    }

    /// Reinstalls the cask
    func reinstall(caskData: CaskData) async {
        defer {
            resetProgressState(caskData: caskData)
        }

        progressState = .busy(withTask: "Reinstalling")
        caskData.busyCasks.insert(self)

        var output: String = ""

        do {
            output = try await Shell.runBrewCommand("uninstall", arguments: [self.info.id])
        } catch {
            showFailure(
                error: error,
                output: output,
                alertTitle: "Failed to reinstall \(self.info.name)",
                alertMessage: error.localizedDescription
            )
            return
        }

        showSuccess(
            logMessage: "Successfully reinstalled \(self.info.id)",
            alertTitle: "\(self.info.name) successfully reinstalled"
        )
    }

    // MARK: - Helper functions

    /// Parses the shell output when installing a cask
    private func parseBrewInstall(output: String) -> ProgressState {
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
        logMessage: String,
        alertTitle: String,
        alertMessage: String = ""
    ) {
        Self.logger.info("\(logMessage)")

        Task {
            await sendNotification(title: alertTitle, body: alertMessage, reason: .success)
        }

        // Show success for 2 seconds
        progressState = .success
        Task {
            try? await Task.sleep(for: .seconds(2))
            progressState = .idle
        }
    }

    /// Register failed task
    ///
    /// - Logs error
    /// - Shows alert and notification
    /// - Sets progress state to failed
    private func showFailure(
        error: Error,
        output: String,
        alertTitle: String,
        alertMessage: String,
        notificationTitle: String? = nil,
        notificationMessage: String = ""
    ) {
        // Log error
        Self.logger.error("\(alertTitle)\nError: \(error.localizedDescription)\nOutput: \(output)")

        // Alert
        alert.show(title: alertTitle, message: alertMessage)

        // Send notification
        let notificationTitle = notificationTitle ?? alertTitle

        Task {
            await sendNotification(title: notificationTitle, body: notificationMessage, reason: .failure)
        }

        // Set progress state to failed
        progressState = .failed(output: output)
    }

    /// Resets progress state and removes self from ``CaskData.busyCasks``
    private func resetProgressState(caskData: CaskData) {
        Task {
            caskData.busyCasks.remove(self)

            // Reset state unless it's not succes or failed
            switch self.progressState {
            case .success:
                break
            case .failed(_):
                break
            default:
                self.progressState = .idle
            }
        }
    }
}
