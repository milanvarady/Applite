import Foundation

enum CaskInstallationState {
    case installed
    case externalInstalled
    case notInstalled

    init(isManaged: Bool, externalAppURL: URL?) {
        self = isManaged ? .installed : (externalAppURL == nil ? .notInstalled : .externalInstalled)
    }
}
