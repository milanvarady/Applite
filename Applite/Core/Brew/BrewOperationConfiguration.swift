import Foundation

struct BrewAdoptionConsent {
    let validate: @MainActor () throws -> Void
}

struct BrewOperationConfiguration: Equatable, Sendable {
    let executable: URL
    let appdirArguments: [String]
    let applicationDirectories: [URL]
    let caskroom: URL?

    nonisolated static var current: Self {
        let defaults = UserDefaults.standard
        let appdirArguments = defaults.value(for: Preferences.appdirOn)
            ? ["--appdir=\(defaults.value(for: Preferences.appdirPath))"] : []
        return Self(
            executable: BrewPaths.currentBrewExecutable,
            appdirArguments: appdirArguments,
            applicationDirectories: InstalledAppLocator.applicationDirectories,
            caskroom: nil
        )
    }

    func matchesSettings(of other: Self) -> Bool {
        executable == other.executable && appdirArguments == other.appdirArguments
            && applicationDirectories == other.applicationDirectories
    }

    func validateCurrent() throws {
        guard matchesSettings(of: .current) else { throw CaskAdoptionError.configurationChanged }
    }

    func resolvingCaskroom() async throws -> Self {
        try Task.checkCancellation()
        try validateCurrent()
        if caskroom != nil { return self }
        let output = try await Shell.run(executable, ["--caskroom"], timeout: .seconds(30))
        try Task.checkCancellation()
        try validateCurrent()
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (path as NSString).isAbsolutePath, !path.contains("\n"), !path.contains("\r") else {
            throw CaskAdoptionError.installationTargetsUnavailable
        }
        return Self(
            executable: executable, appdirArguments: appdirArguments,
            applicationDirectories: applicationDirectories,
            caskroom: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        )
    }
}
