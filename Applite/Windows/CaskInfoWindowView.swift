//
//  CaskInfoWindowView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import SwiftUI

struct CaskInfoWindowView: View {
    let info: CaskAdditionalInfo

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
                infoRow("Installed Version", info.installed ?? String(localized: "Not installed", comment: "Cask info: app is not installed"))
                infoRow("Bundle Version", info.bundle_version ?? "—")

                if let installedTime = info.installed_time {
                    infoRow("Installation Date", dateFormatter.string(from: installedTime))
                }

                if let outdated = info.outdated {
                    infoRow("Outdated", yesNo(outdated))
                }

                infoRow("Auto Updates", yesNo(info.auto_updates ?? false))
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
        .formStyle(.grouped)
        .navigationTitle(info.token)
        .frame(width: 460, height: 520)
        .task(id: info.url) {
            downloadSize = .loading

            if let bytes = await DownloadSizeProbe.size(of: info.url) {
                downloadSize = .known(bytes)
            } else {
                downloadSize = .unavailable
            }
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
    CaskInfoWindowView(info: .dummy)
}
