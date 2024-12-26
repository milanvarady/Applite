//
//  Cask.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 04..
//

import SwiftUI
import os

/// Holds all essential data of a Homebrew cask and provides methods to run brew commands on it (e.g. install, uninstall, update)
final class Cask: Identifiable, Decodable, Hashable, ObservableObject {
    /// Unique id of the class, this is the same name you would use to download the cask with brew
    let id: String
    /// Longer format cask name
    let name: String
    /// Short description
    let description: String
    let homepageURL: URL?
    /// Number of downloads in the last 365 days
    var downloadsIn365days: Int = 0
    /// Description of any caveats with the app
    let caveats: String?
    /// If true app has a .pkg installer
    let pkgInstaller: Bool
    
    /// Cask progress state when installing, updating or uninstalling
    public enum ProgressState: Equatable, Hashable {
        case idle
        case busy(withTask: String)
        case downloading(percent: Double)
        case success
        case failed(output: String)
    }

    @MainActor
    @Published var isInstalled: Bool = false

    @MainActor
    @Published var isOutdated: Bool = false

    /// Progress state of the cask when installing, updating or uninstalling
    @MainActor
    @Published public var progressState: ProgressState = .idle
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: Cask.self)
    )
    
    init(from decoder: Decoder) throws {
        let rawData = try? CaskDTO(from: decoder)

        let homepage: String = rawData?.homepage ?? "https://brew.sh/"

        self.id = rawData?.token ?? "N/A"
        self.name = rawData?.nameArray[0] ?? "N/A"
        self.description = rawData?.desc ?? "N/A"
        self.homepageURL = URL(string: homepage)
        self.caveats = rawData?.caveats
        self.pkgInstaller = rawData?.url.hasSuffix("pkg") ?? false
    }
    
    init() {
        self.id = "test"
        self.name = "Test app"
        self.description = "An application to test this application"
        self.homepageURL = URL(string: "https://aerolite.dev/")
        self.caveats = nil
        self.pkgInstaller = false
    }
    
    /// Installs the cask
    ///
    /// - Parameters:
    ///   - force: If `true` install will be run with the `--force` flag
    /// - Returns: `Void`
    func install(caskData: CaskData, force: Bool = false) async {
        defer {
            resetProgressState(caskData: caskData)
        }
        
        Self.logger.info("Cask \"\(self.id)\" installation started")

        // Appdir argument
        let appdirOn = UserDefaults.standard.bool(forKey: Preferences.appdirOn.rawValue)
        let appdirPath = UserDefaults.standard.string(forKey: Preferences.appdirPath.rawValue)
        let appdirArgument = "--appdir=\"\(appdirPath ?? "/Applications")\""

        // Install command
        let command = "\(BrewPaths.currentBrewExecutable) install --cask \(force ? "--force" : "") \(self.id) \(appdirOn ? appdirArgument : "")"

        // Setup progress
        await MainActor.run {
            self.progressState = .busy(withTask: "")
            caskData.busyCasks.insert(self)
        }

        var completeOutput = ""

        // Run install command and stream output
        do {
            for try await line in Shell.stream(command) {
                completeOutput += line

                await MainActor.run {
                    self.progressState = self.parseBrewInstall(output: line)
                }
            }
        } catch {
            Self.logger.error("Failed to install cask \(self.id).")

            // Capture output
            let output = completeOutput

            await MainActor.run {
                progressState = .failed(output: output)
                caskData.busyCasks.remove(self)
            }

            sendNotification(title: String(localized: "Failed to download \(self.name)"), reason: .failure)
        }

        Self.logger.info("Successfully installed cask \(self.id)")

        sendNotification(title: String(localized: "\(self.name) successfully installed!"), reason: .success)

        await MainActor.run {
            progressState = .success
            self.isInstalled = true
        }

        // Show success for 2 seconds
        try? await Task.sleep(for: .seconds(2))
    }
    
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

    /// Uninstalls the cask
    /// - Parameters:
    ///     - caskData: ``CaskData`` object
    ///     - zap: If true the app will be uninstalled completely using the brew --zap flag
    func uninstall(caskData: CaskData, zap: Bool = false) async {
        defer {
            resetProgressState(caskData: caskData)
        }
        
        _ = await MainActor.run {
            caskData.busyCasks.insert(self)
        }
        
        let arguments: [String] = if zap { ["--zap", self.id] } else { [self.id] }
        
        await runBrewCommand(
            command: "uninstall",
            arguments: arguments,
            taskDescription: "Uninstalling",
            notificationSuccess: String(localized:"\(self.name) successfully uninstalled"),
            notificationFailure: "Failed to uninstall \(self.name)",
            onSuccess: { self.isInstalled = false }
        )
    }
    
    /// Updates the cask
    /// - Returns: Bool - Whether the task has failed or not
    func update(caskData: CaskData) async {
        defer {
            resetProgressState(caskData: caskData)
        }
        
        _ = await MainActor.run {
            caskData.busyCasks.insert(self)
        }
        
        await runBrewCommand(
            command: "upgrade",
            arguments: [self.id],
            taskDescription: "Updating",
            notificationSuccess: String(localized: "\(self.name) successfully updated"),
            notificationFailure: String(localized: "Failed to update \(self.name)"),
            onSuccess: {
                self.isOutdated = false
                caskData.outdatedCasks.remove(self)
        })
    }
    
    /// Updates the cask
    /// - Returns: Bool - Whether the task has failed or not
    func reinstall(caskData: CaskData) async {
        defer {
            resetProgressState(caskData: caskData)
        }
        
        _ = await MainActor.run {
            caskData.busyCasks.insert(self)
        }
        
        await runBrewCommand(
            command: "reinstall",
            arguments: [self.id],
            taskDescription: "Reinstalling",
            notificationSuccess: String(localized: "\(self.name) successfully reinstalled"),
            notificationFailure: String(localized:"Failed to reinstall \(self.name)"),
            onSuccess: {
                caskData.busyCasks.remove(self)
            }
        )
    }
    
    /// Runs a shell command with the currently selected brew path
    ///
    /// - Parameters:
    ///   - command: Brew command to be run
    ///   - arguments: Command arguments
    ///   - taskDesctiption: Description showed under the progress indicator in the UI
    ///   - notificationSuccess: Notification message if succeeds
    ///   - notificationFailure: Notification message if fails
    ///   - onSuccess: Closure run if task succeeds
    /// - Returns: Bool - Whether the the task has failed or not
    private func runBrewCommand(
        command: String,
        arguments: [String],
        taskDescription: String,
        notificationSuccess: String,
        notificationFailure: String,
        onSuccess: (@MainActor () -> Void)? = nil
    ) async {
        await MainActor.run {
            let localizedTaskDescription = String.LocalizationValue(stringLiteral: taskDescription)
            self.progressState = .busy(withTask: String(localized: localizedTaskDescription))
        }

        let command = "HOMEBREW_NO_AUTO_UPDATE=1 \(BrewPaths.currentBrewExecutable) \(command) --cask \(arguments.joined(separator: " "))"

        var output: String = ""

        do {
            output = try await Shell.runAsync(command)
        } catch {
            Self.logger.error("Failed to run brew command: \(error.localizedDescription)")

            sendNotification(title: notificationFailure, reason: .failure)

            await MainActor.run { self.progressState = .failed(output: error.localizedDescription) }
        }

        if let onSuccess {
            await MainActor.run {
                onSuccess()
            }
        }
        
        // Log and Notify
        Self.logger.notice("Successfully run brew command \"\(command)\" with arguments \"\(arguments)\", output: \(output)")

        sendNotification(title: notificationSuccess, reason: .success)

        // Show success for 2 seconds
        await MainActor.run { self.progressState = .success }
        try? await Task.sleep(for: .seconds(2))
    }

    public func launchApp() throws {
        let appPath: String
        
        if self.pkgInstaller {
            // Open PKG type app
            var applicationsDirectory = "/Applications"
            
            // Appdir
            if UserDefaults.standard.bool(forKey: Preferences.appdirOn.rawValue) {
                applicationsDirectory = UserDefaults.standard.string(forKey: Preferences.appdirPath.rawValue) ?? "/Applications"
                
                // Remove trailing "/"
                if applicationsDirectory.hasSuffix("/") {
                    applicationsDirectory.removeLast()
                }
            }
            
            appPath = "\"\(applicationsDirectory)/\(self.name).app\""
        } else {
            // Open normal app
            let brewDirectory = BrewPaths.currentBrewDirectory
            
            appPath = "\(brewDirectory.replacingOccurrences(of: " ", with: "\\ ") )/Caskroom/\(self.id)/*/*.app"
        }

        try Shell.run("open \(appPath)")
    }
    
    /// Resets progress state and removes self from ``CaskData.busyCasks``
    private func resetProgressState(caskData: CaskData) {
        Task {
            await MainActor.run {
                // Only reset state if it's not failed
                if case .failed(_) = self.progressState {
                } else {
                    self.progressState = .idle
                    caskData.busyCasks.remove(self)
                    
                    // Filter busy casks to make sure
                    caskData.filterBusyCasks()
                }
            }
        }
    }
    
    static func == (lhs: Cask, rhs: Cask) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
