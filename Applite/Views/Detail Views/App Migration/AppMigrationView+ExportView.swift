//
//  AppMigrationView+ExportView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI
import OSLog

extension AppMigrationView {
    struct ExportView: View {
        @State var showFileExporter = false
        @State var exportFile: ExportFile = .init()
        @State var exportSuccessful = false
        @StateObject var alert = AlertManager()

        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppMigrationView.ExportView")

        var body: some View {
            VStack(alignment: .leading) {
                Text("Export", comment: "App migration export card title")
                    .font(.appliteSmallTitle)

                HStack {
                    AsyncButton {
                        exportFile = try await AppMigration.export()
                        showFileExporter = true
                    } label: {
                        Label("Export Apps to File", systemImage: "square.and.arrow.up")
                    }
                    .onButtonError { error in
                        alert.show(error: error, title: "Failed to export")
                    }
                    .controlSize(.large)

                    if exportSuccessful {
                        Image(systemName: "square.and.arrow.down.badge.checkmark")
                            .foregroundStyle(.green)
                            .imageScale(.large)
                    }
                }
                .padding(.bottom, 10)

                Text("Export all apps currently installed by Applite to a file.", comment: "App Migration export card description")

                Spacer()
            }
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
}
