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

    @State var showFileImporter = false
    @State var importSuccessful = false
    @State var importedCount = 0
    @State var alert = AlertManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppMigration.ImportAppsView")

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Import", comment: "App Migration import card title")
                .font(.appliteSmallTitle)

            Text(
                "**Tip:** You can also import apps from a Brewfile. However, only casks will be installed, other items like formulae and taps will be skipped.",
                comment: "App Migration import card tip"
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                showFileImporter = true
            } label: {
                Label("Import Apps", systemImage: "square.and.arrow.down")
            }
            .controlSize(.large)

            if importSuccessful {
                Label("Installing \(importedCount) apps…", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity)
        .alertManager(alert)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .data]) { result in
            switch result {
            case .success(let url):
                installCasks(from: url)
            case .failure(let error):
                alert.show(error: error, title: "Failed to import")
            }
        }
    }

    private func installCasks(from url: URL) {
        let caskIds: Set<CaskId>
        do {
            caskIds = try AppMigration.readCaskFile(url: url)
        } catch {
            logger.error("Failed to import file: \(url.path(percentEncoded: false))")
            alert.show(title: "Imported file contains no valid apps", message: "Check if file contains valid cask tokens")
            return
        }

        Task {
            // Resolve against the DB so casks the user has never opened still install.
            let casksToInstall = (try? await caskManager.resolveViewModels(forTokens: caskIds)) ?? []

            guard !casksToInstall.isEmpty else {
                logger.notice("Imported file contains no valid apps: \(url.path(percentEncoded: false))")
                alert.show(title: "Imported file contains no valid apps", message: "Check if file contains valid cask tokens")
                return
            }

            caskManager.installAll(casksToInstall)

            withAnimation {
                importedCount = casksToInstall.count
                importSuccessful = true
            }
        }
    }
}
