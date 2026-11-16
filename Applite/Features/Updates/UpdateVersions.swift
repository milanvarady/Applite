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

struct UpdateVersionCache {
    private struct Entry {
        let key: [String]
        var state: UpdateVersionState
    }

    private var entries: [String: Entry] = [:]

    mutating func reconcile(keys: [String: [String]]) -> [String] {
        entries = entries.filter { keys[$0.key] != nil }
        var pending: [String] = []
        for (identity, key) in keys {
            if let entry = entries[identity], entry.key == key {
                if case .loading = entry.state { pending.append(identity) }
            } else {
                entries[identity] = Entry(key: key, state: .loading)
                pending.append(identity)
            }
        }
        return pending
    }

    func state(for identity: String, key: [String]) -> UpdateVersionState {
        guard let entry = entries[identity], entry.key == key else { return .loading }
        return entry.state
    }

    mutating func store(_ state: UpdateVersionState, for identity: String, key: [String]) {
        guard entries[identity]?.key == key else { return }
        entries[identity]?.state = state
    }

    mutating func retry(_ identity: String) {
        entries.removeValue(forKey: identity)
    }
}
