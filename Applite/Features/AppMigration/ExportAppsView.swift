//
//  ExportAppsView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI
import ButtonKit
import OSLog

struct ExportAppsView: View {
    @State var showFileExporter = false
    @State var exportFile: ExportFile = .init()
    @State var exportSuccessful = false
    @State var alert = AlertManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppMigration.ExportAppsView")

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.up.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Export", comment: "App migration export card title")
                .font(.appliteSmallTitle)

            Text("Export all apps currently installed by Applite to a file.", comment: "App Migration export card description")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                AsyncButton {
                    // Handle the failure inside the action rather than via `.onButtonStateError`,
                    // which re-fires on every re-render while the button stays in its sticky error
                    // state — so dismissing the alert would immediately re-present it in a loop.
                    do {
                        exportFile = try await AppMigration.export()
                        showFileExporter = true
                    } catch {
                        alert.show(error: error, title: "Failed to export")
                    }
                } label: {
                    Label("Export Apps to File", systemImage: "square.and.arrow.up")
                }
                .controlSize(.large)

                if exportSuccessful {
                    Image(systemName: "square.and.arrow.down.badge.checkmark")
                        .foregroundStyle(.green)
                        .imageScale(.large)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .alertManager(alert)
        .fileExporter(isPresented: $showFileExporter, document: exportFile,  contentType: .plainText, defaultFilename: "applite_export") { result in
            switch result {
            case .success(let url):
                logger.notice("Successful cask export: \(url.path(percentEncoded: false))")
                withAnimation { exportSuccessful = true }
            case .failure(let error):
                logger.error("File exporter failed: \(error.localizedDescription)")
                alert.show(error: error, title: "Failed to export")
            }
        }
    }
}
