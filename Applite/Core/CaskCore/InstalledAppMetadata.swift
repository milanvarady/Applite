import Foundation
import Security

struct InstalledAppMetadata: Sendable {
    let appURL: URL
    let version: String?
    let build: String?
    let displayName: String?
    let bundleIdentifier: String?
    let bundleInformation: String?
    let copyrightNotice: String?
    let developmentRegion: String?
    let minimumSystemVersion: String?
    let category: String?
    let localizations: [String]
    let localizationError: String?
    let signingIdentity: String?
    let signingError: OSStatus?

    nonisolated static func read(at appURL: URL) throws -> Self {
        let data = try Data(contentsOf: appURL.appendingPathComponent("Contents/Info.plist"))
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let info = propertyList as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        func text(_ key: String) -> String? {
            guard let value = info[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var languages = Set((info["CFBundleLocalizations"] as? [String] ?? []).filter { !$0.isEmpty })
        var localizationError: String?
        let resources = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: resources, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
            for entry in entries where entry.pathExtension == "lproj" {
                languages.insert(entry.deletingPathExtension().lastPathComponent)
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // Bundles need not contain a Resources directory.
        } catch {
            localizationError = error.localizedDescription
        }
        languages.remove("Base")

        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &code)
        var signingIdentity: String?
        var signingError: OSStatus?
        if createStatus == errSecSuccess, let code {
            var signingInfo: CFDictionary?
            let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo)
            if status == errSecSuccess, let values = signingInfo as? [String: Any] {
                if let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate],
                   let certificate = certificates.first {
                    signingIdentity = SecCertificateCopySubjectSummary(certificate) as String?
                }
            } else if status != errSecCSUnsigned {
                signingError = status
            }
        } else if createStatus != errSecCSUnsigned {
            signingError = createStatus
        }

        return Self(
            appURL: appURL, version: text("CFBundleShortVersionString"), build: text("CFBundleVersion"),
            displayName: text("CFBundleDisplayName") ?? text("CFBundleName"),
            bundleIdentifier: text("CFBundleIdentifier"), bundleInformation: text("CFBundleGetInfoString"),
            copyrightNotice: text("NSHumanReadableCopyright"), developmentRegion: text("CFBundleDevelopmentRegion"),
            minimumSystemVersion: text("LSMinimumSystemVersion"),
            category: text("LSApplicationCategoryType"), localizations: languages.sorted(),
            localizationError: localizationError,
            signingIdentity: signingIdentity, signingError: signingError
        )
    }
}

enum InstalledAppDetails {
    enum Version: Equatable {
        case notInstalled
        case unknown
        case known(String)
    }

    enum UpdateStatus: Equatable {
        case notApplicable
        case unknown
        case outdated
        case current
    }

    private static func concreteVersion(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !["latest", "unknown", "n/a"].contains(value.lowercased()) else { return nil }
        return value
    }

    static func version(
        isLocallyInstalled: Bool, isHomebrewManaged: Bool, hasOtherOwner: Bool,
        metadata: InstalledAppMetadata?, brew: CaskAdditionalInfo?
    ) -> Version {
        guard isLocallyInstalled else { return .notInstalled }
        if let version = concreteVersion(metadata?.version) { return .known(version) }
        if isHomebrewManaged, !hasOtherOwner, let version = concreteVersion(brew?.installed) {
            return .known(version)
        }
        return .unknown
    }

    static func updateStatus(
        isLocallyInstalled: Bool, isHomebrewManaged: Bool, hasOtherOwner: Bool,
        metadata: InstalledAppMetadata?, brew: CaskAdditionalInfo?
    ) -> UpdateStatus {
        guard isLocallyInstalled else { return .notApplicable }
        guard isHomebrewManaged, !hasOtherOwner,
              let installed = concreteVersion(brew?.installed),
              let localVersion = concreteVersion(metadata?.version),
              concreteVersion(brew?.version) != nil,
              brew?.auto_updates != true,
              let outdated = brew?.outdated else { return .unknown }
        let components = installed.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...2).contains(components.count), String(components[0]) == localVersion else { return .unknown }
        if components.count == 2 {
            guard let localBuild = concreteVersion(metadata?.build), String(components[1]) == localBuild else {
                return .unknown
            }
        }
        return outdated ? .outdated : .current
    }
}
