//
//  ImportAppsView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI
import OSLog

struct ImportAppsView: View {
    @Environment(CaskManager.self) var caskManager

    @State private var showFileImporter = false
    /// Drives the selection sheet. Using `.sheet(item:)` (not a separate bool + array) makes the
    /// sheet's content a pure function of the resolved casks, so it can never present with a stale
    /// empty list — the race that showed "0 casks" on the first import attempt.
    @State private var importSelection: ImportSelection?
    @State private var importSuccessful = false
    @State private var importedCount = 0
    @State private var alert = AlertManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppMigration.ImportAppsView")

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("Import", comment: "App Migration import card title")
                .font(.appliteSmallTitle)

            Text("Install apps from a file exported by Applite — or any Brewfile.",
                 comment: "App Migration import card description")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button {
                showFileImporter = true
            } label: {
                Text("Import Apps…", comment: "App Migration import button")
            }
            .cardActionPill()

            Group {
                if importSuccessful {
                    Label("Installing \(importedCount) apps…", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .font(.callout)
            .frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .alertManager(alert)
        // `.item` allows any file so extensionless Brewfiles are selectable, not greyed out.
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                gatherCasks(from: url)
            case .failure(let error):
                alert.show(error: error, title: "Failed to import")
            }
        }
        .sheet(item: $importSelection) { selection in
            CaskSelectionSheet(
                title: "Select Apps to Import",
                confirmLabel: "Install",
                note: selection.notFoundCount > 0 ? "\(selection.notFoundCount) apps could not be found" : nil,
                casks: selection.casks
            ) { selected in
                caskManager.installAll(selected)
                withAnimation {
                    importedCount = selected.count
                    importSuccessful = true
                }
            }
        }
    }

    /// Parses the file, resolves its tokens against the DB, then shows the selection sheet.
    private func gatherCasks(from url: URL) {
        let tokens: Set<CaskId>
        do {
            tokens = try AppMigration.readCaskFile(url: url)
        } catch {
            logger.error("Failed to import file: \(url.path(percentEncoded: false))")
            alert.show(title: "Imported file contains no valid apps", message: "Check if file contains valid cask tokens")
            return
        }

        Task {
            // Resolve against the DB so casks the user has never opened still install.
            let resolvedAll = (try? await caskManager.resolveViewModels(forTokens: tokens)) ?? []

            // Count not-found from the full resolved set so an Applite entry isn't mislabeled as
            // missing — it resolved, we just don't offer it (the import runs from a live Applite,
            // so it's always already installed).
            let matched = Set(resolvedAll.flatMap { [$0.token, $0.fullToken] })
            let resolved = resolvedAll.filter { $0.token != "applite" }.sorted()

            guard !resolved.isEmpty else {
                logger.notice("Imported file contains no valid apps: \(url.path(percentEncoded: false))")
                alert.show(title: "Imported file contains no valid apps", message: "Check if file contains valid cask tokens")
                return
            }

            importSelection = ImportSelection(
                casks: resolved,
                notFoundCount: tokens.subtracting(matched).count
            )
        }
    }
}

/// Identifiable payload for the import selection sheet.
private struct ImportSelection: Identifiable {
    let id = UUID()
    let casks: [CaskViewModel]
    let notFoundCount: Int
}
