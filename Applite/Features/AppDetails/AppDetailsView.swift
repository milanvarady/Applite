//
//  AppDetailsView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import SwiftUI
import OSLog

struct AppDetailsView: View {
    let cask: CaskViewModel
    @Environment(CaskManager.self) private var caskManager

    @State private var loadState: LoadState = .loading
    @State private var homebrewRetryCount = 0
    @State private var localRetryCount = 0
    @State private var localState: LocalState = .loading

    private enum LoadState {
        case loading
        case loaded([String], CaskAdditionalInfo)
        case failed([String], String)
    }

    private enum LocalState {
        case loading
        case loaded([String], InstalledAppMetadata)
        case unavailable
        case failed([String], String)
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Applite",
        category: "AppDetailsView"
    )

    /// Filled in by a live request to the download host; Homebrew itself has no size to give.
    @State private var downloadSize: DownloadSize = .loading

    private enum DownloadSize {
        case loading
        case known(Int64)
        /// The host wouldn't say — a mirror selector, or an archive built on the fly.
        case unavailable
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    if let iconURL = cask.iconURL {
                        AppIconView(
                            iconURL: iconURL,
                            name: cask.name,
                            cacheKey: cask.iconCacheKey,
                            homepageURL: cask.homepage,
                            size: 72
                        )
                        .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(cask.name)
                            .font(.title.bold())
                            .textSelection(.enabled)
                        Text(cask.descriptionText)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let homepage = cask.homepage {
                            Link("Developer Website", destination: homepage)
                        }
                        if cask.isLocallyInstalled {
                            Label("Installed", systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let source = cask.installedManagementSourceName {
                                Text("Tracked by: \(source)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
            }

            installationSection
            localInformationSection

            switch loadState {
            case .loading:
                Section {
                    ProgressView("Loading Homebrew details...")
                }
            case .loaded(let key, let info):
                if key == infoKey { informationSections(info) }
            case .failed(let key, let message):
                if key == infoKey {
                    Section {
                        Label("Couldn't load Homebrew details", systemImage: "exclamationmark.triangle")
                        Text(message)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Try Again") {
                            homebrewRetryCount += 1
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(cask.name)
        .task(id: infoKey) {
            await loadInfo()
        }
        .task(id: localKey) {
            await loadLocalInfo()
        }
        .task(id: downloadURL) {
            downloadSize = .loading
            guard let downloadURL else { return }
            let bytes = await DownloadSizeProbe.size(of: downloadURL)
            guard !Task.isCancelled else { return }
            if let bytes {
                downloadSize = .known(bytes)
            } else {
                downloadSize = .unavailable
            }
        }
    }

    private var infoKey: [String] {
        [cask.fullToken, String(cask.isInstalled), String(cask.metadataRevision), String(homebrewRetryCount)]
    }

    private var localKey: [String] {
        [cask.fullToken, String(cask.isInstalled), cask.externalAppURL?.path ?? "",
         cask.protectedAppInstallation?.url.path ?? "", cask.installedBundleURL?.path ?? "",
         String(cask.metadataRevision), String(localRetryCount)]
    }

    private var brewInfo: CaskAdditionalInfo? {
        guard case .loaded(let key, let info) = loadState, key == infoKey else { return nil }
        return info
    }

    private var localInfo: InstalledAppMetadata? {
        guard case .loaded(let key, let info) = localState, key == localKey else { return nil }
        return info
    }

    @ViewBuilder
    private var installationSection: some View {
        Section {
            let version = InstalledAppDetails.version(
                isLocallyInstalled: cask.isLocallyInstalled, isHomebrewManaged: cask.isInstalled,
                hasOtherOwner: cask.protectedAppInstallation != nil, metadata: localInfo, brew: brewInfo
            )
            switch version {
            case .known(let value):
                if localInfo?.version == value {
                    infoRow("Installed Version", value)
                } else {
                    infoRow("Installed Version (Homebrew)", value)
                }
            case .unknown: infoRow("Installed Version", String(localized: "Unknown"))
            case .notInstalled: infoRow("Installed Version", String(localized: "Not installed"))
            }
            if let build = localInfo?.build {
                infoRow("Bundle Version", build)
            }
            if let source = cask.installedManagementSourceName {
                infoRow("Tracked by", source)
            }
            if let protection = cask.protectedAppInstallation {
                let sources = ProtectedAppInstallation.Source.allCases.filter { protection.appURLs[$0] != nil }
                infoRow("Detected Management Sources", sources.map(\.name).joined(separator: ", "))
                infoRow("Tracked by Homebrew", yesNo(cask.isInstalled))
                infoRow("App Location", protection.url.path)
                let overridden = sources.filter { cask.managementSourceOverrides.contains($0) }
                if !overridden.isEmpty {
                    infoRow("Source Overrides", overridden.map(\.name).joined(separator: ", "))
                }
            } else if cask.isInstalledExternally {
                infoRow("Management", String(localized: "Not managed by Homebrew"))
                if let url = cask.externalAppURL { infoRow("App Location", url.path) }
            } else if let url = localInfo?.appURL {
                infoRow("App Location", url.path)
            }

            if cask.isLocallyInstalled {
                switch InstalledAppDetails.updateStatus(
                    isLocallyInstalled: true, isHomebrewManaged: cask.isInstalled,
                    hasOtherOwner: cask.protectedAppInstallation != nil, brew: brewInfo
                ) {
                case .outdated: infoRow("Outdated", yesNo(true))
                case .current: infoRow("Outdated", yesNo(false))
                case .unknown: infoRow("Outdated", String(localized: "Unknown"))
                case .notApplicable: EmptyView()
                }
            }
            if cask.isInstalled, cask.protectedAppInstallation == nil, let date = brewInfo?.installed_time {
                infoRow("Homebrew Installation Date", dateFormatter.string(from: date))
            }
        } header: {
            Label("Installation", systemImage: "arrow.down.circle")
        }
    }

    @ViewBuilder
    private var localInformationSection: some View {
        if cask.isLocallyInstalled {
            Section {
                switch localState {
                case .loading:
                    ProgressView("Reading installed app information...")
                case .unavailable:
                    Text("The installed app bundle could not be located.")
                        .foregroundStyle(.secondary)
                case .failed(let key, let message):
                    if key == localKey {
                        Label("Couldn't read installed app information", systemImage: "exclamationmark.triangle")
                        Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Try Again") { localRetryCount += 1 }
                    }
                case .loaded(let key, let info):
                    if key == localKey {
                        if let name = info.displayName, name != cask.name { infoRow("Bundle Name", name) }
                        if let identifier = info.bundleIdentifier { infoRow("Bundle Identifier", identifier) }
                        if let description = info.bundleInformation { infoRow("Bundle Information", description) }
                        if let copyright = info.copyrightNotice { infoRow("Copyright", copyright) }
                        if let minimum = info.minimumSystemVersion { infoRow("Minimum macOS Version", minimum) }
                        if let category = info.category {
                            let prefix = "public.app-category."
                            let name = category.hasPrefix(prefix) ? String(category.dropFirst(prefix.count)) : category
                            infoRow("Declared Category", name.replacingOccurrences(of: "-", with: " ").localizedCapitalized)
                        }
                        if !info.localizations.isEmpty {
                            let languages = info.localizations.map {
                                Locale.current.localizedString(forIdentifier: $0) ?? $0
                            }
                            infoRow("Languages", languages.joined(separator: ", "))
                        }
                        if let region = info.developmentRegion {
                            infoRow("Development Language", Locale.current.localizedString(forIdentifier: region) ?? region)
                        }
                        if let error = info.localizationError {
                            infoRow("Some Languages Unavailable", error)
                        }
                        if let identity = info.signingIdentity {
                            infoRow("Signing Identity (unverified)", identity)
                        } else if let error = info.signingError {
                            infoRow("Signing Identity", String(localized: "Unavailable (OSStatus \(error))"))
                        }
                        Text("Information is read from the installed app. Its signing identity is not verified.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Installed App Information", systemImage: "app.badge")
            }
        }
    }

    @ViewBuilder
    private func informationSections(_ info: CaskAdditionalInfo) -> some View {
        Section {
            if let version = info.version {
                infoRow("Homebrew Available Version", version)
            }
            infoRow("Token", info.token)
            infoRow("Full Token", info.full_token)
            infoRow("Tap", info.tap)

            downloadSizeRow

            if cask.homepage == nil {
                linkRow("Homepage", url: info.homepage)
            }
            linkRow("Download URL", url: info.url)
            if let autoUpdates = info.auto_updates {
                infoRow("Homebrew Cask Auto-Update Flag", yesNo(autoUpdates))
            }
        } header: {
            Label("Homebrew Catalog", systemImage: "info.circle")
        }

        if info.deprecated {
            Section {
                if let date = info.deprecation_date {
                    infoRow("Date", date)
                }
                if let reason = info.deprecation_reason {
                    infoRow("Reason", reason)
                }
                if let replacement = info.deprecation_replacement {
                    infoRow("Replacement", replacement)
                }
            } header: {
                Label("Deprecated", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }

        if info.disabled {
            Section {
                if let date = info.disable_date {
                    infoRow("Date", date)
                }
                if let reason = info.disable_reason {
                    infoRow("Reason", reason)
                }
                if let replacement = info.disable_replacement {
                    infoRow("Replacement", replacement)
                }
            } header: {
                Label("Disabled", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var downloadURL: URL? {
        brewInfo?.url
    }

    private func loadLocalInfo() async {
        guard cask.isLocallyInstalled else {
            localState = .unavailable
            return
        }
        localState = .loading
        let key = localKey
        let knownURL = cask.protectedAppInstallation?.url ?? cask.externalAppURL ?? cask.installedBundleURL
        let token = cask.token
        let name = cask.name
        do {
            let info = try await Task.detached { () throws -> InstalledAppMetadata? in
                guard let url = knownURL ?? InstalledAppLocator.appURL(token: token, displayName: name) else {
                    return nil
                }
                return try InstalledAppMetadata.read(at: url)
            }.value
            try Task.checkCancellation()
            guard key == localKey else { return }
            localState = info.map { .loaded(key, $0) } ?? .unavailable
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, key == localKey else { return }
            Self.logger.error("Failed to read installed app information for \(cask.fullToken): \(error.localizedDescription)")
            localState = .failed(key, error.localizedDescription)
        }
    }

    private func loadInfo() async {
        loadState = .loading
        let key = infoKey
        do {
            let info = try await caskManager.getAdditionalInfoForCask(cask)
            try Task.checkCancellation()
            guard key == infoKey else { return }
            loadState = .loaded(key, info)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, key == infoKey else { return }
            Self.logger.error("Failed to load \(cask.fullToken): \(error.localizedDescription)")
            loadState = .failed(key, error.localizedDescription)
        }
    }

    /// The size of the artifact this Mac would actually download — `info.url` comes from
    /// `brew info`, which has already resolved the cask's `variations` for the running macOS
    /// version and architecture. Absent until the probe answers, and dropped entirely if it
    /// can't, so the form never shows a size that might be wrong.
    @ViewBuilder
    private var downloadSizeRow: some View {
        switch downloadSize {
        case .loading:
            LabeledContent("Download Size") {
                ProgressView()
                    .controlSize(.small)
            }
        case .known(let bytes):
            infoRow("Download Size", bytes.formatted(.byteCount(style: .file)))
        case .unavailable:
            EmptyView()
        }
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .textSelection(.enabled)
        }
    }

    /// A row for long URLs: the label sits on top with the link wrapping
    /// full-width on the line below, left-aligned.
    private func linkRow(_ title: LocalizedStringKey, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)

            Link(url.absoluteString, destination: url)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func yesNo(_ value: Bool) -> String {
        value
            ? String(localized: "Yes", comment: "Cask info boolean value")
            : String(localized: "No", comment: "Cask info boolean value")
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    NavigationStack {
        AppDetailsView(cask: .dummy)
            .environment(CaskManager())
    }
}
