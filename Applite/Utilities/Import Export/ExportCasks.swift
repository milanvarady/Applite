//
//  ExportCasks.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 11..
//

import Foundation

enum CaskExportError: Error {
    case ExportError
}

func exportCasks(url: URL) throws -> String {
    let result = shell("\(BrewPaths.currentBrewExecutable) list --cask")
    
    if result.didFail {
        throw CaskExportError.ExportError
    }
    
    let exportedCasks = result.output
    
    let fileURL = url.appendingPathComponent("applite_export.txt")
    
    if let data = exportedCasks.data(using: .utf8) {
        do {
            try data.write(to: fileURL)
        } catch {
            throw CaskExportError.ExportError
        }
    }
    
    return exportedCasks
}
