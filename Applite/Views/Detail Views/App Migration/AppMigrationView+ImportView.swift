//
//  AppMigrationView+ImportView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI
import OSLog

extension AppMigrationView {
    struct ImportView: View {
        @EnvironmentObject var caskManager: CaskManager

        @State var showFileImporter = false
        @State var importSuccessful = false
        @StateObject var alert = AlertManager()

        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppMigrationView.ExportView")

        var body: some View {
            VStack(alignment: .leading) {
                Text("Import", comment: "App Migration import card title")
                    .font(.appliteSmallTitle)

                HStack {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import Apps", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.large)

                    if importSuccessful {
                        Image(systemName: "square.and.arrow.down.badge.checkmark")
                            .foregroundStyle(.green)
                            .imageScale(.large)
                    }
                }
                .padding(.bottom, 10)

                Text(
                    "**Tip:** You can also import apps from a Brewfile. However, only casks will be installed, other items like formulae and taps will be skipped.",
                    comment: "App Migration import card tip"
                )

                Spacer()
            }
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
            var caskIds: [CaskId] = []

            do {
                caskIds = try AppMigration.readCaskFile(url: url)
            } catch {
                logger.error("Failed to import file: \(url.path(percentEncoded: false))")
            }

            let casksToInstall = caskIds.compactMap {
                caskManager.casks[$0]
            }

            guard !casksToInstall.isEmpty else {
                logger.notice("Imported file contains no valid apps: \(url.path(percentEncoded: false))")
                alert.show(title: "Imported file contains no valid apps", message: "Check if file contains valid cask tokens")
                return
            }

            caskManager.installAll(casksToInstall)

            withAnimation {
                importSuccessful = true
            }
        }
    }
}
