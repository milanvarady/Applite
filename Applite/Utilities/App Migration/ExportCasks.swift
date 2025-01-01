//
//  ExportCasks.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 11..
//

import Foundation
import OSLog

enum CaskImportError: Error {
    case EmptyFile
}

enum AppMigration {
    static func export() async throws -> ExportFile {
        let output = try await Shell.runBrewCommand(["list", "--cask"])

        let exportedCasks = output.trimmingCharacters(in: .whitespacesAndNewlines)

        return ExportFile(initialText: exportedCasks)
    }

    static func readCaskFile(url: URL) throws -> [CaskId] {
        let content = try String(contentsOf: url)
        var casks: [CaskId] = []
        let brewfileRegex = /cask "([\w-]+)"/

        // Check if the file being imported is a Brewfile
        // Brewfiles store casks as cask "caskName"
        if content.contains("cask \"") {
            // Brewfile
            let matches = content.matches(of: brewfileRegex)
            casks = matches.map({ String($0.1) })
        } else {
            // Try to load casks as an Applite txt file export
            casks = content.components(separatedBy: .newlines)

            // Trim whitespace
            casks = casks.map({ $0.trimmingCharacters(in: .whitespaces) })
        }

        // Remove empty elements
        casks = casks.filter({ !$0.isEmpty })

        if casks.isEmpty {
            throw CaskImportError.EmptyFile
        }

        return casks
    }
}
