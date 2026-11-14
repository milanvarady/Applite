import Foundation

struct UpdateVersions {
    let installed: String?
    let available: String?

    static func resolve(
        isLocallyInstalled: Bool, isHomebrewManaged: Bool, hasOtherOwner: Bool,
        metadata: InstalledAppMetadata?, brew: CaskAdditionalInfo?
    ) -> Self {
        let version = InstalledAppDetails.version(
            isLocallyInstalled: isLocallyInstalled, isHomebrewManaged: isHomebrewManaged,
            hasOtherOwner: hasOtherOwner, metadata: metadata, brew: brew
        )
        let installed: String?
        if case .known(let value) = version { installed = value } else { installed = nil }
        let raw = brew?.version?.trimmingCharacters(in: .whitespacesAndNewlines)
        let available = raw.flatMap {
            $0.isEmpty || ["latest", "unknown", "n/a"].contains($0.lowercased()) ? nil : $0
        }
        return Self(installed: installed, available: available)
    }
}

enum UpdateVersionState {
    case loading
    case loaded(UpdateVersions, error: String?)
}
