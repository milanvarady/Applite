import Foundation

struct BrewAdoptionConsent {
    let validate: @MainActor () throws -> Void
}

struct BrewOperationConfiguration: Equatable, Sendable {
    let executable: URL
    let appdirArguments: [String]
    let applicationDirectories: [URL]

    nonisolated static var current: Self {
        let defaults = UserDefaults.standard
        let appdirArguments = defaults.value(for: Preferences.appdirOn)
            ? ["--appdir=\(defaults.value(for: Preferences.appdirPath))"] : []
        return Self(
            executable: BrewPaths.currentBrewExecutable,
            appdirArguments: appdirArguments,
            applicationDirectories: InstalledAppLocator.applicationDirectories
        )
    }

    func validateCurrent() throws {
        guard self == .current else { throw CaskAdoptionError.configurationChanged }
    }
}
