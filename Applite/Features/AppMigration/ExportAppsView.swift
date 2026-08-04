//
//  ExportAppsView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI
import OSLog

struct ExportAppsView: View {
    @Environment(CaskManager.self) private var caskManager

    @State private var showSelectionSheet = false
    @State private var showFileExporter = false
    @State private var exportFile = ExportFile()
    /// Set when the selection sheet is confirmed; the file exporter is opened from `onDismiss` so it
    /// never races the selection sheet's own dismissal.
    @State private var hasPendingExport = false
    @State private var exportSuccessful = false

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppMigration.ExportAppsView")

    /// Bare stem (no extension) — `.plainText` appends `.txt`, so adding it here would double it.
    private static var defaultFilename: String {
        "Applite-export-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
    }

    /// Installed apps to offer for export, excluding Applite itself: an import only ever runs from
    /// inside a running Applite, so it is always already installed — listing it is redundant.
    /// (Mirrors `AppGridView`, which hides the self-cask.)
    private var exportableCasks: [CaskViewModel] {
        caskManager.installedViewModels.filter { $0.token != "applite" }
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(systemName: "tray.and.arrow.up.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("Export", comment: "App migration export card title")
                .font(.appliteSmallTitle)

            Text("Save your selected apps to a file you can import on another Mac.",
                 comment: "App Migration export card description")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button {
                showSelectionSheet = true
            } label: {
                Text("Export Apps…", comment: "App Migration export button")
            }
            .cardActionPill()
            .disabled(exportableCasks.isEmpty)

            statusLine
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showSelectionSheet, onDismiss: {
            if hasPendingExport {
                hasPendingExport = false
                showFileExporter = true
            }
        }) {
            CaskSelectionSheet(
                title: "Select Apps to Export",
                confirmLabel: "Export",
                casks: exportableCasks
            ) { selected in
                exportFile = ExportFile(initialText: AppMigration.makeBrewfile(from: selected))
                hasPendingExport = true
            }
        }
        .fileExporter(isPresented: $showFileExporter, document: exportFile, contentType: .plainText, defaultFilename: Self.defaultFilename) { result in
            switch result {
            case .success(let url):
                logger.notice("Successful cask export: \(url.path(percentEncoded: false))")
                withAnimation { exportSuccessful = true }
            case .failure(let error):
                logger.error("File exporter failed: \(error.localizedDescription)")
                caskManager.alert.show(error: error, title: "Failed to export")
            }
        }
    }

    /// Confirmation / waiting caption under the button. Shown in a fixed-height slot so the card
    /// layout doesn't shift when it appears.
    @ViewBuilder
    private var statusLine: some View {
        Group {
            if exportSuccessful {
                Label("Saved to file", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if exportableCasks.isEmpty && caskManager.isResolvingInstalledState {
                Text("Waiting for installed apps to load…", comment: "App Migration export waiting caption")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(height: 20)
    }
}
