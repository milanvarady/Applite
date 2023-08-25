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

func exportCasks(url: URL, exportType: CaskExportType) throws {
    let today = Date.now
    
    let formatter = DateFormatter()
    formatter.dateFormat = "y_MM_dd_HH:mm"
    let currentDateString = formatter.string(from: today)
    
    if exportType == .brewfile {
        let brewfileURL = url.appendingPathComponent("Brewfile_\(currentDateString)")
        
        let result = shell("\(BrewPaths.currentBrewExecutable) bundle dump --file=\"\(brewfileURL.path)\"")
        
        if result.didFail {
            throw CaskExportError.ExportError
        }
    } else {
        let result = shell("\(BrewPaths.currentBrewExecutable) list --cask")
        
        if result.didFail {
            throw CaskExportError.ExportError
        }
        
        let exportedCasks = result.output
        
        let fileURL = url.appendingPathComponent("applite_export_\(currentDateString).txt", conformingTo: .plainText)
        
        if let data = exportedCasks.data(using: .utf8) {
            do {
                try data.write(to: fileURL)
            } catch {
                throw CaskExportError.ExportError
            }
        }
    }
}
