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

enum CaskToFileManager {
    static func export(url: URL, exportType: CaskExportType) async throws {
        let today = Date.now

        let formatter = DateFormatter()
        formatter.dateFormat = "y_MM_dd_HH:mm"
        let currentDateString = formatter.string(from: today)

        switch exportType {
        case .txtFile:
            let output = try await Shell.runAsync("\(BrewPaths.currentBrewExecutable) list --cask")

            let exportedCasks = output.trimmingCharacters(in: .whitespacesAndNewlines)

            let fileURL = url.appendingPathComponent("applite_export_\(currentDateString).txt", conformingTo: .plainText)

            let data = exportedCasks.data(using: .utf8)
            try data?.write(to: fileURL)
        case .brewfile:
            let brewfileURL = url.appendingPathComponent("Brewfile_\(currentDateString)")

            try await Shell.runAsync("\(BrewPaths.currentBrewExecutable) bundle dump --file=\"\(brewfileURL.path)\"")
        }
    }

    static func readCaskFile(url: URL) throws -> [String] {
        let content = try String(contentsOf: url)
        var casks: [String] = []
        let brewfileRegex = /cask "([\w-]+)"/

        if content.contains("cask \"") {
            // Brewfile
            let matches = content.matches(of: brewfileRegex)
            casks = matches.map({ String($0.1) })
        } else {
            // Txt file
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

    static func installImportedCasks(caskIds: [CaskId], caskManager: CaskManager) async {
        await withTaskGroup(of: Void.self) { group in
            for caskId in caskIds {
                guard let cask = await caskManager.casks[caskId] else {
                    continue
                }

                group.addTask {
                    if await !cask.isInstalled {
                        await caskManager.install(cask)
                    }
                }
            }
        }
    }
}
