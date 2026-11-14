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
    @State private var retryCount = 0

    private enum LoadState {
        case loading
        case loaded(CaskAdditionalInfo)
        case failed(String)
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
                        if cask.isLocallyInstalled {
                            Label("Installed", systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
            }

            switch loadState {
            case .loading:
                Section {
                    ProgressView("Loading app details...")
                }
            case .loaded(let info):
                informationSections(info)
            case .failed(let message):
                Section {
                    Label("Couldn't load app details", systemImage: "exclamationmark.triangle")
                    Text(message)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Try Again") {
                        retryCount += 1
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(cask.name)
        .task(id: [cask.fullToken, String(retryCount)]) {
            await loadInfo()
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

    @ViewBuilder
    private func informationSections(_ info: CaskAdditionalInfo) -> some View {
        Section {
            if let version = info.version {
                infoRow(cask.isManagementProtected ? "Homebrew Version" : "Available Version", version)
            }
            infoRow("Token", info.token)
            infoRow("Full Token", info.full_token)
            infoRow("Tap", info.tap)

            downloadSizeRow

            linkRow("Homepage", url: info.homepage)

            linkRow("Download URL", url: info.url)
        } header: {
            Label("General", systemImage: "info.circle")
        }

        Section {
            infoRow("Installed Version", cask.isManagementProtected ? String(localized: "Unknown") : info.installed ?? (
                cask.isLocallyInstalled
                    ? String(localized: "Unknown")
                    : String(localized: "Not installed", comment: "Cask info: app is not installed")
            ))
            if let protection = cask.protectedAppInstallation {
                let sources = ProtectedAppInstallation.Source.allCases.filter { protection.appURLs[$0] != nil }
                infoRow("Detected Management Sources", sources.map(\.name).joined(separator: ", "))
                infoRow("Tracked by Homebrew", yesNo(cask.isInstalled))
                infoRow("App Location", protection.url.path)
                let overridden = sources.filter { cask.managementSourceOverrides.contains($0) }
                if !overridden.isEmpty {
                    infoRow("Source Overrides", overridden.map(\.name).joined(separator: ", "))
                }
            } else if let appURL = cask.externalAppURL, cask.isInstalledExternally {
                infoRow("Management", String(localized: "Not managed by Homebrew"))
                infoRow("App Location", appURL.path)
            }

            if !cask.isManagementProtected {
                infoRow("Bundle Version", info.bundle_version ?? "—")

                if let installedTime = info.installed_time {
                    infoRow("Installation Date", dateFormatter.string(from: installedTime))
                }

                if let outdated = info.outdated {
                    infoRow("Outdated", yesNo(outdated))
                }

                infoRow("Auto Updates", yesNo(info.auto_updates ?? false))
            }
        } header: {
            Label("Installation", systemImage: "arrow.down.circle")
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
        guard case .loaded(let info) = loadState else { return nil }
        return info.url
    }

    private func loadInfo() async {
        loadState = .loading
        do {
            let info = try await caskManager.getAdditionalInfoForCask(cask)
            try Task.checkCancellation()
            loadState = .loaded(info)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            Self.logger.error("Failed to load \(cask.fullToken): \(error.localizedDescription)")
            loadState = .failed(error.localizedDescription)
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
